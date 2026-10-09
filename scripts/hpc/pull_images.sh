#!/bin/bash
# Convert the workflow's docker images into Apptainer/Singularity images that Nextflow picks up
# from singularity.libraryDir (see configs/hmgu_hpc.config) instead of pulling at run time.
#
#   scripts/hpc/pull_images.sh [--methods_config my_methods.yaml | --all] [--prepare] [--force]
#   (--prepare: also the images of the data preparation, see scripts/hpc/container.sh)
#
# Run it inside a SLURM job (scripts/hpc/pull_images.sbatch), not on a login node: the
# conversion is CPU/IO-heavy and gets killed there.
#
# The images are tagged build_main, which moves whenever task_ist_preprocessing main changes.
# Existing images are kept; use --force to re-pull after the upstream methods were updated.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Where the images go: sif_dir in configs/site.yaml (required, see scripts/site_config.py)
exports=$(python3 scripts/site_config.py) || exit 1
eval "$exports"
SIF_DIR="$IST_SIF_DIR"

force=false
list_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=true; shift ;;
    --all) list_args+=(--all); shift ;;
    --prepare) list_args+=(--prepare); shift ;;
    --methods_config) list_args+=(--methods_config "$2"); shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$SIF_DIR"
# The apptainer layer cache defaults into $HOME (50 GB quota): keep it next to the images.
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-$SIF_DIR/.cache}"
# Build in node-local scratch, not on Lustre
export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-${SLURM_TMPDIR:-/localscratch/$USER/${SLURM_JOB_ID:-apptainer_tmp}}}"
# mksquashfs runs under proot, which writes its temp files to /tmp by default; /tmp is small and
# fills up with the GPU images ("proot error: can't create temporary file: No space left")
export PROOT_TMP_DIR="${PROOT_TMP_DIR:-$APPTAINER_TMPDIR}"
mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR"

images=$(python3 scripts/hpc/list_images.py "${list_args[@]}")
echo "Image dir: $SIF_DIR"
echo "$images" | cut -f1 | sed 's/^/  /'

failed=()
while IFS=$'\t' read -r uri name; do
  target="$SIF_DIR/$name"
  if [[ -s "$target" && "$force" == false ]]; then
    echo "[skip] $name exists"
    continue
  fi
  echo "[pull] docker://$uri"
  # pull to a temp name and move into place, so a failed pull never looks like a usable image
  if apptainer pull --force "$target.part" "docker://$uri"; then
    mv "$target.part" "$target"
  else
    rm -f "$target.part"
    failed+=("$uri")
  fi
done <<< "$images"

rm -rf "$APPTAINER_TMPDIR"

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Failed to pull:" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "All images in $SIF_DIR"
