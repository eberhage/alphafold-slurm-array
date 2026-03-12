#!/bin/bash
echo "Job ran on:" $(hostname)

WORKDIR=$(pwd)

export INFERENCE_ID=$(( FIRST_INFERENCE_ID + SLURM_PROCID ))

# Compute last theoretical inference ID covered by this array chunk
last_inference_id=$(( START_OFFSET + PARALLEL_TASKS * (SLURM_ARRAY_TASK_MAX + 1) - 1 ))

# Clamp to total job count
global_last_id=$(( TOTAL_INFERENCE_JOBS - 1 ))
if (( last_inference_id > global_last_id )); then
    last_inference_id=$global_last_id
fi

# Compute start and end of the bucket
bucket_start=$(( (INFERENCE_ID / RESULTS_PER_DIR) * RESULTS_PER_DIR ))
bucket_end=$(( bucket_start + RESULTS_PER_DIR - 1 ))
if (( bucket_end > last_inference_id )); then
    bucket_end=$last_inference_id
fi

user_input_file=$WORKDIR/pending_jobs/${PIPELINE_RUN_ID}/${GPU_PROFILE}/${INFERENCE_ID}_*.json
AF3_input_file=$(basename $user_input_file)
AF3_input_path=$WORKDIR/tmp/input_${PIPELINE_RUN_ID}/${GPU_PROFILE}/${INFERENCE_ID}
AF3_output_path=$WORKDIR/results/${PIPELINE_RUN_ID}_${GPU_PROFILE}_${bucket_start}-${bucket_end}
AF3_cache_path=$WORKDIR/tmp/af3_cache_${PIPELINE_RUN_ID}/${GPU_PROFILE}/${INFERENCE_ID} # Cache directory
export APPTAINER_TMPDIR=$WORKDIR/tmp/apptainer_${PIPELINE_RUN_ID}/${GPU_PROFILE}/${INFERENCE_ID}

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

# Extract the protein name from the JSON
export INFERENCE_NAME=$(jq -r '.name' "$AF3_input_path"/"$AF3_input_file")
export INFERENCE_DIR=${AF3_output_path}/${INFERENCE_NAME}

echo "Running AlphaFold job for ${INFERENCE_NAME} (SLURM_ARRAY_TASK_ID: ${SLURM_ARRAY_TASK_ID}, INFERENCE_ID: ${INFERENCE_ID}, SLURM_PROCID: ${SLURM_PROCID})"

start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

af_output=$(apptainer exec --writable-tmpfs --nv ${AF3_CONTAINER_PATH} python /app/alphafold/run_alphafold.py \
    --run_data_pipeline=false \
    --json_path=/root/af_input/${AF3_input_file} \
    --model_dir=/root/models \
    --output_dir=/root/af_output \
    --jax_compilation_cache_dir=/root/jax_cache_dir \
2>&1 | tee -a "slurm-output/slurm-${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}_${SLURM_PROCID}-${SLURM_JOB_NAME}.out")

unset APPTAINER_BINDPATH

if [[ -n "${INFERENCE_STATISTICS_FILE:-}" ]]; then
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    read bucket_size tokens < <(echo "$af_output" | awk '/Got bucket size/ {
        match($0, /Got bucket size ([0-9]+) for input with ([0-9]+)/, a);
        print a[1], a[2];
        exit
    }')

    confidences=$(python3 $WORKDIR/utilities/collect_af3_confidences.py "${INFERENCE_DIR}" "${INFERENCE_NAME}")

    log_object=$(jq -cn \
            --arg runid "$PIPELINE_RUN_ID" \
            --arg profile "$GPU_PROFILE" \
            --argjson a "$INFERENCE_ID" \
            --arg b "$INFERENCE_NAME" \
            --argjson c "$SLURM_ARRAY_JOB_ID" \
            --argjson d "$SLURM_ARRAY_TASK_ID" \
            --argjson procid "$SLURM_PROCID" \
            --arg e "$(hostname)" \
            --argjson f "$tokens" \
            --argjson g "$bucket_size" \
            --arg h "$start_time" \
            --arg i "$end_time" \
            --argjson confidences "$confidences" \
            --slurpfile af3input "$AF3_input_path/$AF3_input_file" \
            '{
                "pipeline_run_id": $runid,
                "gpu_profile": $profile,
                "inference_id": $a,
                "name": $b,
                "components": ([ $af3input[0].sequences[] | .[] | select(has("description")) | .description ]),
                "array_job": $c,
                "array_task": $d,
                "procid": $procid,
                "hostname": $e,
                "tokens": $f,
                "bucket_size": $g,
                "start_time": $h,
                "end_time": $i,
                "af3_confidences": $confidences
            }')

    mkdir -p "$(dirname "$INFERENCE_STATISTICS_FILE")"

    (
        flock -x -w 30 200 || exit 1
        printf '%s\n' "$log_object" >> "$INFERENCE_STATISTICS_FILE"
    ) 200>"$INFERENCE_STATISTICS_FILE.lock"
fi

rm -rf $AF3_cache_path
rm -rf $APPTAINER_TMPDIR
rm -rf $AF3_input_path

# --- Postprocessing ---
if [[ -n "${POSTPROCESSING_SCRIPT:-}" && -f "$POSTPROCESSING_SCRIPT" ]]; then
    sbatch --output="slurm-output/slurm-${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}_${SLURM_PROCID}-${SLURM_JOB_NAME}.out" \
           --open-mode=append \
           ${POSTPROCESSING_SCRIPT}
fi