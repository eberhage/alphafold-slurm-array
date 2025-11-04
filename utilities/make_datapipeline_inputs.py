import os
import json
import sys

OUTPUT_DIR = "data_pipeline_inputs"
MONOMER_DIR = "monomer_data"
input_file = os.environ["INPUT_FILE"]

os.makedirs(OUTPUT_DIR, exist_ok=True)

with open(input_file, "r") as f:
    dimensions = json.load(f)

first_seen_sequences = {}
file_index = 0


import os
import json
import sys

def check_existing_monomer_data(protein_name):
    """
    Returns True if monomer_data/{protein_name}_data.json exists
    and all unpairedMsaPath, pairedMsaPath, and mmcifPath files
    exist relative to that JSON file.

    Assumes that there is exactly one sequence entry in 'sequences'.
    Prints short messages to stderr for any missing or invalid items.
    """
    monomer_file = os.path.join(MONOMER_DIR, f"{protein_name}_data.json")
    if not os.path.exists(monomer_file):
        return False

    try:
        with open(monomer_file, "r") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        sys.stderr.write(f"[{protein_name}] Could not read or parse {monomer_file}\n")
        return False

    base_dir = os.path.dirname(monomer_file)

    # Expect one sequence entry
    sequences = data.get("sequences")
    if not isinstance(sequences, list) or not sequences:
        sys.stderr.write(f"[{protein_name}] Invalid or missing 'sequences' in {monomer_file}\n")
        return False

    seq_entry = sequences[0]
    if not isinstance(seq_entry, dict):
        sys.stderr.write(f"[{protein_name}] Invalid sequence entry format in {monomer_file}\n")
        return False

    protein_block = seq_entry.get("protein")
    if not isinstance(protein_block, dict):
        sys.stderr.write(f"[{protein_name}] Missing 'protein' section in {monomer_file}\n")
        return False

    # Check unpairedMsaPath and pairedMsaPath
    for key in ("unpairedMsaPath", "pairedMsaPath"):
        if key in protein_block:
            rel_path = protein_block[key]
            abs_path = os.path.join(base_dir, rel_path)
            if not os.path.exists(abs_path):
                sys.stderr.write(f"[{protein_name}] Missing {key} file: {rel_path}\n")
                return False

    # Check templates → mmcifPath
    templates = protein_block.get("templates", [])
    if isinstance(templates, list):
        for template in templates:
            if isinstance(template, dict) and "mmcifPath" in template:
                rel_path = template["mmcifPath"]
                abs_path = os.path.join(base_dir, rel_path)
                if not os.path.exists(abs_path):
                    sys.stderr.write(f"[{protein_name}] Missing mmcifPath file: {rel_path}\n")
                    return False
    else:
        sys.stderr.write(f"[{protein_name}] 'templates' is not a list in {monomer_file}\n")
        return False

    return True  # All checks passed


for dim_idx, dimension in enumerate(dimensions):
    if not isinstance(dimension, dict):
        continue

    for protein_name, protein_seq in dimension.items():
        if protein_name not in first_seen_sequences:
            first_seen_sequences[protein_name] = protein_seq

            # Skip creation if existing monomer data is complete
            if check_existing_monomer_data(protein_name):
                continue

            # Otherwise, create new JSON
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
            if first_seen_sequences[protein_name] != protein_seq:
                sys.stderr.write(
                    f"ERROR: Protein '{protein_name}' has inconsistent sequences.\n"
                    f"  First seen: {first_seen_sequences[protein_name]}\n"
                    f"  At dimension {dim_idx}: {protein_seq}\n"
                )
                sys.exit(1)

# Return the number of created JSON files
print(file_index)
