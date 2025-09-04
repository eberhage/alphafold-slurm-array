#!/bin/bash
#SBATCH --job-name=alphaplots
#SBATCH --time=00:05:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --open-mode=append

alphaplots3_path=/hpc/project/bpc/alphaplots3/alphaplots3.py

# --- Arguments passed from parent job ---
AF3_OUTPUT_PATH=$1  # path to AF3 outputs
NAME=$2             # job or sample name

# Run Alphaplots
python3 "$alphaplots3_path" "${AF3_OUTPUT_PATH}/${NAME}" --sort=rank

# Move master_pae.png to _PAEs folder
mkdir -p "${AF3_OUTPUT_PATH}/_PAEs"
mv "${AF3_OUTPUT_PATH}/${NAME}/master_pae.png" "${AF3_OUTPUT_PATH}/_PAEs/${NAME}.png"

