# AlphaFold SLURM Array

This repository provides a wrapper around **AlphaFold** to run large numbers of inference jobs in a systematic and reproducible way on HPCs with SLURM.  
It is designed for **Cartesian product exploration** of protein sequence combinations, where each dimension represents a set of proteins.

---

## Input Format

The input to the pipeline is a JSON file (`input.json`) containing a **list of dictionaries**.  
Each dictionary defines one **dimension vector**, where every entry is a `"Protein_Name":"AA_Sequence"` pair.

- The Cartesian product of all dimensions defines the jobs to run.  
- Redundant jobs (e.g. permuted chain orders leading to identical complexes) are automatically removed.  
- Each job is run with the specified AlphaFold seeds.

### Example

```json
[
  {
    "Protein_A": "MSQASSSPGEGPSSEAAAISEAEAASGSFGRLHCQV...",
    "Protein_B": "MAQGSRAPSGPPLPVLPVDDWLNFRVDLFGDEHRRL...",
    "Protein_C": "MIKGKLMPNSLKDVQKLICDEGITDNVITTLSRLKP..."
  },
  {
    "Protein_D": "MSQASSSPGEGPSSEAAAISEAEAASGSFGRLHCQV..."
  },
  {
    "Protein_E": "MSQASSSPGEGPSSEAAAISEAEAASGSFGRLHCQV...",
    "Protein_F": "MAQGSRAPSGPPLPVLPVDDWLNFRVDLFGDEHRRL..."
  }
]
```
This input will produce 6 jobs:

ADE, ADF, BDE, BDF, CDE, CDF

If redundant jobs occur (e.g. if `Protein_E` also appears in dimension 1 and `Protein_A` in dimension 3), jobs like EDA and ADE are treated as one unique job.

### Configuration
The following parameters are set inside submit_data_pipeline.sh:

| Variable          | Description                                                                                                                                                   |
|-------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `INPUT_FILE`      | Path to the input JSON file (default: `input.json`).                                                                                                          |
| `SEEDS`           | Comma-separated AlphaFold seeds used for inference (default: `"0,1,2"`).                                                                                      |
| `RESULTS_PER_DIR` | Number of results to bundle per directory (default: `250`). Naming scheme: `results/<SLURM_ARRAY_JOB_ID>_x-y`.                                                |
| `SORTING`         | How to order protein chains within a dimension:<br><ul><li>`alpha`: alphabetically by protein key</li><li>`input`: preserve order from `input.json`</li></ul> |
| `STATISTICS_FILE` | CSV file where inference statistics will be stored (default: `statistics.csv`).                                                                               |


### Output

The AlphaFold jobs are sorted into a result directory with the following structure:

```
results/
 ├── <SLURM_ARRAY_JOB_ID>_0-249/
 │    ├── <inference_job_name>/
 │    │    ├── seed-0_sample-0/
 │    │    │    ├── <inference_job_name>_seed-0_sample-0_confidences.json
 │    │    │    ├── <inference_job_name>_seed-0_sample-0_model.cif
 │    │    │    └── <inference_job_name>_seed-0_sample-0_summary_confidences.json
 │    │    ├── seed-0_sample-1/
 │    │    │    ├── ...
 │    │    │   ...
 │    │    ├── <inference_job_name>_confidences.json
 │    │    ├── <inference_job_name>_data.json
 │    │    ├── <inference_job_name>_model.cif
 │    │    ├── <inference_job_name>_ranking_scores.csv
 │    │    └── <inference_job_name>_summary_confidences.json
 │    ├── ...
 │   ...
 ├── <SLURM_ARRAY_JOB_ID>_250-499/
 │    ├── ...
 │   ...
...
```


The file <job_name>_summary_confidences.json contains model quality metrics such as:

- iptm
- ptm
- ranking_score

These values are automatically collected into the statistics CSV file for downstream analysis.

### Example Workflow

- Prepare input (input.json) with your protein sequences.
- Adjust configuration inside `submit_data_pipeline.sh` if needed.
- Submit the pipeline to your HPC cluster (SLURM).
- Collect statistics from the generated `statistics.csv`.
