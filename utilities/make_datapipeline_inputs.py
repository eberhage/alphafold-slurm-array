import os
import json
import sys

OUTPUT_DIR = "data_pipeline_inputs"
input_file = os.environ["INPUT_FILE"]

# Ensure output directory exists
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Load JSON once
with open(input_file, "r") as f:
    dimensions = json.load(f)

# protein_name → first seen protein_seq
first_seen_sequences = {}
file_index = 0

for dim_idx, dimension in enumerate(dimensions):
    if not isinstance(dimension, dict):
        continue

    for protein_name, protein_seq in dimension.items():
        if protein_name not in first_seen_sequences:
            # First time we see this protein → store and write JSON
            first_seen_sequences[protein_name] = protein_seq

            out_json = {
                "name": protein_name,
                "sequences": [
                    {
                        "protein": {
                            "id": "A",
                            "sequence": protein_seq
                        }
                    }
                ],
                "dialect": "alphafold3",
                "version": 3,
                "modelSeeds": [0]
            }

            out_path = os.path.join(OUTPUT_DIR, f"{file_index}_{protein_name}.json")
            with open(out_path, "w") as out_f:
                json.dump(out_json, out_f, indent=4)

            file_index += 1

        else:
            # Already seen this protein → check consistency
            if first_seen_sequences[protein_name] != protein_seq:
                sys.stderr.write(
                    f"ERROR: Protein '{protein_name}' has inconsistent sequences.\n"
                    f"  First seen: {first_seen_sequences[protein_name]}\n"
                    f"  At dimension {dim_idx}: {protein_seq}\n"
                )
                sys.exit(1)
