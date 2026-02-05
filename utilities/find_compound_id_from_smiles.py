import os
import json
import sys
from typing import List, Dict, Any, Optional

def find_screen_id_from_smiles() -> Optional[str]:
    """
    Read SCREEN_FILE env var (path to a JSON file with list of dicts with 'ID' and 'SMILES' keys)
    and a JSON file passed as a positional argument.
    Return the 'ID' from the SCREEN_FILE where SMILES matches the ligand's 'smiles'
    in the provided JSON file.
    
    Prints all messages to stderr and only the matching ID to stdout.
    
    Returns:
        str: The matching ID, or None if no match found
    """
    # Read SCREEN_FILE from environment variable (it's a file path)
    screen_file_path = os.getenv("SCREEN_FILE")
    if not screen_file_path:
        return None

    # Check if the file exists
    if not os.path.isfile(screen_file_path):
        print(f"Error: SCREEN_FILE points to non-existent file: {screen_file_path}", file=sys.stderr)
        return None

    # Read the JSON file from the path
    try:
        with open(screen_file_path, 'r') as f:
            screen_data: List[Dict[str, Any]] = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in SCREEN_FILE: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error: Could not read SCREEN_FILE: {e}", file=sys.stderr)
        return None

    # Validate screen_data is a list
    if not isinstance(screen_data, list):
        print("Error: SCREEN_FILE must contain a JSON array", file=sys.stderr)
        return None

    # Validate each item in the list
    for i, item in enumerate(screen_data):
        if not isinstance(item, dict):
            print(f"Error: Item at index {i} in SCREEN_FILE is not a dictionary", file=sys.stderr)
            return None
        if "ID" not in item:
            print(f"Error: Item at index {i} in SCREEN_FILE is missing 'ID' key", file=sys.stderr)
            return None
        if "SMILES" not in item:
            print(f"Error: Item at index {i} in SCREEN_FILE is missing 'SMILES' key", file=sys.stderr)
            return None

    # Read positional argument (JSON file path)
    if len(sys.argv) < 2:
        print("Error: Missing positional argument: JSON file path", file=sys.stderr)
        return None

    json_file_path = sys.argv[1]

    try:
        with open(json_file_path, 'r') as f:
            json_data = json.load(f)
    except FileNotFoundError:
        print(f"Error: JSON file not found: {json_file_path}", file=sys.stderr)
        return None
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in provided file: {e}", file=sys.stderr)
        return None

    # Check if json_data has 'sequences' key
    if "sequences" not in json_data:
        print("Error: JSON file must contain a 'sequences' key", file=sys.stderr)
        return None

    sequences = json_data["sequences"]
    if not isinstance(sequences, list):
        print("Error: 'sequences' must be a list", file=sys.stderr)
        return None

    # Find the ligand object
    ligand_obj = None
    for seq in sequences:
        if isinstance(seq, dict) and len(seq) == 1 and "ligand" in seq:
            ligand_obj = seq["ligand"]
            break

    if not ligand_obj:
        print("Error: No ligand object found in sequences", file=sys.stderr)
        return None

    # Check if ligand_obj is a dict and has a 'smiles' key
    if not isinstance(ligand_obj, dict) or "smiles" not in ligand_obj:
        print("Error: Ligand object must be a dictionary with a 'smiles' key", file=sys.stderr)
        return None

    ligand_smiles = ligand_obj["smiles"]

    # Find matching ID in screen_data
    for item in screen_data:
        if item["SMILES"] == ligand_smiles:
            return item["ID"]

    # No match found
    return None

if __name__ == "__main__":
    result = find_screen_id_from_smiles()
    print(result)