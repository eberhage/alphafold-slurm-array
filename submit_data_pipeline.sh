#!/bin/bash

# Path to input file. See README.md for file specifications
export INPUT_FILE="input.json"

# Mode for the job generation. See README.md.
export MODE="cartesian"

# AlphaFold seeds for the inference step to be used for every job. Comma-separated string.
export SEEDS="0,1,2"

# Number of results to be bundled as one directory. Naming scheme: results/<job-id>_<gpu-profile>_x-y
export RESULTS_PER_DIR=250

# Sorting options: 'alpha' = use keys of INPUT_FILE alphabetically for the script logic, 'input' = preserve key order from INPUT_FILE.
export SORTING="alpha"

# where to find the cluster specific settings for this pipeline
export CLUSTER_CONFIG="cluster_config.json"

# Choose which GPU profiles from cluster config to use
export GPU_PROFILES="40g,80g"

# Datapipeline (MSA, template search) statistics file
export DATAPIPELINE_STATISTICS_FILE="datapipeline_statistics.csv"

# Inference (protein structure prediction) statistics file
export INFERENCE_STATISTICS_FILE="inference_statistics.csv"

# Optional postprocessing script that runs after every inference job and has access to environment variables such as
# INFERENCE_NAME, INFERENCE_DIR and INFERENCE_ID. Leave empty if no postprocessing should be done.
export POSTPROCESSING_SCRIPT="postprocessing_example.sh"

###########################################################################################################################
                                                           
# Run the pipeline
bash ./utilities/submit_data_pipeline_part_1.sh

