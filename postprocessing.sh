#!/bin/bash
#SBATCH --job-name=AF3_postprocessing
#SBATCH --time=00:05:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1

alphaplots3_path=/hpc/project/bpc/alphaplots3/alphaplots3.py

# Run Alphaplots
python3 "${alphaplots3_path}" "${INFERENCE_DIR}" --sort=rank

avg_iptm=$(awk -F',' -v gp="${GPU_PROFILE}" -v id="${INFERENCE_ID}" \
    'NR>1 && $1==gp && $2==id { print $12 }' ${INFERENCE_STATISTICS_FILE})
echo "avg_iptm: $avg_iptm"

iptm_category=$(awk -v x="$avg_iptm" '
    BEGIN {
        if (x > 0.8)          print "iptm_better_than_0.8";
        else if (x > 0.6)     print "iptm_0.6-0.8";
        else if (x > 0.4)     print "iptm_0.4-0.6";
        else                  print "iptm_below_0.4";
    }
')
echo "category: $iptm_category"

# Move master_pae.png to _PAEs folder
new_top_folder=${INFERENCE_DIR}/../${iptm_category}
mkdir -p "${new_top_folder}/_PAEs"
mkdir -p "${new_top_folder}/${INFERENCE_NAME}"

mv ${INFERENCE_DIR}/master_pae.png 								${new_top_folder}/_PAEs/${INFERENCE_NAME}.png
mv ${INFERENCE_DIR}/seed-*_sample-*/${INFERENCE_NAME}_seed-*_sample-*_summary_confidences.json 	${new_top_folder}/${INFERENCE_NAME}
mv ${INFERENCE_DIR}/seed-*_sample-*/${INFERENCE_NAME}_seed-*_sample-*_model.cif 		${new_top_folder}/${INFERENCE_NAME}
mv ${INFERENCE_DIR}/${INFERENCE_NAME}_ranking_scores.csv 					${new_top_folder}/${INFERENCE_NAME}

rm -rf ${INFERENCE_DIR}