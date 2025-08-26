import json
import itertools
import sys

# Step 0: Read the JSON file path from command-line arguments
if len(sys.argv) != 2:
    print(f"Usage: python {sys.argv[0]} <json_file_path>")
    sys.exit(1)

json_file_path = sys.argv[1]

# Step 1: Read the JSON file
with open(json_file_path, 'r') as f:
    data = json.load(f)

# Step 2: Validate structure
if not isinstance(data, list):
    raise ValueError("JSON must contain a list of dimensions (dictionaries).")

for dimension in data:
    if not isinstance(dimension, dict):
        raise ValueError("Each item must be a dimension (dictionary)")
    for protein, sequence in dimension.items():
        if sequence is None or not isinstance(sequence, str):
            raise ValueError(f"Invalid sequence for protein '{protein}' in dimension: must be a non-empty string.")

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

all_combinations = itertools.product(*protein_lists)

# Deduplicate combinations by sorting proteins (order doesn't matter)
unique_jobs = {tuple(sorted(comb)) for comb in all_combinations}
unique_jobs_count = len(unique_jobs)

# Step 7: Output results
print(f"{unique_proteins_count} {unique_jobs_count}")