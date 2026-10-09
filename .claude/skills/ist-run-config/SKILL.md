---
name: ist-run-config
description: Prepare an ist_workflow run for a user-chosen selection of methods — write the methods_config YAML, validate it, check which Apptainer images are missing, and give the pull-images + run commands (HPC/SLURM or local, test data or own data). Use whenever the user names methods to run (e.g. "cellpose + proseg + tangram", "use resolVI", "run with baysor"), asks for a new/custom methods config, or wants to know what pulling/running a method combination needs.
---

# Prepare a methods config + pull/run commands for ist_workflow

Repo root: the git root containing `_viash.yaml` with `name: ist_workflow`. Prerequisite:
`configs/site.yaml` must exist (copy `configs/site.example.yaml`, set `sif_dir` and `model_cache`);
if `describe_config.py` reports it missing, tell the user to create it. Full background is in
`.claude/PIPELINE.md` (steps, methods table, resources, ways to run).

## 1. Map the user's methods to steps

One method per step; steps the user doesn't mention keep the defaults. Valid names (source of
truth: `configs/default_methods.yaml`; `DEFAULT_METHODS` / the `*_methods` lists in
`src/workflows/ist_preprocessing/main.nf`):

| step | methods (default first) |
|---|---|
| segmentation | **custom_segmentation**, cellpose, cellposev4, binning, stardist, watershed |
| transcript_assignment | **basic_transcript_assignment**, baysor, clustermap, pciseq, comseg, proseg, segger, fastreseg |
| count_aggregation | **basic_count_aggregation** |
| qc_filtering | **basic_qc_filter** |
| volume_calculation | **alpha_shapes** (runs only with normalize_by_volume) |
| normalization | **normalize_by_volume**, normalize_by_counts, spanorm |
| celltype_annotation | **tacco**, ssam, moscot, mapmycells, tangram, singler, rctd |
| expression_correction | **no_correction**, resolvi_correction, split |
| gene_efficiency_correction | **no_correction**, gene_efficiency_correction |

Common user spellings: resolVI → `resolvi_correction`; "cellpose 4"/"cellpose v4" → `cellposev4`;
SpaNorm/"sparnom" → `spanorm`; "by counts"/"library size" → `normalize_by_counts`; "existing /
provided segmentation" → `custom_segmentation`; MapMyCells → `mapmycells`; RCTD → `rctd`.
`no_correction` exists in two steps — be explicit which one.

If a name is ambiguous or matches nothing, ask (AskUserQuestion) instead of guessing. If the user
gives method arguments, put them under `args` (component argument names without `--`).

## 2. Write the config

Path: `configs/methods_<short_names_joined_by_underscore>.yaml` (or the name the user gives).
Don't overwrite an existing file without looking at it and asking. Format, following
`configs/methods_cellposev4_proseg_spanorm_tangram_resolvi.yaml`:

- header comment: the chain of chosen methods, which steps fall back to defaults, whether
  volume_calculation runs, and the hardware notes from step 3;
- only the steps that differ from the defaults (or that the user explicitly set);
- per step `method:` plus the component's main args as **commented-out defaults**
  (`# args:` block), with user-set args uncommented.

## 3. Validate and check images

```bash
python3 .claude/skills/ist-run-config/describe_config.py configs/<file>.yaml
```

Prints per step: method, hardware (CPU / GPU / H100), labels, time limit, image `pulled` or
`MISSING`, and every argument with its default; exits with `ERROR:` on an unknown step, method or
argument. Fix the config until it passes. Use its output for the header comment and the summary.
If it says a component is missing although the name is valid, `scripts/build.sh` (viash 0.9.7)
has to be re-run first.

Flag to the user: GPU methods (gpu_p), H100 methods (segger, tangram, moscot; other GPU methods run on
A100/H100 only, never V100 — the images need CUDA 13), `veryhighmem` (480 GB: moscot, clustermap, comseg, fastreseg), and 24 h methods
(baysor, clustermap, fastreseg, pciseq, ssam, spanorm) — the head job's 1-day cap means a
resubmit (`-resume`) may be needed.

## 4. Give the commands — do NOT submit

Cluster jobs need explicit user approval (global rule), so print the commands and ask; only run
`sbatch` when the user says so. Always from the repo root, with `mkdir -p logs` first.

Pull only if step 3 reported missing images (existing ones are skipped anyway), and chain the run
on it so it only starts when every pull succeeded:

```bash
mkdir -p logs
jid=$(sbatch --parsable scripts/hpc/pull_images.sbatch --methods_config configs/<file>.yaml)
# test data (mouse brain, ~5 MB; downloaded if missing):
sbatch --dependency=afterok:$jid scripts/hpc/test_hpc.sbatch configs/<file>.yaml output/test_<name>
# or own data:
sbatch --dependency=afterok:$jid scripts/hpc/run_hpc.sbatch <raw_ist.zarr> <scrnaseq_reference.h5ad> configs/<file>.yaml output/<name>
```

Without missing images, drop the pull line and the `--dependency`. For a single node instead of
SLURM: `scripts/run_local.sh <raw_ist.zarr> <ref.h5ad> configs/<file>.yaml output/<name>` inside
an `salloc` allocation sized for the largest method (never on a login node).

Use a **separate publish_dir per method combination** — reusing one mixes results and caches.

For **raw Xenium data** (a SCHEMA dataset folder with `raw/` and `metadata/sample_areas.csv`)
instead of a ready `raw_ist.zarr`: add `--prepare` to the pull command and use
`sbatch datasets/run_xenium_hpc.sbatch <dataset_dir> <reference.h5ad | URL> configs/<file>.yaml <out_dir>`
(prepares and runs all samples; `IST_SAMPLES=a,b` for a test subset; `.claude/PIPELINE.md` 8f).

## Rules (learned on this cluster)

- **Never use `/tmp`** for temp/cache/scratch paths in configs, scripts, jobs or containers; use
  your Lustre workspace (as `sif_dir` / `model_cache` in `configs/site.yaml` do) or the task work dir. `/tmp` is not writable
  inside containers on compute nodes and fills up during image builds.
- **Don't edit a script or config while a job is running it** — bash reads scripts
  incrementally, and Nextflow reads configs at start (edits then silently don't apply).
- If a pull job fails, read `logs/ist_pull_images_<jobid>.err` before rerunning; a run whose images
  are missing pulls them in the 2-CPU head job, which is slow and can fail — better cancel it,
  fix and re-pull.
- After submission, monitor with `squeue --me`, `sacct -j <id>`, `logs/<job>_<id>.{out,err}` and
  `.nextflow.log`; a failing task's details are in its work dir `.command.err`.
