#!/bin/bash

# Parse cluster settings
export AF3_CONTAINER_PATH=$(jq -r '.af3_container_path' "$CLUSTER_CONFIG")
export AF3_MODEL_PATH=$(jq -r '.af3_model_path' "$CLUSTER_CONFIG")
export AF3_DB_PATH=$(jq -r '.af3_db_path' "$CLUSTER_CONFIG")

# Validate paths
if [ ! -f "$AF3_CONTAINER_PATH" ]; then
    echo "Error: AF3_CONTAINER_PATH does not point to a file: $AF3_CONTAINER_PATH" >&2
    exit 1
fi

if [ ! -d "$AF3_MODEL_PATH" ]; then
    echo "Error: AF3_MODEL_PATH does not point to a directory: $AF3_MODEL_PATH" >&2
    exit 1
fi

if [ ! -d "$AF3_DB_PATH" ]; then
    echo "Error: AF3_DB_PATH does not point to a directory: $AF3_DB_PATH" >&2
    exit 1
fi

export DATAPIPELINE_PARTITION=$(jq -r '.datapipeline_partition' "$CLUSTER_CONFIG")
export INFERENCE_PARTITION=$(jq -r '.inference_partition' "$CLUSTER_CONFIG")

check_partition() {
    local partition=$1
    if ! sinfo -h -o "%R" | awk -v p="$partition" '$1 == p {found=1} END {exit !found}'; then
        echo "Error: SLURM partition '$partition' is not available on this cluster" >&2
        exit 1
    fi
}

check_partition "$DATAPIPELINE_PARTITION"
check_partition "$INFERENCE_PARTITION"

# MODE must be cartesian or collapsed
if [[ "$MODE" != "cartesian" && "$MODE" != "collapsed" ]]; then
    echo "ERROR: MODE must be 'cartesian' or 'collapsed'." >&2
    exit 1
fi

# SORTING must be alpha or input
if [[ "$SORTING" != "alpha" && "$SORTING" != "input" ]]; then
    echo "ERROR: SORTING must be 'alpha' or 'input'." >&2
    exit 1
fi

# INPUT_FILE must exist and be readable
if [[ -z "${INPUT_FILE:-}" ]]; then
    echo "ERROR: INPUT_FILE is not set." >&2
    exit 1
elif [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: INPUT_FILE '$INPUT_FILE' not found." >&2
    exit 1
fi

if ! [[ "${SEEDS:-}" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    echo "ERROR: SEEDS must be a comma-separated list of integers (e.g. 0,1,2)." >&2
    exit 1
fi

# RESULTS_PER_DIR must be an integer > 0
if ! [[ "$RESULTS_PER_DIR" =~ ^[0-9]+$ ]] || (( RESULTS_PER_DIR <= 0 )); then
    echo "ERROR: RESULTS_PER_DIR must be a positive integer." >&2
    exit 1
fi

# Default to all profiles if user didn't specify
if [[ -z "${GPU_PROFILES:-}" ]]; then
    readarray -t GPU_PROFILES_ARRAY < <(jq -r '.gpu_profiles | keys | .[]' "$CLUSTER_CONFIG")
    GPU_PROFILES=$(IFS=','; echo "${GPU_PROFILES_ARRAY[*]}")
fi

check_gres_in_partition() {
    local partition=$1
    local gres=$2
    local profile=$3
    # Get list of GRES in the partition
    local available_gres
    available_gres=$(sinfo -h -o "%G" -p "$partition" | tr ',' '\n' | sort -u)

    if ! echo "$available_gres" | grep -q -w "$gres"; then
        echo "Error: GRES '$gres' for GPU profile '$profile' is not available in partition '$partition'" >&2
        exit 1
    fi
}

IFS=',' read -ra GPU_PROFILES_ARRAY <<< "$GPU_PROFILES"
declare -A GPU_LIMITS GPU_GRES
for profile in "${GPU_PROFILES_ARRAY[@]}"; do
    # Check if profile exists in cluster config
    if ! jq -e --arg p "$profile" '.gpu_profiles[$p]' "$CLUSTER_CONFIG" > /dev/null; then
        echo "Error: GPU profile '$profile' not found in cluster config ($CLUSTER_CONFIG)" >&2
        exit 1
    fi

    # Parse gres and token_limit
    GPU_GRES[$profile]=$(jq -r --arg p "$profile" '.gpu_profiles[$p].gres' "$CLUSTER_CONFIG")
    GPU_LIMITS[$profile]=$(jq -r --arg p "$profile" '.gpu_profiles[$p].token_limit' "$CLUSTER_CONFIG")

    # Check if token_limit is a valid positive integer
    if ! [[ "${GPU_LIMITS[$profile]}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: token_limit for GPU profile '$profile' is missing or invalid: ${GPU_LIMITS[$profile]}" >&2
        exit 1
    fi

    # Check if gres exists in the partition
    check_gres_in_partition "$INFERENCE_PARTITION" "${GPU_GRES[$profile]}" "$profile"
done

#########################################################################################################################
#															#
################################################### Main script logic ###################################################
#															#
#########################################################################################################################

if ! output=$(python3 utilities/analyze_job_input_json.py "$INPUT_FILE" "$MODE"); then
    echo "Validation of input file failed. Aborting."
    exit 1
fi

read TOTAL_DATAPIPELINE_JOBS TOTAL_INFERENCE_JOBS <<< "$output"
export TOTAL_DATAPIPELINE_JOBS TOTAL_INFERENCE_JOBS
NUM_DIMENSIONS=$(jq 'length' "$INPUT_FILE")

if [[ "$MODE" == "cartesian" ]]; then
    MODE_DESC="all combinations across dimensions ('cartesian')"
elif [[ "$MODE" == "collapsed" ]]; then
    MODE_DESC="per-dimension products ('collapsed')"
fi

echo
echo "$TOTAL_DATAPIPELINE_JOBS unique sequence(s) found across $NUM_DIMENSIONS dimension(s). Generating $TOTAL_INFERENCE_JOBS job(s) using mode: $MODE_DESC."
echo

read -r -p "Do you want to continue? [Y/n] " answer

# Default to yes if empty
answer="${answer:-y}"

# Convert to lowercase for easier comparison
answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

case "$answer" in
    y|yes|ja|1)
        echo "Continuing..."
        ;;
    n|no|nein|0)
        echo "Aborting."
        exit 1
        ;;
    *)
        echo "Input not recognized. Aborting."
        exit 1
        ;;
esac

# Create output directories
DATAPIPELINE_INPUT_DIR="data_pipeline_inputs"
mkdir -p "$DATAPIPELINE_INPUT_DIR"
export MAX_ARRAY_SIZE=$(scontrol show config | awk -F= '/MaxArraySize/ {gsub(/ /,"",$2); print $2}')
export OUR_ARRAY_SIZE=$(( (MAX_ARRAY_SIZE / RESULTS_PER_DIR) * RESULTS_PER_DIR ))

if (( OUR_ARRAY_SIZE == 0 )); then
    echo "ERROR: RESULTS_PER_DIR ($RESULTS_PER_DIR) is too large for MAX_ARRAY_SIZE ($MAX_ARRAY_SIZE)." >&2
    exit 1

fi

# Get all unique names from all dictionaries in the JSON list
if [[ "$SORTING" == "input" ]]; then
    # Keep keys in the order they appear in the JSON
    mapfile -t NAMES < <(jq -r '.[] | keys_unsorted[]' "$INPUT_FILE" | awk '!seen[$0]++')
elif [[ "$SORTING" == "alpha" ]]; then
    # Sort keys alphabetically
    mapfile -t NAMES < <(jq -r '.[] | keys[]' "$INPUT_FILE" | awk '!seen[$0]++')
else
    echo "ERROR: SORTING must be 'alpha' or 'input'" >&2
    exit 1
fi

# Loop over each entry and create numbered JSONs
for IDX in "${!NAMES[@]}"; do
    NAME="${NAMES[$IDX]}"
    
    # Extract the sequence for this protein across the list of dimensions
    SEQ=$(jq -r --arg name "$NAME" '
        .[] | select(has($name)) | .[$name]
    ' "$INPUT_FILE" | head -n1)  # pick the first match if it appears in multiple dimensions

    cat > "$DATAPIPELINE_INPUT_DIR/${IDX}_${NAME}.json" <<EOF
{
    "name": "${NAME}",
    "sequences": [
        {
            "protein": {
                "id": "A",
                "sequence": "${SEQ}"
            }
        }
    ],
    "dialect": "alphafold3",
    "version": 3,
    "modelSeeds": [0]
}
EOF
done

if [[ -n "${DATAPIPELINE_STATISTICS_FILE:-}" ]]; then
    # Rotate existing statistics file if it exists
    if [ -f "$DATAPIPELINE_STATISTICS_FILE" ]; then
        backup="${DATAPIPELINE_STATISTICS_FILE}.old"
        i=1
        # Find the first unused backup name
        while [ -f "$backup" ]; do
            backup="${DATAPIPELINE_STATISTICS_FILE}.${i}.old"
            i=$((i+1))
        done
        mv "$DATAPIPELINE_STATISTICS_FILE" "$backup"
    fi
    echo "datapipeline_id,datapipeline_name,job_id,task_id,node,sequence_length,start_time,end_time" > "$DATAPIPELINE_STATISTICS_FILE"
fi

# Submit only the first chunk; recursion handled inside af3_datapipeline_only_slurm.sh
sbatch --array=0-$(( MAX_ARRAY_SIZE < TOTAL_DATAPIPELINE_JOBS ? MAX_ARRAY_SIZE-1 : TOTAL_DATAPIPELINE_JOBS-1 )) \
       --partition=${DATAPIPELINE_PARTITION} \
       --export=ALL,START_OFFSET=0 \
       utilities/af3_datapipeline_only_slurm.sh
