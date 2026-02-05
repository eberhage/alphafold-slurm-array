#!/bin/bash
#SBATCH --job-name=AF3_inference
#SBATCH --cpus-per-task=8
#SBATCH --ntasks=1
#SBATCH --threads-per-core=1                    # Disable Multithreading
#SBATCH --hint=nomultithread
#SBATCH --output=slurm-output/slurm-%A_%a-%x.out # %j (Job ID) %x (Job Name)
echo "Job ran on:" $(hostname)
echo ""

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

WORKDIR=$(pwd)
user_input_file=$WORKDIR/pending_jobs/${PIPELINE_RUN_ID}/${GPU_PROFILE}/${INFERENCE_ID}_*.json
AF3_input_file=$(basename $user_input_file)
AF3_input_path=$WORKDIR/tmp/input_${SLURM_ARRAY_JOB_ID}/${SLURM_ARRAY_TASK_ID}
AF3_output_path=$WORKDIR/results/${SLURM_ARRAY_JOB_ID}_${GPU_PROFILE}_${bucket_start}-${bucket_end}
AF3_cache_path=$WORKDIR/tmp/af3_cache_${SLURM_ARRAY_JOB_ID}/${SLURM_ARRAY_TASK_ID} # Cache directory
export APPTAINER_TMPDIR=$WORKDIR/tmp/apptainer_${SLURM_ARRAY_JOB_ID}/${SLURM_ARRAY_TASK_ID}

# --- Only the first task handles submitting the next chunk ---
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
               --gres=gpu:${GPU_TYPE}:1 \
               --time=${GPU_TIME} \
               --dependency=afterok:${SLURM_ARRAY_JOB_ID} \
               --export=ALL,START_OFFSET=$next_start \
               $WORKDIR/utilities/af3_inference_only_slurm.sh
        echo "Submitted next chunk: $next_start-$next_end (dependent on job ${SLURM_ARRAY_JOB_ID})"
    fi
fi
# --- End of Task-0 block ---

mkdir -p "$AF3_input_path"
mkdir -p "$AF3_output_path"
mkdir -p "$AF3_cache_path"
mkdir -p "$APPTAINER_TMPDIR"
python3 utilities/copy_json_and_dependency_files.py $user_input_file "$AF3_input_path"
rm $user_input_file

if [[ "$ENABLE_XLA" == "true" ]]; then
    echo "XLA activated"
    export APPTAINERENV_XLA_PYTHON_CLIENT_PREALLOCATE=false
    export APPTAINERENV_TF_FORCE_UNIFIED_MEMORY=true
    export APPTAINERENV_XLA_CLIENT_MEM_FRACTION=3.2
else
    echo "XLA not activated"
fi
export APPTAINER_BINDPATH="/${AF3_input_path}:/root/af_input,${AF3_output_path}:/root/af_output,${AF3_MODEL_PATH}:/root/models,${AF3_DB_PATH}:/root/public_databases,${AF3_cache_path}:/root/jax_cache_dir"

# Extract the protein name  and compound id from the JSON
export INFERENCE_NAME=$(jq -r '.name' "$AF3_input_path"/"$AF3_input_file")
export COMPOUND_ID=$(jq -r '.sequences[-1].ligand?.description' "$AF3_input_path/$AF3_input_file")
export INFERENCE_DIR=${AF3_output_path}/${INFERENCE_NAME}

echo "Running AlphaFold job for ${INFERENCE_NAME} (index ${SLURM_ARRAY_TASK_ID}, total-index: ${INFERENCE_ID})"

start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

af_output=$(apptainer exec --writable-tmpfs --nv ${AF3_CONTAINER_PATH} python /app/alphafold/run_alphafold.py \
    --run_data_pipeline=false \
    --json_path=/root/af_input/${AF3_input_file} \
    --model_dir=/root/models \
    --output_dir=/root/af_output \
    --jax_compilation_cache_dir=/root/jax_cache_dir \
2>&1 | tee -a "slurm-output/slurm-${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}-${SLURM_JOB_NAME}.out")

unset APPTAINER_BINDPATH

if [[ -n "${INFERENCE_STATISTICS_FILE:-}" && -f "$INFERENCE_STATISTICS_FILE" ]]; then
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    read bucket_size tokens < <(echo "$af_output" | awk '/Got bucket size/ {
        match($0, /Got bucket size ([0-9]+) for input with ([0-9]+)/, a);
        print a[1], a[2];
        exit
    }')

    confidences=$(python $WORKDIR/utilities/collect_af3_confidences.py "${INFERENCE_DIR}" "${INFERENCE_NAME}")

    jq -cn  --arg runid "$PIPELINE_RUN_ID" \
            --arg profile "$GPU_PROFILE" \
            --argjson a "$INFERENCE_ID" \
            --arg b "$INFERENCE_NAME" \
            --arg compoundid "$COMPOUND_ID" \
            --argjson c "$SLURM_ARRAY_JOB_ID" \
            --argjson d "$SLURM_ARRAY_TASK_ID" \
            --arg e "$(hostname)" \
            --argjson f "$tokens" \
            --argjson g "$bucket_size" \
            --arg h "$start_time" \
            --arg i "$end_time" \
            --argjson confidences "$confidences" \
            '{
                "pipeline_run_id": $runid,
                "gpu_profile": $profile,
                "inference_id": $a,
                "name": $b,
                "compound_id": (if $compoundid == "null" then null else $compoundid end),
                "array_job": $c,
                "array_task": $d,
                "hostname": $e,
                "tokens": $f,
                "bucket_size": $g,
                "start_time": $h,
                "end_time": $i,
                "af3_confidences": $confidences
            }' >> "$INFERENCE_STATISTICS_FILE"
fi

rm -rf $AF3_cache_path
rm -rf $APPTAINER_TMPDIR
rm -rf $AF3_input_path

# --- Postprocessing ---
if [[ -n "${POSTPROCESSING_SCRIPT:-}" && -f "$POSTPROCESSING_SCRIPT" ]]; then
    sbatch --output="slurm-output/slurm-${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}-${SLURM_JOB_NAME}.out" \
           --open-mode=append \
           ${POSTPROCESSING_SCRIPT}
fi
