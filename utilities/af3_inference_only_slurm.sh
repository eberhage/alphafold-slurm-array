#!/bin/bash
#SBATCH --job-name=AF3_inference
#SBATCH --cpus-per-task=8
#SBATCH --threads-per-core=1                    # Disable Multithreading
#SBATCH --hint=nomultithread
#SBATCH --output=slurm-output/slurm-%A_%a_0-%x.out # %j (Job ID) %x (Job Name)

WORKDIR=$(pwd)

# Compute first and last INFERENCE_IDs for this array task
first_task_inference_id=$(( START_OFFSET + PARALLEL_TASKS * SLURM_ARRAY_TASK_ID ))
last_task_inference_id=$(( first_task_inference_id + PARALLEL_TASKS - 1 ))
(( last_task_inference_id >= TOTAL_INFERENCE_JOBS )) && last_task_inference_id=$(( TOTAL_INFERENCE_JOBS - 1 ))

# Update Slurm comment
if (( first_task_inference_id == last_task_inference_id )); then
    task_comment="$((first_task_inference_id + 1))"
else
    task_comment="$((first_task_inference_id + 1))-$((last_task_inference_id + 1))"
fi
scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} comment="Task $task_comment of ${TOTAL_INFERENCE_JOBS}"

# Submit next chunk if this is the first array task
if [[ "$SLURM_ARRAY_TASK_ID" -eq 0 ]]; then
    next_start=$(( START_OFFSET + PARALLEL_TASKS * SLURM_ARRAY_TASK_COUNT ))
    if (( next_start < TOTAL_INFERENCE_JOBS )); then
        max_array_size=$(utilities/determine_array_size.sh "$INFERENCE_PARTITION")
        echo "Determined maximum array size $max_array_size for partition $INFERENCE_PARTITION"
        next_end=$(( next_start + PARALLEL_TASKS * max_array_size - 1 ))
        if (( next_end >= TOTAL_INFERENCE_JOBS )); then
            next_end=$(( TOTAL_INFERENCE_JOBS - 1 ))
        fi

        # Compute next array size considering parallel_tasks
        next_array_size=$(( (next_end - next_start + PARALLEL_TASKS) / PARALLEL_TASKS ))

        job_info=$(sbatch --array=0-$(( next_array_size - 1 )) \
                          --partition=${INFERENCE_PARTITION} \
                          --gres=${GRES} \
                          --gpus-per-task=${GPUS_PER_TASK} \
                          --time=${GPU_TIME} \
                          --ntasks=${PARALLEL_TASKS} \
                          --dependency=afterok:${SLURM_ARRAY_JOB_ID} \
                          --export=ALL,START_OFFSET=$next_start \
                          --parsable \
                          $WORKDIR/utilities/af3_inference_only_slurm.sh)
        echo "Submitted next chunk: $next_start-$next_end (dependent on job ${SLURM_ARRAY_JOB_ID}). Job info: $job_info"

        if [[ -n "${POSTPROCESSING_SCRIPT:-}" && -f "$POSTPROCESSING_SCRIPT" && "$POSTPROCESSING_LEVEL" == "array" ]]; then
            sbatch --output="slurm-output/slurm-%j_%x.out" \
                   --dependency=afterok:${job_info%%;*} \
                   --export=ALL,FIRST_INFERENCE_ID=$next_start,LAST_INFERENCE_ID=$next_end \
                   "${POSTPROCESSING_SCRIPT}"
            echo "Postprocessing on array level submitted. Dependency=afterok:${job_info%%;*}"
        fi
    fi
fi

export FIRST_INFERENCE_ID=$first_task_inference_id
export LAST_INFERENCE_ID=$last_task_inference_id

srun --ntasks=$(( LAST_INFERENCE_ID - FIRST_INFERENCE_ID + 1 )) \
     --output=slurm-output/slurm-%A_%a_%t-%x.out \
     --open-mode=append \
     $WORKDIR/utilities/af3_inference_task.sh

# --- Postprocessing ---
if [[ -n "${POSTPROCESSING_SCRIPT:-}" && -f "$POSTPROCESSING_SCRIPT" && "$POSTPROCESSING_LEVEL" == "job" ]]; then
    sbatch --output="slurm-output/slurm-${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}_0-${SLURM_JOB_NAME}.out" \
           --open-mode=append \
           "${POSTPROCESSING_SCRIPT}"
fi