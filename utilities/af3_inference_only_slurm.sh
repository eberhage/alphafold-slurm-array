#!/bin/bash
#SBATCH --job-name=AF3_inference
#SBATCH --cpus-per-task=8
#SBATCH --time=06:00:00
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
user_input_file=$WORKDIR/pending_jobs/${GPU_PROFILE}/${INFERENCE_ID}_*.json
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

export APPTAINER_BINDPATH="/${AF3_input_path}:/root/af_input,${AF3_output_path}:/root/af_output,${AF3_MODEL_PATH}:/root/models,${AF3_DB_PATH}:/root/public_databases,${AF3_cache_path}:/root/jax_cache_dir"

# Extract the protein name from the JSON
export INFERENCE_NAME=$(jq -r '.name' "$AF3_input_path"/"$AF3_input_file")
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

if [[ -n "${INFERENCE_STATISTICS_FILE:-}" && -f "$INFERENCE_STATISTICS_FILE" ]]; then
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    read bucket_size tokens < <(echo "$af_output" | awk '/Got bucket size/ {
        match($0, /Got bucket size ([0-9]+) for input with ([0-9]+)/, a);
        print a[1], a[2];
        exit
    }')

    # extract best prediction scores
    read best_iptm best_ptm best_ranking_score < <(
        jq -r '[.iptm, .ptm, .ranking_score] | @tsv' \
        "${INFERENCE_DIR}/${INFERENCE_NAME}_summary_confidences.json"
    )

    # collect per-model scores
    scores=$(find "${INFERENCE_DIR}" -type f -path "${INFERENCE_DIR}/seed-*_sample-*/${INFERENCE_NAME}_seed-*_sample-*_summary_confidences.json")

    # compute averages + stddevs
    if [[ -n "$scores" ]]; then
        read avg_iptm std_iptm avg_ptm std_ptm avg_rank std_rank < <(
            jq -s -r '
                [.[].iptm] as $iptm |
                [.[].ptm] as $ptm |
                [.[].ranking_score] as $rank |
                def mean(a): (a | add / length);
                def std(a): if (a | length) > 1 then ((a | map((. - (a | add / (a | length))) * (. - (a | add / (a | length)))) | add) / ((a | length) - 1)) | sqrt else 0 end;
                [ mean($iptm), std($iptm),
                  mean($ptm), std($ptm),
                  mean($rank), std($rank) ] | map((. * 10000 | round) / 10000) | @tsv
            ' $scores
        )
    else
        avg_iptm= avg_ptm= avg_rank= std_iptm= std_ptm= std_rank=
    fi

    # write statistics (added averages + stddevs)
    echo "${GPU_PROFILE},${INFERENCE_ID},${INFERENCE_NAME},${SLURM_ARRAY_JOB_ID},${SLURM_ARRAY_TASK_ID},$(hostname),${tokens},${bucket_size},${best_iptm},${best_ptm},${best_ranking_score},${avg_iptm},${std_iptm},${avg_ptm},${std_ptm},${avg_rank},${std_rank},${start_time},${end_time}" >> "$INFERENCE_STATISTICS_FILE"
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
