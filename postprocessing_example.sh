#!/bin/bash
#SBATCH --job-name=AF3_postprocessing
#SBATCH --time=00:05:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1

echo "Postprocessing..."
echo "Currently, this does nothing except print a few variables to the SLURM log."
echo
echo "PIPELINE_RUN_ID = '$PIPELINE_RUN_ID'"
echo "GPU_PROFILE = '$GPU_PROFILE'"
echo "FIRST_INFERENCE_ID = '$FIRST_INFERENCE_ID'"
echo "LAST_INFERENCE_ID = '$LAST_INFERENCE_ID'"
echo 
echo "INFERENCE_ID = '$INFERENCE_ID'"
echo "INFERENCE_NAME = '$INFERENCE_NAME'"
echo "INFERENCE_DIR = '$INFERENCE_DIR'"
