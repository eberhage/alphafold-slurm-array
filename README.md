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

## Job Configuration
The following parameters are set inside submit_data_pipeline.sh:

| Variable                       | Description                                                                                                                                                                       |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `INPUT_FILE`                   | Path to the input JSON file (default: `input.json`).                                                                                                                              |
| `MODE`                         | Job generation mode (see [below](#mode)):<ul><li>`cartesian`: full product between dimensions</li><li>`collapsed`: one job per dimension</li></ul>                                |
| `SEEDS`                        | Comma-separated AlphaFold seeds used for inference.                                                                                                                               |
| `RESULTS_PER_DIR`              | Number of results to bundle per directory. Naming scheme: `results/<SLURM_ARRAY_JOB_ID>_<GPU_PROFILE>_x-<x+RESULTS_PER_DIR-1>`.                                                                                     |
| `SORTING`                      | How to order protein chains within a dimension:<br><ul><li>`alpha`: alphabetically by protein key</li><li>`input`: preserve order from `input.json`</li></ul>                     |
| `CLUSTER_CONFIG`               | Path to your cluster configuration JSON file (see [below](#cluster-configuration)).                                                                                               |
| `GPU_PROFILES`                 | Comma-separated list of GPU profiles from cluster configuration to use for job assignment (e.g., `"40g,80g"`).                                                                |
| `DATAPIPELINE_STATISTICS_FILE` | CSV file where statistics from the **data pipeline** stage will be stored (default: `datapipeline_statistics.csv`).                                                               |
| `INFERENCE_STATISTICS_FILE`    | CSV file where statistics from the **inference** stage will be stored (default: `inference_statistics.csv`).                                                                      |
| `POSTPROCESSING_SCRIPT`        | Optional script that runs after each inference job. It has access to environment variables such as `INFERENCE_NAME`, `INFERENCE_DIR`, and `INFERENCE_ID`. Leave empty to disable. |


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

> [!WARNING]  
> In `collapsed` mode, sequence names must be unique per dimension (they may repeat across dimensions). If multiple chains share the same name and you *have* to use `collapsed` mode, assign distinct identifiers (for example, append `_A`, `_B`, etc.) to ensure proper complex prediction. The same limitation exists in `cartesian` mode; however, duplicate sequences are inherently nonsensical for this configuration.

## Cluster Configuration

The pipeline now uses a **cluster configuration JSON** to define paths, SLURM partitions, and GPU profiles. This centralizes settings that are unlikely to change frequently.  

### Example

```json
{
  "af3_container_path": "/path/to/af3_container.sif",
  "af3_model_path": "/path/to/model",
  "af3_db_path": "/path/to/db",
  "datapipeline_partition": "cpupartition",
  "inference_partition": "gpupartition",
  "gpu_profiles": {
    "40g": {
      "gres": "a100-40g",
      "token_limit": 3072
    },
    "80g": {
      "gres": "a100-80g",
      "token_limit": 5120
    }
  }
}
```

| Field                    | Description                                                                                                                                                                                  |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `af3_container_path`     | Path to the AlphaFold3 container file (`.sif`).                                                                                                                                              |
| `af3_model_path`         | Path to the directory containing [AlphaFold3 model weights provided by Google-Deepmind](https://docs.google.com/forms/d/e/1FAIpQLSfWZAgo1aYk0O4MuAXZj8xRQ8DafeFJnldNOnh_13qAx2ceZw/viewform).|
| `af3_db_path`            | Path to the AlphaFold3 databases directory.                                                                                                                                                  |
| `datapipeline_partition` | SLURM partition used for MSA/template search (CPU jobs).                                                                                                                                     |
| `inference_partition`    | SLURM partition used for inference (GPU jobs).                                                                                                                                               |
| `gpu_profiles`           | Dictionary of GPU profiles. Each profile defines: <ul><li>`gres`: GPU resource name in SLURM</li><li>`token_limit`: maximum number of tokens this profile can handle</li></ul>               |

### Notes on GPU Profiles

- Users may define **any number of GPU profiles**. Each profile must include a valid `gres` and a `token_limit`.
- The pipeline will automatically **assign jobs to the smallest possible GPU profile** that can handle the total tokens of the job.
- Token limits allow the pipeline to efficiently distribute jobs across different GPU types.

## Output

The AlphaFold jobs are sorted into a result directory with the following structure:

```bash
results/
 ├── <SLURM_ARRAY_JOB_ID>_<GPU_PROFILE>_0-249/
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

## Example Workflow

- Prepare input (`input.json`) with your protein sequences.
- Prepare cluster configuration file.
- Adjust configuration inside `submit_data_pipeline.sh`.
- Submit the pipeline to your HPC cluster (SLURM).
- Collect statistics from the generated CSV files.
