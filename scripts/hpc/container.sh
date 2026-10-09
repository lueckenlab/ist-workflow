# Sourced by the prepare sbatch scripts: run a command in one of the Apptainer images in sif_dir
# (configs/site.yaml), with the same setup as configs/singularity.config: no /tmp, a writable
# HOME and caches in a work dir.
#
#   in_image <docker uri> <work_dir> [<bind> ...] -- <command ...>
#
# A bind is "path" or "src:dst[:ro]". Requires IST_SIF_DIR (load_site in scripts/check_inputs.sh).

# Images used by the data preparation (pulled with: pull_images.sbatch --prepare)
PREP_XENIUM_IMAGE="ghcr.io/openproblems-bio/task_ist_preprocessing/datasets/loaders/tenx_xenium:build_main"  # spatialdata-io
PREP_REFERENCE_IMAGE="ghcr.io/openproblems-bio/task_ist_preprocessing/methods_cell_type_annotation/tacco:build_main"  # scanpy

in_image() {
  local uri="$1" work="$2"
  shift 2
  local binds=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do binds+=(-B "$1"); shift; done
  shift  # --
  # Nextflow's file name for the image (scripts/hpc/list_images.py)
  local img="$IST_SIF_DIR/$(echo "$uri" | sed 's#[/:]#-#g').img"
  if [[ ! -s "$img" ]]; then
    echo "ERROR: $img not found; pull it first: sbatch scripts/hpc/pull_images.sbatch --prepare" >&2
    return 1
  fi
  mkdir -p "$work"
  apptainer exec --no-home --home "$work:$work" -B "$work" "${binds[@]}" \
    --env TMPDIR="$work" --env NUMBA_CACHE_DIR="$work/.numba_cache" --env MPLCONFIGDIR="$work/.mplconfig" \
    "$img" "$@"
}
