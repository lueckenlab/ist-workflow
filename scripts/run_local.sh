#!/bin/bash
# Run the workflow on one dataset, with all tasks on the current machine (Apptainer images from
# IST_SIF_DIR, see scripts/hpc/pull_images.sh). On the HMGU cluster use
# scripts/hpc/run_hpc.sbatch instead, which submits every task as its own SLURM job.
#
#   scripts/run_local.sh <raw_ist.zarr> <scrnaseq_reference.h5ad> [methods_config.yaml] [publish_dir]
#
set -e
cd "$(git rev-parse --show-toplevel)"

source scripts/check_inputs.sh
load_site
check_inputs "scripts/run_local.sh <raw_ist.zarr> <scrnaseq_reference.h5ad> [methods_config.yaml] [publish_dir]" "${1:-}" "${2:-}" "${3:-configs/default_methods.yaml}" "${4:-}"

input_sp=$(realpath "$1")
input_sc=$(realpath "$2")
methods_config=$(realpath "${3:-configs/default_methods.yaml}")
publish_dir=$(realpath -m "${4:-output/$(date +%Y-%m-%d_%H-%M-%S)}")
id=$(basename "${input_sp%.zarr}")

# Temp dir of Nextflow and of every task (viash VIASH_META_TEMP_DIR), instead of /tmp
export NXF_TEMP="${NXF_TEMP:-$publish_dir/tmp}"
mkdir -p "$publish_dir" "$NXF_TEMP"
params_file="$publish_dir/params.yaml"
cat > "$params_file" << HERE
id: $id
input_sp: $input_sp
input_sc: $input_sc
methods_config: $methods_config
publish_dir: $publish_dir
HERE

# For several datasets, replace id/input_* with the task_ist_preprocessing state form and add
# `-entry auto` below (the auto entry only reads input_states, it ignores id/input_*):
#   input_states: <dir>/**/state.yaml
#   rename_keys: 'input_sc:output_sc;input_sp:output_sp'

nextflow run . \
  -main-script target/nextflow/workflows/ist_preprocessing/main.nf \
  -c configs/singularity.config \
  -params-file "$params_file" \
  -resume
