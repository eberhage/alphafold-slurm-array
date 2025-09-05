import sys
import re
import json
import itertools

VALID_AA = set("ACDEFGHIKLMNPQRSTVWY")
VALID_FILENAME_REGEX = re.compile(r'^[A-Za-z0-9_-]+$')

# Read arguments
if len(sys.argv) != 3:
    print(f"Usage: python {sys.argv[0]} <json_file_path> <mode>", file=sys.stderr)
    sys.exit(1)

json_file_path = sys.argv[1]
MODE = sys.argv[2].lower()

with open(json_file_path, 'r') as f:
    data = json.load(f)

error_found = False

if not isinstance(data, list):
    print("ERROR: JSON must contain a list of dimensions (dictionaries).", file=sys.stderr)
    sys.exit(1)

if MODE not in ("cartesian", "collapsed"):
    print(f"ERROR: MODE must be 'cartesian' or 'collapsed'. Got '{MODE}'", file=sys.stderr)
    error_found = True

for idx, dimension in enumerate(data):
    if not isinstance(dimension, dict):
        print(f"ERROR: Dimension at index {idx} is not a dictionary.", file=sys.stderr)
        error_found = True
        continue

    for protein, sequence in dimension.items():
        if not isinstance(protein, str) or not VALID_FILENAME_REGEX.match(protein):
            print(f"ERROR: Invalid protein name in dimension {idx}: '{protein}'", file=sys.stderr)
            error_found = True
        if not isinstance(sequence, str) or not sequence or not all(aa.upper() in VALID_AA for aa in sequence):
            print(f"ERROR: Invalid sequence for protein '{protein}' in dimension {idx}: '{sequence}'", file=sys.stderr)
            error_found = True

if error_found:
    sys.exit(1)

# Step 3 & 4: Check protein uniqueness and consistent sequences
global_protein_sequences = {}
for idx, dimension in enumerate(data):
    # Check duplicates inside the same dimension
    if len(dimension) != len(set(dimension.keys())):
        raise ValueError(f"Duplicate proteins found in dimension at index {idx}")
    
    for protein, sequence in dimension.items():
        if protein in global_protein_sequences:
            if global_protein_sequences[protein] != sequence:
                raise ValueError(f"Protein '{protein}' has inconsistent sequences across dimensions")
        else:
            global_protein_sequences[protein] = sequence

# Step 5: Count unique proteins
unique_proteins_count = len(global_protein_sequences)

# Step 6: Calculate unique jobs
protein_lists = [list(dimension.keys()) for dimension in data]

if MODE == "cartesian":
    # Cartesian product across all dimensions
    all_combinations = itertools.product(*protein_lists)
    # Deduplicate combinations (order doesn't matter)
    unique_jobs = {tuple(sorted(comb)) for comb in all_combinations}
    unique_jobs_count = len(unique_jobs)
elif MODE == "collapsed":
    # Each dimension collapsed into a single job (product of elements)
    # Each dimension's job is the sorted tuple of its proteins
    unique_jobs = {tuple(sorted(dim)) for dim in protein_lists}
    unique_jobs_count = len(unique_jobs)

# Step 7: Output results
print(f"{unique_proteins_count} {unique_jobs_count}")
