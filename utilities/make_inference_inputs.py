import json
import os
import sys
import itertools
import copy

monomer_dir = "monomer_data"
INFERENCE_JOBS_DIR = "pending_jobs"
TOO_BIG_FILE = "too_big.json"
msas_dir = "msas"
templates_dir = "templates"

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
            if any(isinstance(el, dict) for el in o):
                items = []
                for el in o:
                    items.append(" " * ((level+1) * indent) + _dump(el, level+1))
                return "[\n" + ",\n".join(items) + "\n" + " " * (level * indent) + "]"
            else:
                return "[" + ",".join(_dump(el, level) for el in o) + "]"
        else:
            return json.dumps(o)
    return _dump(obj, 0)

def dump_compact_lists(obj, filename, indent=2):
    with open(filename, "w") as f:
        f.write(dumps_compact_lists(obj, indent))

def chain_id(idx: int) -> str:
    if idx >= 26:
        raise ValueError("Too many proteins in a job (max 26 supported: A–Z).")
    return chr(65 + idx)

def main():
    # Read environment variables
    INPUT_FILE = os.environ["INPUT_FILE"]
    SEEDS = os.environ["SEEDS"]
    MODE = os.environ["MODE"]
    SORTING = os.environ.get("SORTING", "input")

    # Load cluster config
    CLUSTER_CONFIG = os.environ["CLUSTER_CONFIG"]
    with open(CLUSTER_CONFIG, "r") as f:
        cluster_conf = json.load(f)

    GPU_PROFILES = os.environ.get("GPU_PROFILES", "")
    if GPU_PROFILES:
        GPU_PROFILES = [p.strip() for p in GPU_PROFILES.split(",")]
    else:
        GPU_PROFILES = list(cluster_conf.get("gpu_profiles", {}).keys())

    # Sort GPU profiles by token limit ascending
    sorted_profiles = sorted(
        GPU_PROFILES,
        key=lambda p: cluster_conf["gpu_profiles"][p]["token_limit"]
    )

    profile_limits = {}
    for profile in sorted_profiles:
        profile_limits[profile] = cluster_conf["gpu_profiles"][profile]["token_limit"]

    GPU_PROFILES = sorted_profiles  # now ensures profiles are always in ascending order

    # Track job indices per profile
    profile_indices = {profile: 0 for profile in GPU_PROFILES}
    too_big_jobs = []

    try:
        MODEL_SEEDS = [int(s) for s in SEEDS.split(",") if s.strip() != ""]
    except ValueError:
        print("ERROR: SEEDS must be comma-separated integers (e.g. 0,1,2).", file=sys.stderr)
        sys.exit(1)

    # Load dimensions JSON
    with open(INPUT_FILE, "r") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError("Input JSON must be a list of dimensions (each a dictionary).")

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
        if SORTING == "alpha":
            keys = sorted(keys)
        key_lists.append(keys)

    # Load monomer result JSONs
    all_proteins = set().union(*key_lists) if key_lists else set()
    protein_to_monomer_seqobj = {}
    for name in sorted(all_proteins):
        path = os.path.join(monomer_dir, f"{name}_data.json")
        if not os.path.exists(path):
            raise FileNotFoundError(f"Missing monomer result: {path}")
        with open(path, "r") as f:
            md = json.load(f)
        seq_obj = md["sequences"][0].copy()
        protein_to_monomer_seqobj[name] = seq_obj

    seen = set()

    if MODE == "cartesian":
        iterator = itertools.product(*key_lists)
    elif MODE == "collapsed":
        iterator = key_lists
    else:
        raise ValueError("MODE must be 'cartesian' or 'collapsed'.")

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

        token_size = sum(len(seq_obj["protein"]["sequence"]) for seq_obj in sequences)

        assigned = False
        for profile in GPU_PROFILES:
            if token_size <= profile_limits[profile]:
                target_dir = os.path.join(INFERENCE_JOBS_DIR, profile)
                os.makedirs(target_dir, exist_ok=True)
                msas_link = os.path.join(target_dir, msas_dir)
                msas_target = os.path.join("..", "..", monomer_dir, msas_dir)
                os.path.islink(msas_link) or os.symlink(msas_target, msas_link, target_is_directory=True)
                templates_link = os.path.join(target_dir, templates_dir)
                templates_target = os.path.join("..", "..", monomer_dir, templates_dir)
                os.path.islink(templates_link) or os.symlink(templates_target, templates_link, target_is_directory=True)
                idx = profile_indices[profile]
                job_file = os.path.join(target_dir, f"{idx}_{job_name}.json")
                profile_indices[profile] += 1
                dump_compact_lists(job_data, job_file)
                print(f"Created {job_file} (token size {token_size})", file=sys.stderr)
                assigned = True
                break

        if not assigned:
            too_big_jobs.append({"name": job_name, "token_size": token_size})

    # Write too-big jobs list
    if too_big_jobs:
        with open(TOO_BIG_FILE, "w") as f:
            json.dump(too_big_jobs, f, indent=2)
        print(f"{len(too_big_jobs)} jobs too big -> written to {TOO_BIG_FILE}", file=sys.stderr)

    # Final summary
    output = {
        "total_jobs": sum(profile_indices.values()) + len(too_big_jobs),
        "profiles": {},
        "too_big_jobs": too_big_jobs
    }

    for profile in GPU_PROFILES:
        output["profiles"][profile] = {
            "jobs": profile_indices[profile],
            "min": 0 if profile == GPU_PROFILES[0] else profile_limits[GPU_PROFILES[GPU_PROFILES.index(profile)-1]] + 1,
            "max": profile_limits[profile]
        }

    print(json.dumps(output))

if __name__ == "__main__":
    main()
