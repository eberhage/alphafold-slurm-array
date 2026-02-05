import json
import sys
from pathlib import Path

if len(sys.argv) != 3:
    print(f"Usage: python {sys.argv[0]} <inference_dir> <inference_name>", file=sys.stderr)
    sys.exit(1)

confidences = {}
pattern = f"seed-*_sample-*/{sys.argv[2]}_seed-*_sample-*_summary_confidences.json"

# Use glob to find all matching files
for json_file in Path(sys.argv[1]).glob(pattern):
    if not json_file.is_file():
        continue

    try:
        with open(json_file, 'r') as f:
            data = json.load(f)
        stem = json_file.stem
        parts = stem.split('_')
        seed_part = None
        sample_part = None
        for part in parts:
            if part.startswith("seed-"):
                seed_part = part
            if part.startswith("sample-"):
                sample_part = part
        if seed_part and sample_part:
            key = f"{seed_part}_{sample_part}"
        else:
            # Fallback: use the full stem if we can't parse
            key = stem

        confidences[key] = data

    except Exception as e:
        print(f"Warning: Could not read {json_file}: {e}", file=sys.stderr)

confidences = dict(sorted(confidences.items()))
print(json.dumps(confidences))
