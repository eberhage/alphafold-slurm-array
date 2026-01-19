import os
import json
import shutil
import argparse

def find_paths(obj, paths=None):
    """Recursively collect all unique values for keys containing 'Path'."""
    if paths is None:
        paths = set()  # use a set for deduplication

    if isinstance(obj, dict):
        for k, v in obj.items():
            if "Path" in k and isinstance(v, str):
                paths.add(v)
            else:
                find_paths(v, paths)
    elif isinstance(obj, list):
        for item in obj:
            find_paths(item, paths)

    return list(paths)

def main():
    parser = argparse.ArgumentParser(description="Copy files referenced by JSON Path keys.")
    parser.add_argument("json_file", help="Path to the JSON file")
    parser.add_argument("dest_dir", help="Directory to copy files into")
    args = parser.parse_args()

    json_file = os.path.abspath(args.json_file)
    json_dir = os.path.dirname(json_file)
    os.makedirs(args.dest_dir, exist_ok=True)

    # Load JSON
    with open(json_file) as f:
        data = json.load(f)

    # Find all paths
    file_paths = find_paths(data)
    if not file_paths:
        print("No Path keys found in JSON.")
    else:
        for rel_path in file_paths:
            # Resolve against JSON dir
            src_path = os.path.join(json_dir, rel_path)
            if os.path.exists(src_path):
                # Preserve structure relative to json_dir
                dest_path = os.path.join(args.dest_dir, rel_path)
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                shutil.copy2(src_path, dest_path)
                print(f"Copied {src_path} → {dest_path}")
            else:
                print(f"Warning: file not found: {src_path}")

    # Copy the JSON file itself
    dest_json = os.path.join(args.dest_dir, os.path.basename(json_file))
    shutil.copy2(json_file, dest_json)
    print(f"Copied input JSON → {dest_json}")

if __name__ == "__main__":
    main()
