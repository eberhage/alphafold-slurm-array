#!/usr/bin/env bash

INPUT_FILE="input.json"                                    # Needs to contain a list ("[]") of dictionaries ("{}") with protein:sequence pairs ("Protein_Name":"AA_Seqence").
                                                           # Every dictionary is treated as a DIMENSION vector. 
                                                           #
                                                           # Example:
                                                           # [
                                                           #    {
                                                           #       "Protein_A":"MSQASSSPGEGPSSEAAAISEAEAASGSFGRLHCQV...",
                                                           #       "Protein_B":"MAQGSRAPSGPPLPVLPVDDWLNFRVDLFGDEHRRL...",
                                                           #       "Protein_C":"MIKGKLMPNSLKDVQKLICDEGITDNVITTLSRLKP..."
                                                           #    },
                                                           #    {
                                                           #       "Protein_D":"MSQASSSPGEGPSSEAAAISEAEAASGSFGRLHCQV..."
                                                           #    },
                                                           #    {
                                                           #       "Protein_E":"MSQASSSPGEGPSSEAAAISEAEAASGSFGRLHCQV...",
                                                           #       "Protein_F":"MAQGSRAPSGPPLPVLPVDDWLNFRVDLFGDEHRRL..."
                                                           #    }
                                                           # ]
                                                           #
MODE="cartesian"                                           # Options:
                                                           #  'cartesian':    The total jobs will be the Cartesian product of all DIMENSIONS (redundant jobs removed).
                                                           #                      Example (see input above):
                                                           #                          → 6 jobs: ADE, ADF, BDE, BDF, CDE, CDF
                                                           #                  If there were redundant jobs (e.g. if Protein_E would also be in DIMENSION 1 and Protein_A would  
                                                           #                  also be in DIMENSION 3) the resulting products EDA and ADE would be treated as ONE job.
                                                           #
                                                           #                  Use this mode if you want the all vs. all scenario.
                                                           #
                                                           #  'collapsed':    Each DIMENSION is collapsed into the product of all its elements.
                                                           #                  Each collapsed product is one job.
                                                           #                      Example (see input above):
                                                           #                          → 3 jobs: ABC, D, EF
                                                           #
                                                           #                  Use this mode if you want every dictionary in the JSON to be one AlphaFold job
                                                           #
SEEDS="0,1,2"                                              # AlphaFold seeds for the inference step to be used for every job. Comma-separated string.
RESULTS_PER_DIR=250                                        # Number of results to be bundled as one directory. Naming scheme: results/<job-id>_x-y
SORTING="alpha"                                            # Options: 'alpha' = use keys of INPUT_FILE alphabetically for the script logic, 'input' = preserve key order from INPUT_FILE.
DATAPIPELINE_STATISTICS_FILE="datapipeline_statistics.csv" # Datapipeline (MSA, template search) statistics file
INFERENCE_STATISTICS_FILE="inference_statistics.csv"       # Inference (protein structure prediction) statistics file
DATAPIPELINE_PARTITION="leinecpu_lowprio"                  # SLURM partition to run datapapline on. 
INFERENCE_PARTITION="leinegpu_lowprio"                     # SLURM partition to run inference on.
SMALL_JOBS_UPPER_LIMIT=3072 			           # Amount of tokens to process on small GPU.
LARGE_JOBS_UPPER_LIMIT=5120                                # Amount of tokens to process on large GPU.
SMALL_GPU="a100-40g"                                       # Name of the small GPU gres in SLURM
LARGE_GPU="a100-80g"                                       # Name of the large GPU gres in SLURM
POSTPROCESSING_SCRIPT="utilities/postprocessing.sh"        # Optional postprocessing script that runs after every inference job and has access to envirnonment variables such as INFERENCE_NAME, INFERENCE_DIR and INFERENCE_ID

# ------------------------------- No user changes below ----------------------------------

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

# DATAPIPELINE_PARTITION must be non-empty
if [[ -z "${DATAPIPELINE_PARTITION:-}" ]]; then
    echo "ERROR: DATAPIPELINE_PARTITION is not set." >&2
    exit 1
fi

# INFERENCE_PARTITION must be non-empty
if [[ -z "${INFERENCE_PARTITION:-}" ]]; then
    echo "ERROR: INFERENCE_PARTITION is not set." >&2
    exit 1
fi

# SMALL_JOBS_UPPER_LIMIT must be a positive integer
if ! [[ "$SMALL_JOBS_UPPER_LIMIT" =~ ^[0-9]+$ ]] || (( SMALL_JOBS_UPPER_LIMIT <= 0 )); then
    echo "ERROR: SMALL_JOBS_UPPER_LIMIT must be a positive integer." >&2
    exit 1
fi

# LARGE_JOBS_UPPER_LIMIT must be a positive integer
if ! [[ "$LARGE_JOBS_UPPER_LIMIT" =~ ^[0-9]+$ ]] || (( LARGE_JOBS_UPPER_LIMIT <= 0 )); then
    echo "ERROR: LARGE_JOBS_UPPER_LIMIT must be a positive integer." >&2
    exit 1
fi

if (( SMALL_JOBS_UPPER_LIMIT >= LARGE_JOBS_UPPER_LIMIT )); then
    echo "WARNING: SMALL_JOBS_UPPER_LIMIT ($SMALL_JOBS_UPPER_LIMIT) is not smaller than LARGE_JOBS_UPPER_LIMIT ($LARGE_JOBS_UPPER_LIMIT)."
fi

# SMALL_GPU must be non-empty
if [[ -z "${SMALL_GPU:-}" ]]; then
    echo "ERROR: SMALL_GPU is not set." >&2
    exit 1
fi

# LARGE_GPU must be non-empty
if [[ -z "${LARGE_GPU:-}" ]]; then
    echo "ERROR: LARGE_GPU is not set." >&2
    exit 1
fi

if ! output=$(python3 utilities/analyze_job_input_json.py "$INPUT_FILE" "$MODE"); then
    echo "Validation of input file failed. Aborting."
    exit 1
fi

read TOTAL_DATAPIPELINE_JOBS TOTAL_INFERENCE_JOBS <<< "$output"
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
MAX_ARRAY_SIZE=$(scontrol show config | awk -F= '/MaxArraySize/ {gsub(/ /,"",$2); print $2}')
OUR_ARRAY_SIZE=$(( (MAX_ARRAY_SIZE / RESULTS_PER_DIR) * RESULTS_PER_DIR ))

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
 
export TOTAL_DATAPIPELINE_JOBS MAX_ARRAY_SIZE SEEDS INPUT_FILE SORTING TOTAL_INFERENCE_JOBS OUR_ARRAY_SIZE RESULTS_PER_DIR DATAPIPELINE_STATISTICS_FILE INFERENCE_STATISTICS_FILE MODE DATAPIPELINE_PARTITION INFERENCE_PARTITION SMALL_JOBS_UPPER_LIMIT LARGE_JOBS_UPPER_LIMIT SMALL_GPU LARGE_GPU POSTPROCESSING_SCRIPT

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
    echo "datapipeline_id,datapipeline_name,job_id,task_id,node,start_time,end_time" > "$DATAPIPELINE_STATISTICS_FILE"
fi

# Submit only the first chunk; recursion handled inside af3_datapipeline_only_slurm.sh
sbatch --array=0-$(( MAX_ARRAY_SIZE < TOTAL_DATAPIPELINE_JOBS ? MAX_ARRAY_SIZE-1 : TOTAL_DATAPIPELINE_JOBS-1 )) \
       --partition=${DATAPIPELINE_PARTITION} \
       --export=ALL,START_OFFSET=0 \
       utilities/af3_datapipeline_only_slurm.sh
