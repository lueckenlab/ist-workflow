#!/bin/bash
# Nextflow head job for the HMGU HPC: every workflow task is submitted as its own SLURM job
# (configs/hmgu_hpc.config) and runs in the pre-pulled Apptainer images.
#
#   sbatch scripts/hpc/run_hpc.sbatch <raw_ist.zarr> <scrnaseq_reference.h5ad> [methods_config.yaml] [publish_dir]
#
# Submit from the repo root (logs/ is relative to the submission dir). Before the first run:
#   scripts/build.sh
#   sbatch scripts/hpc/pull_images.sbatch --methods_config <same methods_config.yaml>
#
# The head only supervises (1 CPU is enough). cpu_p / cpu_normal caps it at 1 day; a pipeline
# with 24 h methods (baysor, ssam, ...) can outlive that. Resubmitting continues from the
# cache (-resume), so a timeout loses no finished tasks.
#SBATCH --job-name=ist_workflow
#SBATCH --partition=cpu_p
#SBATCH --qos=cpu_normal
#SBATCH --nice=10000
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=1-00:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -euo pipefail

source scripts/check_inputs.sh
load_site
check_inputs "sbatch scripts/hpc/run_hpc.sbatch <raw_ist.zarr> <scrnaseq_reference.h5ad> [methods_config.yaml] [publish_dir]" "${1:-}" "${2:-}" "${3:-configs/default_methods.yaml}" "${4:-}"

input_sp=$(realpath "$1")
input_sc=$(realpath "$2")
methods_config=$(realpath "${3:-configs/default_methods.yaml}")
publish_dir=$(realpath -m "${4:-output/$(basename "${input_sp%.zarr}")}")
id=$(basename "${input_sp%.zarr}")

nextflow_hpc_env "$publish_dir"
params_file="$publish_dir/params.yaml"
cat > "$params_file" << HERE
id: $id
input_sp: $input_sp
input_sc: $input_sc
methods_config: $methods_config
publish_dir: $publish_dir
HERE

nextflow run . \
  -main-script target/nextflow/workflows/ist_preprocessing/main.nf \
  -c configs/hmgu_hpc.config \
  -params-file "$params_file" \
  -resume
