import json
import sys
import os
from rdkit import Chem


def count_explicit_atoms(smiles):
    """Count total atoms (only explicit!) in SMILES using RDKit just like AlphaFold does it."""
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return float('inf')  # Invalid SMILES → skip
    return mol.GetNumAtoms()


def main():
    SCREEN_FILE = os.environ.get("SCREEN_FILE", None)
    MAX_COMPOUND_ATOMS = os.environ.get("MAX_COMPOUND_ATOMS", None)

    # Validate SCREEN_FILE exists
    if not os.path.isfile(SCREEN_FILE):
        print(f"Error: SCREEN_FILE '{SCREEN_FILE}' not found.", file=sys.stderr)
        sys.exit(1)

    try:
        with open(SCREEN_FILE, 'r') as f:
            screen_data = json.load(f)
    except Exception as e:
        print(f"Error: Failed to read SCREEN_FILE '{SCREEN_FILE}': {e}", file=sys.stderr)
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
        num_atoms = count_explicit_atoms(smiles)
        
        # Skip if exceeds MAX_COMPOUND_ATOMS (if limit is set)
        if MAX_COMPOUND_ATOMS and num_atoms > int(MAX_COMPOUND_ATOMS):
            continue

        valid_compounds += 1
        total_compounds += 1  # Only count if valid

    print(f"{total_compounds} {valid_compounds}")


if __name__ == "__main__":
    main()