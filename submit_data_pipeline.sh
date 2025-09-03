#!/usr/bin/env bash

INPUT_FILE="input.json"          # Needs to contain a list ("[]") of dictionaries ("{}") with protein:sequence pairs ("Protein_Name":"AA_Seqence").
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
MODE="cartesian"                 # Options:
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
SEEDS="0,1,2"                    # AlphaFold seeds for the inference step to be used for every job. Comma-separated string.
RESULTS_PER_DIR=250              # Number of results to be bundled as one directory. Naming scheme: results/<job-id>_x-y
SORTING="alpha"                  # Options: 'alpha' = use keys of INPUT_FILE alphabetically for the script logic, 'input' = preserve key order from INPUT_FILE.
STATISTICS_FILE="statistics.csv" # Inference statistics file (no spaces in the filenames, please!)

# ------------------------------- No user changes below ----------------------------------

if [[ "$MODE" != "cartesian" && "$MODE" != "collapsed" ]]; then
    echo "ERROR: MODE must be 'cartesian' or 'collapsed'." >&2
    exit 1
fi

if ! output=$(python3 utilities/analyze_job_input_json.py "$INPUT_FILE" "$MODE"); then
    exit 1
fi

read TOTAL_DATAPIPELINE_JOBS TOTAL_INFERENCE_JOBS <<< "$output"

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

NUM_DIMENSIONS=$(jq 'length' "$INPUT_FILE")

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

if [[ "$MODE" == "cartesian" ]]; then
    MODE_DESC="all combinations across dimensions"
elif [[ "$MODE" == "collapsed" ]]; then
    MODE_DESC="per-dimension products"
fi

echo "$TOTAL_DATAPIPELINE_JOBS unique sequence(s) found across $NUM_DIMENSIONS dimension(s). Generating $TOTAL_INFERENCE_JOBS job(s) using mode: $MODE_DESC."
 
export TOTAL_DATAPIPELINE_JOBS MAX_ARRAY_SIZE SEEDS INPUT_FILE SORTING TOTAL_INFERENCE_JOBS OUR_ARRAY_SIZE RESULTS_PER_DIR STATISTICS_FILE MODE

# Submit only the first chunk; recursion handled inside af3_datapipeline_only_slurm.sh
sbatch --array=0-$(( MAX_ARRAY_SIZE < TOTAL_DATAPIPELINE_JOBS ? MAX_ARRAY_SIZE-1 : TOTAL_DATAPIPELINE_JOBS-1 )) \
       --export=ALL,START_OFFSET=0 \
       utilities/af3_datapipeline_only_slurm.sh
