# ist_workflow

> Full guide (steps, methods, resources, all ways to run, troubleshooting): [.claude/PIPELINE.md](.claude/PIPELINE.md)

Run **one** imaging-based spatial transcriptomics preprocessing pipeline on your own data, using
the method implementations from the
[task_ist_preprocessing](https://github.com/openproblems-bio/task_ist_preprocessing) benchmark.

- **Input:** a raw iST SpatialData zarr (`raw_ist.zarr`) and a single-cell reference
  (`scrnaseq_reference.h5ad`), in the task_ist_preprocessing formats. There are no dataset loaders;
  bring data in that format (e.g. via that repo's `process_datasets` workflow).
- **Steps:** segmentation → transcript assignment → count aggregation → QC filter →
  (cell volume) → normalization → cell type annotation → expression correction →
  gene-efficiency correction → spatial data aggregation.
- **Output:** `output.zarr` (aggregated SpatialData) and `counts.h5ad` (final corrected counts with
  cell types) per dataset, plus `state.yaml`. No metrics are computed.

## Agentic setup
- **Define methods**: use skill `/benchmark-results` with the metric yaml file from the benchmarking step to decide on which methods to use
- 
- **Prepare for the run**: use skil `/ist-run-config method names` to prepare config file with needed methods and corresponding parameters
## Choosing methods

One method per step, in a YAML file passed as `methods_config`. See
[`configs/default_methods.yaml`](configs/default_methods.yaml) for every step, its options, and the
defaults. Example:

```yaml
segmentation:
  method: cellpose
  args: {diameter: 30}
transcript_assignment:
  method: proseg
celltype_annotation:
  method: tangram
```

Omitted steps use the defaults. Unknown steps or method names fail at start-up.
`volume_calculation` only runs when `normalization` is `normalize_by_volume`.

## No duplicated code

`src/workflows/ist_preprocessing/config.vsh.yaml` lists every method as a dependency with
`repository: tip`, which `_viash.yaml` points to
`openproblems-bio/task_ist_preprocessing@build/main`. `viash ns build` fetches those built
components into `target/dependencies/`, and Nextflow pulls their containers from
`ghcr.io/openproblems-bio/task_ist_preprocessing`. To change a method, change it there.

## Usage on the HMGU HPC (SLURM + Apptainer)

The methods ship as docker images on ghcr.io. Docker isn't available on the cluster, so they are
converted to Apptainer images once, ahead of the run. First set where the images and downloaded
models go (required, per user; the file is git-ignored):

```bash
cp configs/site.example.yaml configs/site.yaml   # then edit sif_dir and model_cache
scripts/build.sh                                                       # needs viash 0.9.7
mkdir -p logs
sbatch scripts/hpc/pull_images.sbatch --methods_config my_methods.yaml # or --all (~33 images)
sbatch scripts/hpc/run_hpc.sbatch raw_ist.zarr scrnaseq_reference.h5ad my_methods.yaml output/run1
```

- **Images:** `scripts/hpc/pull_images.sh` writes them to `sif_dir` from `configs/site.yaml`.
  They are named as Nextflow
  expects in `singularity.libraryDir`, so runs use them without pulling. It only pulls the images
  of the methods in the given config, and skips images that already exist. The upstream tag is
  `build_main`, which moves; re-pull with `--force` after the methods change upstream.
- **`configs/singularity.config`:** Apptainer settings, resource labels (memory grows on
  retry), and `--nv` for the GPU methods.
- **`configs/hmgu_hpc.config`:** includes the above and adds the SLURM executor. CPU tasks go to
  `cpu_p`/`cpu_normal`, GPU tasks to `gpu_p`/`gpu_normal` with `--gres=gpu:1`. segger, tangram
  and moscot ask for `gpu:h100:1`. All jobs use `--nice=10000`, the HMGU baseline. Extra SLURM
  flags can go in `IST_SLURM_OPTS`.
- **`run_hpc.sbatch`:** the Nextflow head job, capped at 1 day by `cpu_normal`. Resubmitting
  resumes from the cache.
- **`test_hpc.sbatch`:** the same head job on the task_ist_preprocessing mouse brain test data
  (downloaded to `resources_test/` if missing), publishing to `output/test_mouse_brain_combined`:
  `sbatch scripts/hpc/test_hpc.sbatch [methods_config.yaml] [publish_dir]`.

### Whole Xenium datasets

`scripts/hpc/run_xenium_hpc.sbatch <dataset_dir> <reference.h5ad | URL> [methods_config] [out_dir]`
first converts every sample of a raw Xenium dataset (SCHEMA folder layout, split into sample areas
by Xenium Explorer polygons) and the reference into the pipeline format, then runs the pipeline on
all of them. Details: `.claude/PIPELINE.md` section 8f.

## Usage on a single machine

```bash
scripts/run_local.sh raw_ist.zarr scrnaseq_reference.h5ad my_methods.yaml output/run1
```

This runs every task on the current machine, using the same Apptainer images
(`configs/singularity.config`).
