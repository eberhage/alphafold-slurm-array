#!/bin/bash
#SBATCH --job-name=AF3_inference
#SBATCH --cpus-per-task=8
#SBATCH --gpus-per-task=1
#SBATCH --threads-per-core=1                    # Disable Multithreading
#SBATCH --hint=nomultithread
#SBATCH --output=slurm-output/slurm-%A_%a-%x.out # %j (Job ID) %x (Job Name)
echo "Job ran on:" $(hostname)
echo ""

WORKDIR=$(pwd)

export INFERENCE_ID=$(( SLURM_ARRAY_TASK_ID + START_OFFSET ))
scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} comment="Task $((INFERENCE_ID + 1)) of ${TOTAL_INFERENCE_JOBS}"

# Compute start and end of the bucket
bucket_start=$(( (INFERENCE_ID / RESULTS_PER_DIR) * RESULTS_PER_DIR ))
bucket_end=$(( bucket_start + RESULTS_PER_DIR - 1 ))

# Handle last bucket
LAST_INFERENCE_ID=$(( SLURM_ARRAY_TASK_MAX + START_OFFSET ))
if [ $bucket_end -gt $LAST_INFERENCE_ID ]; then
    bucket_end=$LAST_INFERENCE_ID
fi

if [[ "$SLURM_ARRAY_TASK_ID" -eq 0 ]]; then
    next_start=$(( START_OFFSET + SLURM_ARRAY_TASK_COUNT ))
    if (( next_start < TOTAL_INFERENCE_JOBS )); then
        next_end=$(( next_start + OUR_ARRAY_SIZE - 1 ))
        if (( next_end >= TOTAL_INFERENCE_JOBS )); then
            next_end=$(( TOTAL_INFERENCE_JOBS - 1 ))
        fi
        # Submit the next chunk
        sbatch --array=0-$(( next_end - next_start )) \
               --partition=${INFERENCE_PARTITION} \
               --gres=${GPU_TYPE}:1 \
               --time=${GPU_TIME} \
               --ntasks=1 \
               --dependency=afterok:${SLURM_ARRAY_JOB_ID} \
               --export=ALL,START_OFFSET=$next_start \
               $WORKDIR/utilities/af3_inference_only_slurm.sh
        echo "Submitted next chunk: $next_start-$next_end (dependent on job ${SLURM_ARRAY_JOB_ID})"
    fi
fi

srun --ntasks=1 $WORKDIR/utilities/af3_inference_task.sh