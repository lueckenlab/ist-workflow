---
name: ist-method-recommendation
description: Recommend the best ist_workflow method per step (segmentation, transcript assignment, cell-type annotation, normalization, expression correction) for a tissue / disease / technology, from the txsim benchmark master run — its per-dataset HTML reports (dataset_reports/*.html), the segmentation / cell-type figures, and the master_run metric tables. Use whenever the user asks which methods are best/recommended for a dataset or sample type (e.g. "best methods for lung cancer", "what should I use for Xenium breast", "assess the methods in this report"), points at a dataset report, or wants a benchmark-based choice before building a methods config.
---

# Recommend methods from the txsim benchmark

Data live in the txsim analysis workspace (read-only — never modify anything there):
`/lustre/groups/luckylab/workspace/daria.romanovskaia/txsim_analysis` (also mounted as
`/ictstr01/...`):

| what | where |
|---|---|
| dataset metadata (tissue, disease, technology, sc reference) | `datasets_overview.csv` |
| per-dataset HTML report (Quarto) | `dataset_reports/<dataset_id with / → _>.html` |
| report figures + tables | `<run>/<dataset_id>/{segmentation_masks.png, segmentation_cells.csv, celltype_calls.png, celltype_composition.{png,csv}}` |
| metrics per dataset × variant | `master_run/<run>_{similarity,quality}_metrics.csv` (`_metrics_long.csv` has stage / control flags) |

The HTML reports contain **no scores** — only masks, cell-type maps and compositions. Scores come
from `master_run`. User-given report names may be slightly off (e.g. missing `_xenium`); `ls
dataset_reports/` and pick the match.

## Benchmark design (needed to read the numbers right)

One baseline chain — custom_segmentation → basic_transcript_assignment → tacco →
alpha_shapes + normalize_by_volume → no_correction — and **one step varied at a time**
(variant names `segm=`, `ta=`, `cta=`, `cell_vol_alpha=… | norm=`, `corr=`). So a result says
"method X vs the baseline method in that step"; combinations of winners were never run together.
Controls: `control: identity` (all 1.0) and `control: permute_celltype_annotations`.

## 1. Pull the metrics

```bash
python3 -I .claude/skills/ist-method-recommendation/metrics_table.py <pattern> [...] [--run <run_id>]
```

`<pattern>` is a regex over dataset ids or over tissue / disease / technology in
`datasets_overview.csv` — one dataset (`2023_10x_human_lung_cancer_xenium`) or a whole class
(`'lung.*cancer|cancer.*lung'`, `xenium`). Prints per dataset the full table, which metrics
**discriminate** (permuted-label control below the method median), per-stage ranks on those
metrics with the quality columns beside them, the report + figure paths, and for several datasets
a mean rank per method across datasets. Ask the user whether they want one dataset or the whole
class if unclear; when a class has several datasets, use the cross-dataset ranks as the primary
evidence and the single dataset as a check.

## 2. Look at the figures

Read `segmentation_masks.png` and `celltype_calls.png` (and the composition table/png) for the
dataset(s). Metrics alone mislead; the figures catch:
- cell-type maps that are **salt-and-pepper noise** or a near-uniform composition (tangram has
  done this — top metric rank, biologically meaningless map);
- one type painting the whole tissue (mapmycells / moscot calling everything "Transitioning
  epithelial");
- large unassigned fractions (rctd, ssam) — check `n_unassigned` / `proportion_of_annotated_cells`;
- masks that are nuclear-only, over-split, or a grid (binning).

Check plausibility against the tissue (e.g. lung adenocarcinoma → AT2-like epithelium dominant).

## 3. Judge — rules learned so far

- **Distrust non-discriminating metrics.** On lung cancer Xenium the permuted control beat every
  method on coexpr_similarity(_celltype), knn_mixing, neg_marker_purity_cells and
  rel_pairwise_gene_expr_sim; only rel_pairwise_ct_expr_sim and neg_marker_purity_reads were
  informative. Always say which metrics you relied on.
- **Weigh `proportion_of_assigned_reads`.** Nuclear-mask segmenters (cellpose, cellposev4,
  stardist, watershed) get high purity by keeping only 20–33 % of reads; segger ~70 %, resolvi
  correction ~56 %. A rank win that throws most reads away is not a win — unless paired with a
  transcript-assignment method that expands the cells.
- `number_of_cells` far from the vendor count = over-/under-segmentation (binning ~5×,
  clustermap ~⅓). Treat as a red flag.
- Differences in the 2nd–3rd decimal (normalization, often correction) are noise on one dataset —
  keep the default unless consistent across datasets.
- A method with NaN metrics (e.g. pciseq) failed or is missing on that dataset: report it as
  "no data", not as bad. In cross-dataset means, check `count` — a method present on 1 dataset
  isn't comparable to one present on 10.

## 4. Report

Lead with the design caveat (one-at-a-time, which datasets, which metrics discriminated), then a
table: step | pick | evidence (numbers + what the figure showed) | what to avoid and why. End
with a suggested chain and the note that it was never run as a combination. Keep it concise.

Then offer to turn the pick into a methods config — that is the **ist-run-config** skill (it
writes `configs/methods_*.yaml`, validates it and gives pull/run commands). Never submit cluster
jobs without explicit approval.
