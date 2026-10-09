#!/usr/bin/env python3
"""Per-variant benchmark metrics for one or more txsim datasets, with control checks.

    python3 -I .claude/skills/ist-method-recommendation/metrics_table.py <pattern> [<pattern> ...]
        [--run <run_id>] [--root <txsim_analysis dir>]

<pattern> is a regex matched against `dataset` (e.g. `2023_10x_human_lung_cancer_xenium`) or
against the tissue / disease / technology columns of datasets_overview.csv (e.g. `lung.*cancer`,
so all lung cancer datasets are pulled at once). The run defaults to the newest
<run>_similarity_metrics.csv in master_run/.

Prints, per dataset: the variant x metric table, which metrics the permuted-annotation control
does NOT beat (only those discriminate), per-stage ranks on those metrics, and the report /
figure paths. With several datasets, also a mean rank per method across datasets. Read-only.
"""
import argparse
import re
import sys
from pathlib import Path

import pandas as pd

ROOTS = [
    "/lustre/groups/luckylab/workspace/daria.romanovskaia/txsim_analysis",
    "/ictstr01/groups/luckylab/workspace/daria.romanovskaia/txsim_analysis",
]
SIM = ["coexpr_similarity", "coexpr_similarity_celltype", "knn_mixing", "neg_marker_purity_cells",
       "neg_marker_purity_reads", "rel_pairwise_ct_expr_sim", "rel_pairwise_gene_expr_sim"]
QUAL = ["number_of_cells", "proportion_of_annotated_cells", "proportion_of_assigned_reads"]
PERMUTED = "control: permute_celltype_annotations"
STAGE = {"segm": "segmentation", "ta": "transcript_assignment", "cta": "celltype_annotation",
         "corr": "expression_correction", "cell_vol_alpha": "volume+normalization"}

pd.set_option("display.width", 250)
pd.set_option("display.max_columns", 40)
pd.set_option("display.max_colwidth", 50)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("patterns", nargs="+")
    ap.add_argument("--run")
    ap.add_argument("--root")
    a = ap.parse_args()

    root = Path(a.root) if a.root else next((Path(r) for r in ROOTS if Path(r).is_dir()), None)
    if root is None:
        sys.exit(f"ERROR: no txsim_analysis root found (tried {ROOTS})")
    mdir = root / "master_run"
    run = a.run or sorted(p.name[: -len("_similarity_metrics.csv")]
                          for p in mdir.glob("*_similarity_metrics.csv"))[-1]
    sim = pd.read_csv(mdir / f"{run}_similarity_metrics.csv")
    qual = pd.read_csv(mdir / f"{run}_quality_metrics.csv")
    df = sim[["dataset", "variant"] + [c for c in SIM if c in sim]].merge(
        qual[["dataset", "variant"] + [c for c in QUAL if c in qual]], on=["dataset", "variant"], how="outer")

    # Dataset selection: by id, or by the metadata columns in datasets_overview.csv.
    meta = pd.read_csv(root / "datasets_overview.csv") if (root / "datasets_overview.csv").is_file() else None
    rx = re.compile("|".join(f"(?:{p})" for p in a.patterns), re.I)
    ids = {d for d in df.dataset.unique() if rx.search(d)}
    if meta is not None:
        cols = [c for c in ("tissue", "disease_state", "disease_detail", "technology") if c in meta]
        hit = meta[cols].astype(str).agg(" ".join, axis=1).str.contains(rx)
        ids |= set(meta.loc[hit, "dataset_id"]) & set(df.dataset)
    if not ids:
        sys.exit(f"ERROR: no dataset in run {run} matches {a.patterns}")
    print(f"run {run}: {len(ids)} dataset(s)\n")

    ranks = []
    for ds in sorted(ids):
        t = df[df.dataset == ds].drop(columns="dataset").set_index("variant")
        print("=" * 100, f"\n{ds}")
        if meta is not None and ds in set(meta.dataset_id):
            m = meta.set_index("dataset_id").loc[ds]
            print("  ", " | ".join(str(m.get(c, "")) for c in ("technology", "tissue", "disease_detail", "sc_reference")))
        print(t.round(3).to_string())

        methods = t[~t.index.str.startswith("control")]
        good = []
        if PERMUTED in t.index:
            print("\nmetric vs permuted-label control (a metric only discriminates if the control scores below the methods):")
            for c in SIM:
                if c not in t:
                    continue
                ctl, best, med = t.loc[PERMUTED, c], methods[c].max(), methods[c].median()
                ok = ctl < med
                good += [c] if ok else []
                print(f"  {c:30s} control={ctl:.3f}  methods median={med:.3f} max={best:.3f}  "
                      f"{'DISCRIMINATES' if ok else 'not informative (control >= median)'}")
        else:
            print("\n(no permuted control for this dataset; all similarity metrics used, interpret with care)")
            good = [c for c in SIM if c in t]
        if not good:
            print("  -> no informative metric; rely on quality metrics and the report figures")
            continue

        # Per stage: rank the one-at-a-time variants on the informative metrics (1 = best).
        print(f"\nper-stage ranks on informative metrics {good} (1 = best; baseline method included):")
        for pre, stage in STAGE.items():
            s = methods[methods.index.str.startswith(pre + "=")]
            if len(s) < 2:
                continue
            r = s[good].rank(ascending=False).mean(axis=1).sort_values()
            out = pd.DataFrame({"mean_rank": r.round(2)}).join(s[[c for c in QUAL if c in s]].round(3))
            print(f"\n  [{stage}]\n" + "\n".join("    " + line for line in out.to_string().splitlines()))
            ranks += [{"dataset": ds, "stage": stage, "method": v.split("=", 1)[1], "rank": x}
                      for v, x in r.items()]

        rep = root / "dataset_reports" / f"{ds.replace('/', '_')}.html"
        figs = root / run / ds
        print(f"\nreport:  {rep if rep.is_file() else '(none: ' + rep.name + ')'}")
        if figs.is_dir():
            print(f"figures: {figs}/  ({', '.join(sorted(p.name for p in figs.iterdir() if p.is_file()))})")
        print()

    if len({r['dataset'] for r in ranks}) > 1:
        R = pd.DataFrame(ranks)
        print("=" * 100, "\nmean per-stage rank across datasets (lower = better; n = datasets with that variant):")
        agg = R.groupby(["stage", "method"])["rank"].agg(["mean", "count"]).round(2)
        for stage, g in agg.groupby(level=0):
            print(f"\n  [{stage}]\n" + "\n".join("    " + l for l in g.droplevel(0).sort_values("mean").to_string().splitlines()))


if __name__ == "__main__":
    main()
