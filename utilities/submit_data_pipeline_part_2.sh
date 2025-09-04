#!/usr/bin/env bash
#SBATCH --job-name=AF3_pairing
#SBATCH --time=00:10:00
#SBATCH --output=slurm-output/slurm-%j-%x.out # %j (Job ID) %x (Job Name)

# ------------------------------
# Check required environment variables
# ------------------------------
echo "MODE = '$MODE'"
echo "SEEDS = '$SEEDS'"
echo "SORTING = '$SORTING'"
echo "INPUT_FILE = '$INPUT_FILE'"
echo "TOTAL_INFERENCE_JOBS = '$TOTAL_INFERENCE_JOBS'"
echo "OUR_ARRAY_SIZE = '$OUR_ARRAY_SIZE'"
echo "RESULTS_PER_DIR = '$RESULTS_PER_DIR'"
echo "STATISTICS_FILE = '$STATISTICS_FILE'"

rm -rf data_pipeline_inputs
echo "size,inference_id,inference_name,job_id,task_id,node,tokens,bucket_size,iptm,ptm,ranking_score,start_time,end_time" > $STATISTICS_FILE

# ------------------------------
# Phase 1: Run make_inference_inputs.py
# ------------------------------

read SMALL_JOBS LARGE_JOBS < <(
    python3 utilities/make_inference_inputs.py "$INPUT_FILE" --seeds "$SEEDS" --sorting "$SORTING" --mode "$MODE"
)
echo "Small jobs (Tokens <= 3072): $SMALL_JOBS"
echo "Large jobs (Tokens > 3072): $LARGE_JOBS"
echo "Total jobs (calculated): $TOTAL_INFERENCE_JOBS"

if [[ $TOTAL_INFERENCE_JOBS -ne $((SMALL_JOBS + LARGE_JOBS)) ]]; then
    echo "ERROR: Mismatch in job counts! Check the code and resubmit the job. Datapipeline data can be reused if unmoved and undeleted." >&2
    exit 1
fi

# ------------------------------
# Phase 2: Submit inference jobs
# ------------------------------

# Small jobs
if [[ $SMALL_JOBS -gt 0 ]]; then
    FIRST_CHUNK_SIZE_SMALL=$(( SMALL_JOBS < OUR_ARRAY_SIZE ? SMALL_JOBS : OUR_ARRAY_SIZE ))
    echo "Submitting small inference jobs (0-$((FIRST_CHUNK_SIZE_SMALL - 1)))."
    sbatch --array=0-$(( FIRST_CHUNK_SIZE_SMALL - 1 )) \
           --export=TOTAL_INFERENCE_JOBS=$SMALL_JOBS,OUR_ARRAY_SIZE,RESULTS_PER_DIR,STATISTICS_FILE,START_OFFSET=0,JOB_SIZE=small \
           --gres=gpu:a100-40g:1 \
           utilities/af3_inference_only_slurm.sh
else
    echo "No small inference jobs to submit."
fi

# Large jobs
if [[ $LARGE_JOBS -gt 0 ]]; then
    FIRST_CHUNK_SIZE_LARGE=$(( LARGE_JOBS < OUR_ARRAY_SIZE ? LARGE_JOBS : OUR_ARRAY_SIZE ))
    echo "Submitting large inference jobs (0-$((FIRST_CHUNK_SIZE_LARGE - 1)))."
    sbatch --array=0-$(( FIRST_CHUNK_SIZE_LARGE - 1 )) \
           --export=TOTAL_INFERENCE_JOBS=$LARGE_JOBS,OUR_ARRAY_SIZE,RESULTS_PER_DIR,STATISTICS_FILE,START_OFFSET=0,JOB_SIZE=large \
           --gres=gpu:a100-80g:1 \
           utilities/af3_inference_only_slurm.sh
else
    echo "No large inference jobs to submit."
fi
