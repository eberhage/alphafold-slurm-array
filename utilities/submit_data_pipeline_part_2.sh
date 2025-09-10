#!/usr/bin/env bash
#SBATCH --job-name=AF3_pairing
#SBATCH --time=00:10:00
#SBATCH --output=slurm-output/slurm-%j-%x.out # %j (Job ID) %x (Job Name)

rm -rf data_pipeline_inputs

if [[ -n "${INFERENCE_STATISTICS_FILE:-}" ]]; then
    # Rotate existing statistics file if it exists
    if [ -f "$INFERENCE_STATISTICS_FILE" ]; then
        backup="${INFERENCE_STATISTICS_FILE}.old"
        i=1
        # Find the first unused backup name
        while [ -f "$backup" ]; do
            backup="${INFERENCE_STATISTICS_FILE}.${i}.old"
            i=$((i+1))
        done
        mv "$INFERENCE_STATISTICS_FILE" "$backup"
    fi
    echo "size,inference_id,inference_name,job_id,task_id,node,tokens,bucket_size,iptm,ptm,ranking_score,start_time,end_time" > "$INFERENCE_STATISTICS_FILE"
fi

# ------------------------------
# Phase 1: Run make_inference_inputs.py
# ------------------------------

read SMALL_JOBS LARGE_JOBS TOO_BIG_JOBS < <(python3 utilities/make_inference_inputs.py)
echo "Small jobs (Tokens ≤ ${SMALL_JOBS_UPPER_LIMIT}): $SMALL_JOBS"
echo "Large jobs (${SMALL_JOBS_UPPER_LIMIT} < Tokens ≤ ${LARGE_JOBS_UPPER_LIMIT}): $LARGE_JOBS"
echo "Too big jobs (Tokens > ${LARGE_JOBS_UPPER_LIMIT}): $TOO_BIG_JOBS"
echo "Total jobs (calculated): $TOTAL_INFERENCE_JOBS"

if [[ $TOTAL_INFERENCE_JOBS -ne $((SMALL_JOBS + LARGE_JOBS + TOO_BIG_JOBS)) ]]; then
    echo "ERROR: Mismatch in job counts! Check the code and resubmit the job. Datapipeline data can be reused if unmoved and undeleted." >&2
    exit 1
fi

# ------------------------------
# Phase 2: Submit inference jobs
# ------------------------------

for job_size in small large; do
    job_count_var="$(echo "${job_size^^}_JOBS")"   # e.g. SMALL_JOBS, LARGE_JOBS
    gpu_type_var="$(echo "${job_size^^}_GPU")"     # e.g. SMALL_GPU, LARGE_GPU

    job_count="${!job_count_var}"
    gpu_type="${!gpu_type_var}"

    if [[ $job_count -gt 0 ]]; then
        first_chunk_size=$(( job_count < OUR_ARRAY_SIZE ? job_count : OUR_ARRAY_SIZE ))
        echo "Submitting ${job_size} inference jobs (0-$((first_chunk_size - 1)))."
        sbatch --array=0-$(( first_chunk_size - 1 )) \
               --partition="${INFERENCE_PARTITION}" \
               --gres=gpu:${gpu_type}:1 \
               --export=ALL,TOTAL_INFERENCE_JOBS=$job_count,START_OFFSET=0,JOB_SIZE=$job_size,GPU_TYPE=$gpu_type \
               utilities/af3_inference_only_slurm.sh
    else
        echo "No ${job_size} inference jobs to submit."
    fi
done
