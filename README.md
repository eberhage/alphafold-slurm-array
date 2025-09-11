# AlphaFold SLURM Array

This repository provides a wrapper around **AlphaFold** to run large numbers of inference jobs in a systematic and reproducible way on HPCs with SLURM and Apptainer (formerly Singularity).
It supports two exploration strategies for protein sequence combinations. Each **dimension** represents a set of proteins.
- `cartesian`: exhaustive Cartesian product exploration across dimensions  
	→ Proteins will **never** be part of the same job with proteins from the *same* dimension but instead be in exactly one job with all protein combinations from *other* dimensions.
- `collapsed`: one job per dimension, without crossing combinations  
	→ **Only** Proteins in the same dimension are part of the same job.

---

## Input Format

The input to the pipeline is a JSON file (`input.json`) containing a **list of dictionaries**.  
Each dictionary defines one **dimension vector**, where every entry is a `"Protein_Name":"AA_Sequence"` pair.

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

### Mode
The behavior of the pipeline is controlled by the `MODE` parameter.
- `cartesian`  
	The Cartesian product of all dimensions defines the jobs to run.   

	The example above will produce 6 jobs:

	ADE, ADF, BDE, BDF, CDE, CDF

	Redundant jobs (e.g. permuted chain orders leading to identical complexes) are automatically removed.

- `collapsed`  
	Each dimension is treated independently and produces exactly one job (if not a duplicate of a different dimension).

	The example above will produce 3 jobs:

	ABC, D, EF

### Configuration
The following parameters are set inside submit_data_pipeline.sh:

| Variable                       | Description                                                                                                                                                                       |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `INPUT_FILE`                   | Path to the input JSON file (default: `input.json`).                                                                                                                              |
| `MODE`                         | Job generation mode:<ul><li>`cartesian`: full product between dimensions</li><li>`collapsed`: one job per dimension</li></ul>                                                     |
| `SEEDS`                        | Comma-separated AlphaFold seeds used for inference.                                                                                                                               |
| `RESULTS_PER_DIR`              | Number of results to bundle per directory. Naming scheme: `results/<SLURM_ARRAY_JOB_ID>_x-y`.                                                                                     |
| `SORTING`                      | How to order protein chains within a dimension:<br><ul><li>`alpha`: alphabetically by protein key</li><li>`input`: preserve order from `input.json`</li></ul>                     |
| `DATAPIPELINE_PARTITION`       | SLURM partition to run the **data pipeline** (MSA, template search).                                                                                                              |
| `INFERENCE_PARTITION`          | SLURM partition to run the **inference** step. Must provide access to GPUs.                                                                                                       |
| `AF3_CONTAINER_PATH`           | Path to the AlphaFold3 Apptainer container.                                                                                                                                       |
| `AF3_MODEL_PATH`               | Path to the directory containing the AlphaFold3 model weights (provided by Google).                                                                                               |
| `AF3_DB_PATH`                  | Path to the directory containing the AlphaFold3 databases.                                                                                                                        |
| `SMALL_JOBS_UPPER_LIMIT`       | Token cutoff for small GPU jobs (jobs with ≤ this many tokens will run on `SMALL_GPU`).                                                                                           |
| `LARGE_JOBS_UPPER_LIMIT`       | Token cutoff for large GPU jobs (jobs with ≤ this many tokens will run on `LARGE_GPU`).                                                                                           |
| `SMALL_GPU`                    | Name of the SLURM GPU resource (gres) corresponding to the smaller GPU (e.g., `"a100-40g"`).                                                                                      |
| `LARGE_GPU`                    | Name of the SLURM GPU resource (gres) corresponding to the larger GPU (e.g., `"a100-80g"`).                                                                                       |
| `DATAPIPELINE_STATISTICS_FILE` | CSV file where statistics from the **data pipeline** stage will be stored (default: `datapipeline_statistics.csv`).                                                               |
| `INFERENCE_STATISTICS_FILE`    | CSV file where statistics from the **inference** stage will be stored (default: `inference_statistics.csv`).                                                                      |
| `POSTPROCESSING_SCRIPT`        | Optional script that runs after each inference job. It has access to environment variables such as `INFERENCE_NAME`, `INFERENCE_DIR`, and `INFERENCE_ID`. Leave empty to disable. |


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

- Prepare input (`input.json`) with your protein sequences.
- Adjust configuration inside `submit_data_pipeline.sh`.
- Submit the pipeline to your HPC cluster (SLURM).
- Collect statistics from the generated CSV files.
