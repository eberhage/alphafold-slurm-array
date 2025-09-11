#!/usr/bin/env bash

# Path to input file. See README.md for file specifications
export INPUT_FILE="input.json"

# Mode for the job generation. See README.md.
export MODE="cartesian"

# AlphaFold seeds for the inference step to be used for every job. Comma-separated string.
export SEEDS="0,1,2"                                              

# Number of results to be bundled as one directory. Naming scheme: results/<job-id>_x-y
export RESULTS_PER_DIR=250                                        

# Sorting options: 'alpha' = use keys of INPUT_FILE alphabetically for the script logic, 'input' = preserve key order from INPUT_FILE.
export SORTING="alpha"                                                 

# SLURM partition to run datapapline on. 
export DATAPIPELINE_PARTITION="leinecpu_lowprio"                  

# SLURM partition to run inference on. Must have GPUs.
export INFERENCE_PARTITION="leinegpu_lowprio"

# AlphaFold3 container path
export AF3_CONTAINER_PATH="/leinesw/software/user/alphafold3/container/alphafold3.1.sif"

# Path to directory containing the model weights provided by Google
export AF3_MODEL_PATH="/leinesw/software/user/alphafold3/model"

# Path to databases
export AF3_DB_PATH="/leinesw/software/user/alphafold3/db"

# Amount of tokens to process on small GPU.
export SMALL_JOBS_UPPER_LIMIT=3072 			           

# Amount of tokens to process on large GPU.
export LARGE_JOBS_UPPER_LIMIT=5120                                

# Name of the small GPU gres in SLURM
export SMALL_GPU="a100-40g"                                       

# Name of the large GPU gres in SLURM
export LARGE_GPU="a100-80g"

# Datapipeline (MSA, template search) statistics file
export DATAPIPELINE_STATISTICS_FILE="datapipeline_statistics.csv" 

# Inference (protein structure prediction) statistics file
export INFERENCE_STATISTICS_FILE="inference_statistics.csv"  

# Optional postprocessing script that runs after every inference job and has access to envirnonment variables such as
# INFERENCE_NAME, INFERENCE_DIR and INFERENCE_ID. Leave empty if no postprocessing should be done.
export POSTPROCESSING_SCRIPT="postprocessing.sh"           

###########################################################################################################################
                                                           
# Run the pipeline
bash ./utilities/submit_data_pipeline_part_1.sh

