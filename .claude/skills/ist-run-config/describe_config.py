#!/usr/bin/env python3
"""Describe what a methods_config will run: per step the method, its image (and whether it is
already pulled into IST_SIF_DIR), its hardware/resource labels and its arguments with defaults.

    python3 .claude/skills/ist-run-config/describe_config.py <methods_config.yaml>

Uses the same selection logic as scripts/hpc/list_images.py (defaults from
configs/default_methods.yaml, volume step only for normalize_by_volume). Exits non-zero on an
unknown step or a method that has no built component.
"""
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts/hpc"))
sys.path.insert(0, str(REPO_ROOT / "scripts"))
import list_images  # noqa: E402
import site_config  # noqa: E402

GPU_LABELS = {"gpu": "GPU (gpu_p, gpu:1)", "gpuhighmem": "GPU (gpu_p, gpu:1)", "gpuh100": "GPU H100 (gpu_p, gpu:h100:1)"}
TIME = {"lowtime": "1 h", "midtime": "4 h", "hightime": "8 h", "veryhightime": "24 h"}


def labels_of(cfg):
    for r in cfg.get("runners", []):
        if r.get("type") == "nextflow":
            return r.get("directives", {}).get("label") or []
    return []


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    methods_config = sys.argv[1]
    sif_dir = Path(site_config.load()["IST_SIF_DIR"])  # configs/site.yaml (env vars override)
    user_cfg = yaml.safe_load(open(methods_config)) or {}

    comps = list_images.selected_components(methods_config)
    missing = []
    for comp in comps:
        comp_dir = list_images.DEP_DIR / comp
        if not comp_dir.exists():
            sys.exit(f"ERROR: method {comp} has no built component (typo, or run scripts/build.sh)")
        cfg = yaml.safe_load(open(comp_dir / ".config.vsh.yaml"))
        labels = labels_of(cfg)
        uri = list_images.image_of(comp_dir)
        img = sif_dir / list_images.nextflow_image_name(uri)
        pulled = img.is_file() and img.stat().st_size > 0
        if not pulled:
            missing.append(uri)
        hw = next((GPU_LABELS[l] for l in labels if l in GPU_LABELS), "CPU")
        time = next((TIME[l] for l in labels if l in TIME), "?")
        step = next((s for s, ns in list_images.STEP_NAMESPACE.items() if comp.startswith(ns + "/")), "(always)")
        set_args = (user_cfg.get(step) or {}).get("args", {}) if isinstance(user_cfg.get(step), dict) else {}

        print(f"== {step}: {comp.split('/')[1]}")
        print(f"   hardware: {hw}; labels: {', '.join(labels)}; time limit: {time}")
        print(f"   image: {'pulled' if pulled else 'MISSING'}  ({uri})")
        for g in cfg.get("argument_groups", []):
            for a in g["arguments"]:
                if a.get("type") == "file" or a.get("direction", "input") != "input":
                    continue
                name = a["name"].lstrip("-")
                default = a.get("default", [None])
                default = default[0] if isinstance(default, list) and len(default) == 1 else default
                req = " REQUIRED" if a.get("required") and default is None else ""
                val = f" -> set to {set_args[name]!r}" if name in set_args else ""
                desc = (a.get("description") or "").strip().split("\n")[0][:80]
                print(f"   arg {name} ({a['type']}) default={default!r}{req}{val}  {desc}")
        unknown = set(set_args) - {g_a["name"].lstrip("-") for g in cfg.get("argument_groups", []) for g_a in g["arguments"]}
        if unknown:
            sys.exit(f"ERROR: unknown args for {comp}: {sorted(unknown)}")

    print(f"\n{len(comps) - len(missing)}/{len(comps)} images pulled in {sif_dir}")
    for uri in missing:
        print(f"   missing: {uri}")


if __name__ == "__main__":
    main()
