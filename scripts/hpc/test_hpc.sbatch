#!/bin/bash
# Test run on the task_ist_preprocessing mouse brain test data (~5 MB): the same head job as
# run_hpc.sbatch, with the inputs filled in. Downloads the test data first if it is missing.
#
#   sbatch scripts/hpc/test_hpc.sbatch [methods_config.yaml] [publish_dir]
#
# Submit from the repo root (logs/ is relative to the submission dir), after
#   sbatch scripts/hpc/pull_images.sbatch --methods_config <same methods_config.yaml>
#SBATCH --job-name=ist_workflow_test
#SBATCH --partition=cpu_p
#SBATCH --qos=cpu_normal
#SBATCH --nice=10000
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=08:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -euo pipefail

methods_config="${1:-configs/default_methods.yaml}"
publish_dir="${2:-output/test_mouse_brain_combined}"

s3_dir=s3://openproblems-data/resources_test/task_ist_preprocessing/mouse_brain_combined
test_dir=resources_test/task_ist_preprocessing/mouse_brain_combined
if [[ ! -e "$test_dir/raw_ist.zarr/zarr.json" || ! -s "$test_dir/scrnaseq_reference.h5ad" ]]; then
  mkdir -p "$test_dir"
  aws s3 sync --no-sign-request --quiet "$s3_dir/raw_ist.zarr" "$test_dir/raw_ist.zarr"
  aws s3 cp --no-sign-request --quiet "$s3_dir/scrnaseq_reference.h5ad" "$test_dir/"
fi

bash scripts/hpc/run_hpc.sbatch \
  "$test_dir/raw_ist.zarr" "$test_dir/scrnaseq_reference.h5ad" "$methods_config" "$publish_dir"
