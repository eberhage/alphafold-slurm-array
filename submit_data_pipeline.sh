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

# Screen file with compounds in SMILE format. See README.md for file specifications. The pipeline will run once for every compound.
export SCREEN_FILE="screen.json"
export MAX_COMPOUND_ATOMS=50

# where to find the cluster specific settings for this pipeline
export CLUSTER_CONFIG="cluster_config.json"

# Choose which GPU profiles from cluster config to use
export GPU_PROFILES="40g-parallel,80g"

# Datapipeline (MSA, template search) statistics file (simple CSV)
export DATAPIPELINE_STATISTICS_FILE="datapipeline_statistics.csv"

# Directory that will contain statistics about the inference (protein structure prediction) in JSON format.
export INFERENCE_STATISTICS_DIR="inference_statistics"

# Optional postprocessing script that runs AFTER every instance of POSTPROCESSING_LEVEL and has access to environment variables.
# Leave empty for no postprocessing.
# The POSTPROCESSING_LEVEL determines at what stage of the pipeline postprocessing should be done. 
# If you dont use parallelisation you should never use "job" but always "process" instead.
# Options: 
#       "array": Has access to environment variables PIPELINE_RUN_ID, GPU_PROFILE, FIRST_INFERENCE_ID, LAST_INFERENCE_ID (of the array)
#       "job": Has access to environment variables PIPELINE_RUN_ID, GPU_PROFILE, FIRST_INFERENCE_ID, LAST_INFERENCE_ID (of the job)
#       "process": Has access to environment variables PIPELINE_RUN_ID, GPU_PROFILE, INFERENCE_NAME, INFERENCE_DIR and INFERENCE_ID
export POSTPROCESSING_SCRIPT="postprocessing_example.sh"
export POSTPROCESSING_LEVEL="process"

###########################################################################################################################
                                                           
# Run the pipeline
bash ./utilities/submit_data_pipeline_part_1.sh

