import json
import sys
import os
from rdkit import Chem


def count_total_atoms(smiles):
    """Count total atoms (including hydrogens) in SMILES using RDKit."""
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return float('inf')  # Invalid SMILES → skip
    return mol.GetNumAtoms()


def main():
    # Check for exactly two positional arguments
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <SCREEN_FILE> <MAX_COMPOUND_ATOMS>", file=sys.stderr)
        sys.exit(1)

    screen_file = sys.argv[1]
    max_atoms_str = sys.argv[2]

    # Validate MAX_COMPOUND_ATOMS
    try:
        max_atoms = int(max_atoms_str)
    except ValueError:
        print(f"Error: MAX_COMPOUND_ATOMS='{max_atoms_str}' is not a valid integer.", file=sys.stderr)
        sys.exit(1)

    # Read screen file
    if not os.path.isfile(screen_file):
        print(f"Error: SCREEN_FILE '{screen_file}' not found.", file=sys.stderr)
        sys.exit(1)

    try:
        with open(screen_file, 'r') as f:
            screen_data = json.load(f)
    except Exception as e:
        print(f"Error: Failed to read SCREEN_FILE '{screen_file}': {e}", file=sys.stderr)
        sys.exit(1)

    # Validate it's a list
    if not isinstance(screen_data, list):
        print(f"Error: SCREEN_FILE must contain a top-level list.", file=sys.stderr)
        sys.exit(1)

    total_compounds = 0
    valid_compounds = 0

    for i, item in enumerate(screen_data):
        if not isinstance(item, dict):
            print(f"Warning: Item {i} is not a dictionary. Skipping.", file=sys.stderr)
            continue

        if 'ID' not in item:
            print(f"Warning: Item {i} missing 'ID' key. Skipping.", file=sys.stderr)
            continue

        smiles = item.get('SMILES', '')

        # Skip if SMILES is empty
        if not smiles:
            continue

        # Count total atoms
        num_atoms = count_total_atoms(smiles)
        if num_atoms > max_atoms:
            continue

        valid_compounds += 1
        total_compounds += 1  # Only count if valid

    print(f"{total_compounds} {valid_compounds}")


if __name__ == "__main__":
    main()