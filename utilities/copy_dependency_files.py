import os
import sys
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

    json_dir = os.path.dirname(os.path.abspath(args.json_file))
    os.makedirs(args.dest_dir, exist_ok=True)

    # Load JSON
    with open(args.json_file) as f:
        data = json.load(f)

    # Find all paths
    file_paths = find_paths(data)
    if not file_paths:
        print("No Path keys found in JSON.")
        return

    # Copy files preserving relative paths
    for path in file_paths:
        if os.path.exists(path):
            rel_path = os.path.normpath(path)
            dest_path = os.path.join(args.dest_dir, rel_path)
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            shutil.copy2(path, dest_path)
            print(f"Copied {path} → {dest_path}")
        else:
            print(f"Warning: file not found: {path}")

if __name__ == "__main__":
    main()
