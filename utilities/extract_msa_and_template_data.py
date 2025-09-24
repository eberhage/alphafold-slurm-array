import os
import json
import gzip
import argparse

# Argument parsing
parser = argparse.ArgumentParser(description="Extract MSAs and templates from AlphaFold3 JSON.")
parser.add_argument("input_file", help="Path to the input JSON file")
parser.add_argument("-z", "--gzip", action="store_true", help="Gzip the output files")
args = parser.parse_args()

use_gzip = args.gzip
input_file = args.input_file

# Folders relative to input file location
input_dir = os.path.dirname(os.path.abspath(input_file))
msa_folder = os.path.join(input_dir, "msas")
template_folder = os.path.join(input_dir, "templates")
os.makedirs(msa_folder, exist_ok=True)
os.makedirs(template_folder, exist_ok=True)

# Load JSON
with open(input_file) as f:
    data = json.load(f)

# Get the name for MSA files
name = data.get("name", "protein")

def dumps_compact_lists(obj, indent=2):
    def _dump(o, level=0):
        if isinstance(o, dict):
            items = []
            for k, v in o.items():
                items.append(
                    " " * ((level+1) * indent) + json.dumps(k) + ": " + _dump(v, level+1)
                )
            return "{\n" + ",\n".join(items) + "\n" + " " * (level * indent) + "}"
        elif isinstance(o, list):
            # check if list contains any dicts (or nested dicts)
            if any(isinstance(el, dict) for el in o):
                # pretty-print with indentation
                items = []
                for el in o:
                    items.append(" " * ((level+1) * indent) + _dump(el, level+1))
                return "[\n" + ",\n".join(items) + "\n" + " " * (level * indent) + "]"
            else:
                # collapse into one line
                return "[" + ",".join(_dump(el, level) for el in o) + "]"
        else:
            return json.dumps(o)

    return _dump(obj, 0)

def dump_compact_lists(obj, filename, indent=2):
    with open(filename, "w") as f:
        f.write(dumps_compact_lists(obj, indent))

def file_content_matches(path, new_content):
    """Check if file exists and has identical content."""
    if not os.path.exists(path):
        return False
    with open(path, "r") as f:
        existing_content = f.read()
    return existing_content == new_content

def get_unique_cif_path(base_path, new_content, use_gzip):
    """
    Return a path for the mmcif file.
    If base exists and is identical -> reuse.
    If base exists but differs -> create base_1, base_2, etc.
    """
    ext = ".cif.gz" if use_gzip else ".cif"
    base, _ = os.path.splitext(base_path)
    candidate = base + ext
    idx = 1

    while os.path.exists(candidate):
        # If file content matches -> reuse existing
        if use_gzip:
            with gzip.open(candidate, "rt") as f:
                if f.read() == new_content:
                    print(f"[INFO] Reusing existing mmcif file: {candidate}")
                    return candidate
        else:
            if file_content_matches(candidate, new_content):
                print(f"[INFO] Reusing existing mmcif file: {candidate}")
                return candidate

        # Otherwise, try with suffix
        candidate = f"{base}_{idx}{ext}"
        idx += 1

    # Return the first free candidate path
    print(f"[NEW] Will create new mmcif file: {candidate}")
    return candidate

# Helper to write gzipped or plain files
def write_file(path, content):
    if use_gzip:
        gz_path = path + ".gz"
        with gzip.open(gz_path, "wt") as gz:
            gz.write(content)
        return gz_path
    else:
        with open(path, "w") as f:
            f.write(content)
        return path

# Iterate over sequences
for seq_entry in data.get("sequences", []):
    protein = seq_entry.get("protein", {})

    # Handle unpaired MSA
    if "unpairedMsa" in protein and protein["unpairedMsa"]:
        unpaired_content = protein.pop("unpairedMsa")
        unpaired_file = os.path.join(msa_folder, f"{name}_unpaired.a3m")
        protein["unpairedMsaPath"] = os.path.relpath(write_file(unpaired_file, unpaired_content), input_dir)

    # Handle paired MSA
    if "pairedMsa" in protein and protein["pairedMsa"]:
        paired_content = protein.pop("pairedMsa")
        paired_file = os.path.join(msa_folder, f"{name}_paired.a3m")
        protein["pairedMsaPath"] = os.path.relpath(write_file(paired_file, paired_content), input_dir)

    # Handle templates
    for template in protein.get("templates", []):
        if "mmcif" in template and template["mmcif"]:
            cif_content = template.pop("mmcif")
            pdb_id_line = cif_content.splitlines()[0]
            pdb_id = pdb_id_line.replace("data_", "").strip()
            base_path = os.path.join(template_folder, pdb_id)

            # Deduplication + versioning check
            cif_path = get_unique_cif_path(base_path, cif_content, use_gzip)

            # If not already existing, write the file
            if not os.path.exists(cif_path):
                write_file(cif_path.replace(".gz", "") if use_gzip else cif_path, cif_content)

            template["mmcifPath"] = os.path.relpath(cif_path, input_dir)

# Save updated JSON in-place
dump_compact_lists(data, input_file)

print(f"Updated JSON saved in-place: {input_file}")
print(f"Output files {'gzipped' if use_gzip else 'plain'} in {msa_folder}/ and {template_folder}/")
