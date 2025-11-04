#!/bin/bash
#SBATCH --job-name=AF3_datapipeline
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=06:00:00
#SBATCH --ntasks=1
#SBATCH --threads-per-core=1                    # Disable Multithreading
#SBATCH --hint=nomultithread
#SBATCH --output=slurm-output/slurm-%A_%a-%x.out # %j (Job ID) %x (Job Name)
echo "Job ran on:" $(hostname)
echo ""

DATA_PIPELINE_ID=$(( SLURM_ARRAY_TASK_ID + START_OFFSET ))
scontrol update jobid=${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID} comment="Task $((DATA_PIPELINE_ID + 1)) of ${TOTAL_DATAPIPELINE_JOBS}"

WORKDIR=$(pwd)
user_input_file=$WORKDIR/data_pipeline_inputs/${DATA_PIPELINE_ID}_*.json
AF3_input_file=$(basename $user_input_file)
AF3_input_path=$WORKDIR/data_pipeline_inputs
AF3_output_path=$WORKDIR/monomer_data
export APPTAINER_TMPDIR=$WORKDIR/tmp/apptainer_${SLURM_ARRAY_JOB_ID}/${SLURM_ARRAY_TASK_ID}

# --- Task 0 only: decide what’s next ---
if [[ "$SLURM_ARRAY_TASK_ID" -eq 0 ]]; then
    NEXT_OFFSET=$(( START_OFFSET + MAX_ARRAY_SIZE ))

    if (( NEXT_OFFSET < TOTAL_DATAPIPELINE_JOBS )); then
        echo "Submitting next datapipeline batch starting at offset $NEXT_OFFSET"
        sbatch --dependency=afterok:${SLURM_ARRAY_JOB_ID} \
               --partition=${DATAPIPELINE_PARTITION} \
               --array=0-$(( MAX_ARRAY_SIZE < (TOTAL_DATAPIPELINE_JOBS - NEXT_OFFSET) ? MAX_ARRAY_SIZE-1 : (TOTAL_DATAPIPELINE_JOBS - NEXT_OFFSET)-1 )) \
               --export=ALL,START_OFFSET=$NEXT_OFFSET \
               $WORKDIR/utilities/af3_datapipeline_only_slurm.sh
    else
        echo "All datapipeline batches done. Continuing with pair-building and inference..."
        sbatch --dependency=afterok:${SLURM_ARRAY_JOB_ID} \
               $WORKDIR/utilities/submit_data_pipeline_part_2.sh
    fi
fi
# -- End of Task 0 only ---

mkdir -p "$APPTAINER_TMPDIR"
mkdir -p "$AF3_output_path"

export APPTAINER_BINDPATH="/${AF3_input_path}:/root/af_input,${AF3_output_path}:/root/af_output,${AF3_MODEL_PATH}:/root/models,${AF3_DB_PATH}:/root/public_databases"

# Extract the protein name from the JSON
NAME=$(jq -r '.name' "$AF3_input_path"/"$AF3_input_file")

echo "Running AlphaFold job for ${NAME} (index ${SLURM_ARRAY_TASK_ID}, total index ${DATA_PIPELINE_ID})"

start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

apptainer exec --writable-tmpfs --nv ${AF3_CONTAINER_PATH} python /app/alphafold/run_alphafold.py \
    --run_inference=false \
    --json_path=/root/af_input/${AF3_input_file} \
    --model_dir=/root/models \
    --output_dir=/root/af_output \
    --db_dir=/root/public_databases \
    --jackhmmer_n_cpu=$SLURM_CPUS_PER_TASK 

if [[ -n "${DATAPIPELINE_STATISTICS_FILE:-}" && -f "$DATAPIPELINE_STATISTICS_FILE" ]]; then
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    sequence_length=$(jq -r '.sequences[0].protein.sequence | length' "$AF3_input_path"/"$AF3_input_file")

    # write statistics
    echo "${DATA_PIPELINE_ID},${NAME},${SLURM_ARRAY_JOB_ID},${SLURM_ARRAY_TASK_ID},$(hostname),${sequence_length},${start_time},${end_time}" >> $DATAPIPELINE_STATISTICS_FILE
fi

rm -rf $APPTAINER_TMPDIR
rm -rf "$AF3_input_path"/"$AF3_input_file"

# move file one up and delete old directory (it is always only one file per directory -> messy)
mv "$AF3_output_path"/"$NAME"/"$NAME"_data.json "$AF3_output_path" && rm -rf "$AF3_output_path"/"$NAME"

echo "Extracting MSA and templates"
python3 $WORKDIR/utilities/extract_msa_and_template_data.py -z "$AF3_output_path"/"$NAME"_data.json