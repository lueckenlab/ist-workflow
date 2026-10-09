#!/usr/bin/env python3
"""Per-user site settings: where the Apptainer images and the downloaded models live.

Read from configs/site.yaml (git-ignored; copy configs/site.example.yaml), or the file in
$IST_SITE_CONFIG. Environment variables IST_SIF_DIR / IST_MODEL_CACHE override the file.
$VARS in the values (e.g. $USER) are expanded. configs/singularity.config reads the same file.

    eval "$(python3 scripts/site_config.py)"    # exports IST_SIF_DIR and IST_MODEL_CACHE

Exits 1 with a message if a setting is missing or points to /tmp or $HOME.
"""
import os
import shlex
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
KEYS = {"sif_dir": "IST_SIF_DIR", "model_cache": "IST_MODEL_CACHE"}


def site_file() -> Path:
    return Path(os.environ.get("IST_SITE_CONFIG") or REPO_ROOT / "configs/site.yaml")


def load() -> dict:
    """Return {env var name: path}; exits with a message on missing or unsuitable paths."""
    path = site_file()
    cfg = (yaml.safe_load(path.read_text()) or {}) if path.is_file() else {}
    out, errors = {}, []
    for key, env in KEYS.items():
        value = os.environ.get(env) or cfg.get(key)
        if not value:
            errors.append(f"'{key}' is not set in {path} (or {env} in the environment)")
            continue
        value = os.path.expandvars(str(value))
        if "<" in value or ">" in value:
            errors.append(f"{key} = {value}: replace the <placeholder> from site.example.yaml")
        if value == "/tmp" or value.startswith("/tmp/") or value.startswith(os.path.expanduser("~")):
            errors.append(f"{key} = {value}: use a Lustre workspace path, not /tmp or $HOME")
        out[env] = value
    if errors:
        msg = "\n".join(f"ERROR: {e}" for e in errors)
        if not path.is_file():
            msg += f"\nCreate it: cp configs/site.example.yaml {path} and fill in your paths."
        sys.exit(msg + "\nSee .claude/PIPELINE.md section 7.")
    return out


if __name__ == "__main__":
    for env, value in load().items():
        print(f"export {env}={shlex.quote(value)}")
