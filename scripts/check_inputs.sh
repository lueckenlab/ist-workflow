# Shared helpers, sourced by the run scripts (run_local.sh, run_hpc.sbatch, run_xenium_hpc.sbatch,
# prepare_*.sbatch): load_site, check_inputs, nextflow_hpc_env.
#
# check_inputs fails fast, with a clear message, when the positional arguments are missing or in
# the wrong order (e.g. a methods config passed as the first argument), instead of failing
# inside the first pipeline task.
#
#   check_inputs <usage> <input_sp> <input_sc> <methods_config> <publish_dir>

# Export IST_SIF_DIR / IST_MODEL_CACHE from configs/site.yaml (see scripts/site_config.py);
# exits with a message if the file or a setting is missing.
load_site() {
  local exports
  exports=$(python3 scripts/site_config.py) || exit 1
  eval "$exports"
}

check_inputs() {
  local usage="$1" sp="${2%/}" sc="$3" cfg="$4" out="$5" err=()

  if [[ -z "$sp" || -z "$sc" ]]; then
    err+=("<raw_ist.zarr> and <scrnaseq_reference.h5ad> are required")
  else
    if [[ ! -d "$sp" || "$sp" != *.zarr ]]; then
      err+=("input_sp '$sp' must be an existing .zarr directory (raw iST SpatialData)")
    elif [[ ! -e "$sp/zarr.json" && ! -e "$sp/.zgroup" ]]; then
      err+=("input_sp '$sp' is not a zarr store (no zarr.json / .zgroup)")
    fi
    if [[ ! -f "$sc" || "$sc" != *.h5ad ]]; then
      err+=("input_sc '$sc' must be an existing .h5ad file (single-cell reference)")
    fi
  fi
  if [[ ! -f "$cfg" || ( "$cfg" != *.yaml && "$cfg" != *.yml ) ]]; then
    err+=("methods_config '$cfg' must be an existing .yaml file")
  fi
  if [[ "$out" == *.yaml || "$out" == *.yml || "$out" == *.zarr || "$out" == *.h5ad || -f "$out" ]]; then
    err+=("publish_dir '$out' looks like a file, not an output directory")
  fi

  if [[ ${#err[@]} -gt 0 ]]; then
    printf 'ERROR: %s\n' "${err[@]}" >&2
    echo "Usage: $usage" >&2
    echo "For the mouse brain test data use scripts/hpc/test_hpc.sbatch [methods_config.yaml] [publish_dir]." >&2
    exit 1
  fi
}

# Environment of a Nextflow head job on SLURM (run_hpc.sbatch, run_xenium_hpc.sbatch).
#   nextflow_hpc_env <publish_dir>
nextflow_hpc_env() {
  local publish_dir="$1"
  # Cap the Nextflow JVM below the job memory: by default it sizes its heap from the node's RAM
  # (up to 25% of e.g. 750 GB), not from the job limit, and gets OOM-killed by SLURM.
  export NXF_OPTS="${NXF_OPTS:--Xms1g -Xmx12g}"
  # Work dir on group Lustre, not $HOME (50 GB quota); NXF_WORK overrides.
  export NXF_WORK="${NXF_WORK:-$publish_dir/work}"
  # Temp dir of Nextflow and of every task (viash VIASH_META_TEMP_DIR), instead of /tmp
  export NXF_TEMP="${NXF_TEMP:-$publish_dir/tmp}"
  # Child jobs carry the same --comment as this head job, if it has one
  local comment
  comment=$(scontrol show job "${SLURM_JOB_ID:-}" 2>/dev/null | grep -oP 'Comment=\K\S+' || true)
  if [[ -n "$comment" && "$comment" != "(null)" ]]; then
    export IST_SLURM_OPTS="${IST_SLURM_OPTS:-} --comment=$comment"
  fi
  mkdir -p "$publish_dir" "$NXF_TEMP"
}
