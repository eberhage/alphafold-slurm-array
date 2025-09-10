#!/bin/bash
#SBATCH --job-name=AF3_datapipeline
#SBATCH --cpus-per-task=8
#SBATCH --time=02:00:00
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
AF3_cache_path=$WORKDIR/tmp/af3_cache_${SLURM_ARRAY_JOB_ID}/${SLURM_ARRAY_TASK_ID} # Cache directory
json_done_path=$WORKDIR/done
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

# Extract the protein name from the JSON
NAME=$(jq -r '.name' "$AF3_input_path"/"$AF3_input_file")

if [[ -f "$AF3_output_path"/"$NAME"/"$NAME"_data.json ]]; then
    echo "MSA "$NAME"/"$NAME"_data.json already exists. Skipping."
    exit 0
fi

######### Do not change this(!) #########
AF3_root=/leinesw/software/user/alphafold3
AF3_model_path=${AF3_root}/model
AF3_db_path=${AF3_root}/db
AF3_container_path=${AF3_root}/container

mkdir -p "$AF3_cache_path"
mkdir -p "$APPTAINER_TMPDIR"
mkdir -p "$AF3_output_path"

export APPTAINER_BINDPATH="/${AF3_input_path}:/root/af_input,${AF3_output_path}:/root/af_output,${AF3_model_path}:/root/models,${AF3_db_path}:/root/public_databases,${AF3_cache_path}:/root/jax_cache_dir"

echo "Running AlphaFold job for ${NAME} (index ${SLURM_ARRAY_TASK_ID}, total index ${DATA_PIPELINE_ID})"

start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

apptainer exec --writable-tmpfs --nv ${AF3_container_path}/alphafold3.1.sif python /app/alphafold/run_alphafold.py \
    --run_inference=false \
    --json_path=/root/af_input/${AF3_input_file} \
    --model_dir=/root/models \
    --output_dir=/root/af_output \
    --mgnify_database_path=/root/public_databases/mgy_clusters_2022_05.fa \
    --ntrna_database_path=/root/public_databases/nt_rna_2023_02_23_clust_seq_id_90_cov_80_rep_seq.fasta \
    --pdb_database_path=/root/public_databases/mmcif_files \
    --rfam_database_path=/root/public_databases/rfam_14_9_clust_seq_id_90_cov_80_rep_seq.fasta \
    --rna_central_database_path=/root/public_databases/rnacentral_active_seq_id_90_cov_80_linclust.fasta \
    --seqres_database_path=/root/public_databases/pdb_seqres_2022_09_28.fasta \
    --small_bfd_database_path=/root/public_databases/bfd-first_non_consensus_sequences.fasta \
    --uniprot_cluster_annot_database_path=/root/public_databases/uniprot_all_2021_04.fa \
    --uniref90_database_path=/root/public_databases/uniref90_2022_05.fa \
    --jackhmmer_n_cpu=$SLURM_CPUS_PER_TASK \
    --jax_compilation_cache_dir=/root/jax_cache_dir

if [[ -n "${DATAPIPELINE_STATISTICS_FILE:-}" && -f "$DATAPIPELINE_STATISTICS_FILE" ]]; then
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # write statistics
    echo "${DATA_PIPELINE_ID},${NAME},${SLURM_ARRAY_JOB_ID},${SLURM_ARRAY_TASK_ID},$(hostname),${start_time},${end_time}" >> $DATAPIPELINE_STATISTICS_FILE
fi

rm -rf $AF3_cache_path
rm -rf $APPTAINER_TMPDIR
rm -rf "$AF3_input_path"/"$AF3_input_file"

echo "Extracting MSA and templates"
python3 $WORKDIR/utilities/extract_msa_and_template_data.py -z "$AF3_output_path"/"$NAME"/"$NAME"_data.json