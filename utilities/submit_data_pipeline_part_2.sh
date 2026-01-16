#!/usr/bin/env bash
#SBATCH --job-name=AF3_part_2
#SBATCH --time=01:00:00
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
    touch $INFERENCE_STATISTICS_FILE
    # echo "gpu_profile,inference_id,inference_name,job_id,task_id,node,tokens,bucket_size,best_iptm,best_ptm,best_ranking_score,avg_iptm,stdev_iptm,avg_ptm,stdev_ptm,avg_ranking_score,stdev_ranking_score,start_time,end_time" > "$INFERENCE_STATISTICS_FILE"
fi

# ------------------------------
# Phase 1: Run make_inference_inputs.py and parse job info
# ------------------------------

# Run Python function to generate job info
json_output=$(python3 utilities/make_inference_inputs.py)

# Extract total jobs and too big jobs
TOTAL_INFERENCE_JOBS=$(echo "$json_output" | jq -r '.total_jobs')
TOO_BIG_JOBS=$(echo "$json_output" | jq -r '.too_big_jobs | length')

# Reconstruct array
IFS=',' read -ra GPU_PROFILES_ARRAY <<< "$GPU_PROFILES"

# Extract jobs per profile into associative arrays
declare -A JOB_COUNTS BOUND_MIN BOUND_MAX
for profile in "${GPU_PROFILES_ARRAY[@]}"; do
    # Check profile exists in JSON
    if ! echo "$json_output" | jq -e --arg p "$profile" '.profiles | has($p)' >/dev/null; then
        echo "Error: Profile '$profile' missing in JSON output" >&2
        exit 1
    fi

    JOB_COUNTS[$profile]=$(echo "$json_output" | jq -r --arg p "$profile" '.profiles[$p].jobs')
    BOUND_MIN[$profile]=$(echo "$json_output" | jq -r --arg p "$profile" '.profiles[$p].min')
    BOUND_MAX[$profile]=$(echo "$json_output" | jq -r --arg p "$profile" '.profiles[$p].max')
done

# Logging
echo "Total jobs (calculated): $TOTAL_INFERENCE_JOBS"
for profile in "${GPU_PROFILES_ARRAY[@]}"; do
    echo "Jobs for profile '$profile' (Tokens ${BOUND_MIN[$profile]}-${BOUND_MAX[$profile]}): ${JOB_COUNTS[$profile]}"
done
echo "Too big jobs (Tokens > ${BOUND_MAX[${GPU_PROFILES_ARRAY[-1]}]}): $TOO_BIG_JOBS"

# Sanity check: sum of profile jobs + too big jobs should equal total jobs
sum=0
for profile in "${GPU_PROFILES_ARRAY[@]}"; do
    sum=$((sum + JOB_COUNTS[$profile]))
done
sum=$((sum + TOO_BIG_JOBS))

if [[ $sum -ne $TOTAL_INFERENCE_JOBS ]]; then
    echo "ERROR: Mismatch in job counts! Sum of profile jobs + too big ($sum) != total jobs ($TOTAL_INFERENCE_JOBS)." >&2
    exit 1
fi

IFS=',' read -ra seed_array <<< "$SEEDS"
num_seeds=${#seed_array[@]}

# ------------------------------
# Phase 2: Submit inference jobs
# ------------------------------

# Loop over all selected GPU profiles
for profile in "${GPU_PROFILES_ARRAY[@]}"; do
    job_count=${JOB_COUNTS[$profile]:-0}
    gpu_type=$(jq -r --arg p "$profile" '.gpu_profiles[$p].gres' "$CLUSTER_CONFIG")
    enable_xla=$(jq -r --arg p "$profile" '.gpu_profiles[$p].enable_xla // false' "$CLUSTER_CONFIG")
    max_minutes=$(jq -r --arg p "$profile" '.gpu_profiles[$p].max_minutes_per_seed' "$CLUSTER_CONFIG")
    gpu_time=$(( max_minutes * num_seeds ))

    if [[ $job_count -gt 0 ]]; then
        first_chunk_size=$(( job_count < OUR_ARRAY_SIZE ? job_count : OUR_ARRAY_SIZE ))
        echo "Submitting ${profile} inference jobs (0-$((first_chunk_size - 1))) with GPU '$gpu_type.'"
        sbatch --array=0-$(( first_chunk_size - 1 )) \
               --partition="${INFERENCE_PARTITION}" \
               --gres=gpu:${gpu_type}:1 \
               --time=${gpu_time} \
               --export=ALL,TOTAL_INFERENCE_JOBS=$job_count,START_OFFSET=0,GPU_PROFILE=$profile,GPU_TYPE=$gpu_type,ENABLE_XLA=$enable_xla,GPU_TIME=$gpu_time \
               utilities/af3_inference_only_slurm.sh
    else
        echo "No jobs to submit for GPU profile '$profile'."
    fi
done