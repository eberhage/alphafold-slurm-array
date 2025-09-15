import os
import json
import sys

# Constants
OUTPUT_DIR = "data_pipeline_inputs"

# Read environment variables
sorting = os.environ.get("SORTING", "input")
input_file = os.environ["INPUT_FILE"]

# Ensure output directory exists
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Load JSON once
with open(input_file, "r") as f:
    data = json.load(f)

# Collect first-seen values for each key, check consistency
first_seen = {}
for entry_idx, entry in enumerate(data):
    if isinstance(entry, dict):
        for k, v in entry.items():
            if k not in first_seen:
                first_seen[k] = v
            else:
                if first_seen[k] != v:
                    sys.stderr.write(
                        f"ERROR: Key '{k}' has inconsistent values.\n"
                        f"  First seen: {first_seen[k]}\n"
                        f"  At entry {entry_idx}: {v}\n"
                    )
                    sys.exit(1)

# Determine key order
if sorting == "input":
    names = list(first_seen.keys())   # order of appearance
elif sorting == "alpha":
    names = sorted(first_seen.keys()) # alphabetical
else:
    sys.stderr.write("ERROR: SORTING must be 'alpha' or 'input'\n")
    sys.exit(1)

# Write out JSON files
for idx, name in enumerate(names):
    out_json = {
        "name": name,
        "sequences": [
            {
                "protein": {
                    "id": "A",
                    "sequence": first_seen[name]
                }
            }
        ],
        "dialect": "alphafold3",
        "version": 3,
        "modelSeeds": [0]
    }

    out_path = os.path.join(OUTPUT_DIR, f"{idx}_{name}.json")
    with open(out_path, "w") as out_f:
        json.dump(out_json, out_f, indent=4)
