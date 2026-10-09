#!/usr/bin/env python3
"""List the docker images the workflow needs, with the file name Nextflow expects for each
Singularity/Apptainer image.

Reads the built components under target/dependencies (run scripts/build.sh first). With
--methods_config only the images of the selected methods are listed (plus aggregate_spatial_data,
and alpha_shapes only when normalization is normalize_by_volume) -- the images are several GB
each, so pulling all ~33 is rarely what you want.

Output: one line per image, "<docker uri>\t<image file name>".
"""
import argparse
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
DEP_DIR = REPO_ROOT / "target/dependencies/github/openproblems-bio/task_ist_preprocessing/build/main/nextflow"
DEFAULTS = REPO_ROOT / "configs/default_methods.yaml"
# Images of the data preparation (datasets/container.sh, used by prepare_*.sbatch)
PREPARE_IMAGES = [
    "ghcr.io/openproblems-bio/task_ist_preprocessing/datasets/loaders/tenx_xenium:build_main",
    "ghcr.io/openproblems-bio/task_ist_preprocessing/methods_cell_type_annotation/tacco:build_main",
]

# step in methods_config -> component namespace
STEP_NAMESPACE = {
    "segmentation": "methods_segmentation",
    "transcript_assignment": "methods_transcript_assignment",
    "count_aggregation": "methods_count_aggregation",
    "qc_filtering": "methods_qc_filter",
    "volume_calculation": "methods_calculate_cell_volume",
    "normalization": "methods_normalization",
    "celltype_annotation": "methods_cell_type_annotation",
    "expression_correction": "methods_expression_correction",
    "gene_efficiency_correction": "methods_gene_efficiency_correction",
}

CONTAINER_RE = re.compile(
    r'"container" : \{\s*"registry" : "([^"]+)",\s*"image" : "([^"]+)",\s*"tag" : "([^"]+)"'
)


def image_of(component_dir: Path) -> str:
    text = (component_dir / "main.nf").read_text()
    m = CONTAINER_RE.search(text)
    if not m:
        sys.exit(f"No container found in {component_dir}/main.nf")
    registry, image, tag = m.groups()
    return f"{registry}/{image}:{tag}"


def nextflow_image_name(uri: str) -> str:
    # Nextflow's SingularityCache naming: '/' and ':' become '-', suffix '.img'.
    # A file with this name in singularity.libraryDir/cacheDir is used instead of pulling.
    return re.sub(r"[/:]", "-", uri) + ".img"


def selected_components(methods_config):
    def load(path):
        with open(path) as f:
            return yaml.safe_load(f) or {}

    cfg = {step: (v if isinstance(v, dict) else {"method": v}) for step, v in load(DEFAULTS).items()}
    if methods_config:
        for step, v in load(methods_config).items():
            if step not in STEP_NAMESPACE:
                sys.exit(f"Unknown step '{step}' in {methods_config}")
            cfg[step] = v if isinstance(v, dict) else {"method": v}

    steps = dict(cfg)
    # the volume step only runs for normalize_by_volume (same rule as main.nf)
    if steps["normalization"]["method"] != "normalize_by_volume":
        steps.pop("volume_calculation")

    comps = [f"{STEP_NAMESPACE[s]}/{v['method']}" for s, v in steps.items()]
    return comps + ["methods_data_aggregation/aggregate_spatial_data"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--methods_config", help="only list images for the methods in this config")
    parser.add_argument("--all", action="store_true", help="list the images of every method")
    parser.add_argument("--prepare", action="store_true", help="add the images of the data preparation")
    args = parser.parse_args()

    if not DEP_DIR.exists():
        sys.exit(f"{DEP_DIR} not found - run scripts/build.sh first")

    if args.all:
        comps = sorted(str(p.parent.relative_to(DEP_DIR)) for p in DEP_DIR.glob("*/*/main.nf"))
    else:
        comps = selected_components(args.methods_config)

    uris = []
    for comp in comps:
        comp_dir = DEP_DIR / comp
        if not comp_dir.exists():
            sys.exit(f"Component {comp} not found in {DEP_DIR}")
        uris.append(image_of(comp_dir))
    if args.prepare:
        uris += PREPARE_IMAGES
    for uri in dict.fromkeys(uris):  # unique, in order
        print(f"{uri}\t{nextflow_image_name(uri)}")


if __name__ == "__main__":
    main()
