#!/bin/bash
#SBATCH --job-name=AF3_postprocessing
#SBATCH --time=00:05:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1

echo "Postprocessing..."
echo "Currently this does nothing except printing some variables to the SLURM-log:"
echo
echo "GPU_PROFILE = '$GPU_PROFILE'"
echo "INFERENCE_ID = '$INFERENCE_ID'"
echo "INFERENCE_NAME = '$INFERENCE_NAME'"
echo "INFERENCE_DIR = '$INFERENCE_DIR'"
