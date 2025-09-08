import argparse
import json
import os
import sys
import itertools
import copy

RESULTS_DIR = "monomer_data"
INFERENCE_JOBS_DIR = "pending_jobs"
SMALL_DIR = os.path.join(INFERENCE_JOBS_DIR, "small")
LARGE_DIR = os.path.join(INFERENCE_JOBS_DIR, "large")

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

def parse_args():
    p = argparse.ArgumentParser(description="Generate AlphaFold3 input jobs from dimensions JSON.")
    p.add_argument("input_file",
                   help="JSON file with a list of dimensions (each a dict of protein->sequence).")
    p.add_argument("--seeds", required=True,
                   help="Comma-separated list of model seeds (e.g. 0,1,2).")
    p.add_argument("--sorting", dest="sorting", choices=["alpha", "input"], default="input",
                   help="Sort proteins within each dimension alphabetically ('alpha') or keep input order ('input').")
    p.add_argument("--mode", dest="mode", choices=["cartesian", "collapsed"], required=True,
                   help="Job generation mode: 'cartesian' (all combinations) or 'collapsed' (one job per dimension).")
    return p.parse_args()

def chain_id(idx: int) -> str:
    """Return chain IDs A–Z. Error if more than 26 proteins are requested."""
    if idx >= 26:
        raise ValueError("Too many proteins in a job (max 26 supported: A–Z).")
    return chr(65 + idx)

def main():
    args = parse_args()
    try:
        MODEL_SEEDS = [int(s) for s in args.seeds.split(",") if s.strip() != ""]
    except ValueError:
        print("ERROR: --seeds must be comma-separated integers (e.g. 0,1,2).", file=sys.stderr)
        sys.exit(1)

    # Load dimensions JSON
    with open(args.input_file, "r") as f:
        data = json.load(f)

    if not isinstance(data, list):
        raise ValueError("Input JSON must be a list of dimensions (each a dictionary).")

    # Validate dimensions and check sequence consistency across dimensions
    protein_to_input_seq = {}
    dimensions = []
    for idx, dim in enumerate(data):
        if not isinstance(dim, dict):
            raise ValueError(f"Dimension at index {idx} is not a dictionary.")
        for protein, sequence in dim.items():
            if not isinstance(sequence, str):
                raise ValueError(f"Invalid sequence for protein '{protein}' (dimension {idx}): must be a string.")
            prev = protein_to_input_seq.get(protein)
            if prev is not None and prev != sequence:
                raise ValueError(f"Inconsistent sequence for protein '{protein}' across dimensions.")
            protein_to_input_seq.setdefault(protein, sequence)
        dimensions.append(dim)

    # Compute per-dimension protein lists with requested ordering
    key_lists = []
    for dim in dimensions:
        keys = list(dim.keys())
        if args.sorting == "alpha":
            keys = sorted(keys)
        key_lists.append(keys)

    # Load monomer result JSONs
    all_proteins = set().union(*key_lists) if key_lists else set()
    protein_to_monomer_seqobj = {}
    for name in sorted(all_proteins):
        path = os.path.join(RESULTS_DIR, name, f"{name}_data.json")
        if not os.path.exists(path):
            raise FileNotFoundError(f"Missing monomer result: {path}")
        with open(path, "r") as f:
            md = json.load(f)
        seq_obj = md["sequences"][0].copy()
        protein_to_monomer_seqobj[name] = seq_obj

    # Prepare output directory
    os.makedirs(SMALL_DIR, exist_ok=True)
    os.makedirs(LARGE_DIR, exist_ok=True)

    # Generate unique jobs (order-insensitive tuples)
    seen = set()
    small_index = 0
    large_index = 0

    if args.mode == "cartesian":
        iterator = itertools.product(*key_lists)
    elif args.mode == "collapsed":
        # One job per dimension
        iterator = key_lists

    for choice in iterator:
        choice_tuple = tuple(choice)
        canon = tuple(sorted(choice))
        if canon in seen:
            continue
        seen.add(canon)

        if len(choice_tuple) > 26:
            raise ValueError("Job has more than 26 proteins, cannot assign chain IDs beyond Z.")

        sequences = []
        for pos, protein in enumerate(choice_tuple):
            seq_obj = copy.deepcopy(protein_to_monomer_seqobj[protein])

            # Strict check for protein structure
            if "protein" not in seq_obj or not isinstance(seq_obj["protein"], dict):
                raise ValueError(f"Invalid monomer JSON for protein '{protein}': missing or malformed 'protein' key.")

            seq_obj["protein"]["id"] = chain_id(pos)
            sequences.append(seq_obj)

        job_name = "_".join(choice_tuple)
        job_data = {
            "dialect": "alphafold3",
            "version": 3,
            "name": job_name,
            "sequences": sequences,
            "modelSeeds": MODEL_SEEDS,
            "bondedAtomPairs": None,
            "userCCD": None
        }

        # Compute token size
        token_size = sum(len(seq_obj["protein"]["sequence"]) for seq_obj in sequences)

        # Pick target directory & index
        if token_size <= 3072:
            target_dir = SMALL_DIR
            job_file = os.path.join(target_dir, f"{small_index}_{job_name}.json")
            small_index += 1
        else:
            target_dir = LARGE_DIR
            job_file = os.path.join(target_dir, f"{large_index}_{job_name}.json")
            large_index += 1

        dump_compact_lists(job_data, job_file)
        print(f"Created {job_file} (token size {token_size})", file=sys.stderr)

    # Final summary
    print(f"{small_index} {large_index}")

if __name__ == "__main__":
    main()
