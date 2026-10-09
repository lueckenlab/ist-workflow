#!/bin/bash
# Pull/convert the workflow's images on a compute node.
#
#   sbatch scripts/hpc/pull_images.sbatch [--methods_config my_methods.yaml | --all] [--prepare] [--force]
#
# Submit from the repo root (logs/ is relative to the submission dir).
# cpu_p / cpu_normal: 1-day cap; 8 h is plenty for the full set (~33 images).
# --nice=10000 is the HMGU baseline (lower = higher priority).
#SBATCH --job-name=ist_pull_images
#SBATCH --partition=cpu_p
#SBATCH --qos=cpu_normal
#SBATCH --nice=10000
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err
#SBATCH --no-requeue

set -euo pipefail
scripts/hpc/pull_images.sh "$@"
