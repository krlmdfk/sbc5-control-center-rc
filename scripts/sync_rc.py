#!/usr/bin/env python3
"""Build a guarded Home Assistant RC App and companion HACS tree.

Input: ./_source is a checked-out snapshot of the candidate App repository.
Only writes to the current RC distribution repository.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "_source"
CONFIG = json.loads((ROOT / ".rc-source.json").read_text(encoding="utf-8"))
VERSION = CONFIG["version"]
assert re.fullmatch(r"\d+\.\d+\.\d+-rc[1-9]\d*", VERSION), VERSION
APP_SOURCE = SOURCE / "local_apps" / "sbc5_control_center"
APP_DEST = ROOT / "sbc5_control_center_rc"
HACS_SOURCE = SOURCE / "custom_components" / "sbc5_control_center"
HACS_DEST = ROOT / "custom_components" / "sbc5_control_center"

def replace_one(content: str, a: str, b: str, label: str) -> str:
    assert content.count(a) == 1, f"{label}: expected one exact match, got {content.count(a)}"
    return content.replace(a, b, 1)

# The source release metadata is generated in a temporary checkout. Do not
# change or merge the Stable repository just to build this release candidate.
manifest = SOURCE / "update-manifest.json"
data = json.loads(manifest.read_text(encoding="utf-8"))
data["files"]["local_apps/sbc5_control_center/zip_security_preflight.py"] = "0" * 64
manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
subprocess.run(
    ["python", "scripts/release_prepare.py",
     "--version", VERSION, "--release-date", CONFIG["release_date"],
     "--restart-required", "home_assistant",
     "--summary-en", "Test channel with AI and security hardening",
     "--summary-pl", "Kanał testowy: zabezpieczenia AI i aktualizacji"],
    cwd=SOURCE, check=True,
)

# Source of truth for the HACS companion is the canonical component from
# the exact versioned RC App source. Do not use the unrelated Stable manifest.
if APP_DEST.exists():
    shutil.rmtree(APP_DEST)
shutil.copytree(APP_SOURCE, APP_DEST, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
if HACS_DEST.exists():
    shutil.rmtree(HACS_DEST)
shutil.copytree(HACS_SOURCE, HACS_DEST, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))

cfg = APP_DEST / "config.yaml"
text = cfg.read_text(encoding="utf-8")
text = replace_one(text, "name: SBC5 Control Center\n",
                   "name: SBC5 Control Center RC\n", "App name")
text = replace_one(text, "slug: sbc5_control_center\n",
                   "slug: sbc5_control_center_rc\n", "App slug")
text = replace_one(text, "stage: stable\n", "stage: experimental\n", "stage")
text = replace_one(text, "boot: auto\n", "boot: manual\n", "boot")
text = replace_one(text, "options:\n", "options:\n  rc_exclusive_ack: false\n", "App options")
text = replace_one(text, "schema:\n", "schema:\n  rc_exclusive_ack: bool\n", "App schema")
text = replace_one(text, "  local_package_updates_enabled: true\n",
                   "  local_package_updates_enabled: false\n", "disable in-App package update")
text = replace_one(text, "  update_check_enabled: true\n",
                   "  update_check_enabled: false\n", "disable stable update checker")
text = replace_one(
    text,
    "app_update_manifest_url: https://raw.githubusercontent.com/krlmdfk/sbc5-control-center/main/local_apps/sbc5_control_center/release.json",
    "app_update_manifest_url: https://raw.githubusercontent.com/krlmdfk/sbc5-control-center-rc/main/sbc5_control_center_rc/release.json",
    "RC version source",
)
cfg.write_text(text, encoding="utf-8")

# RC's gate runs BEFORE all host access, AI workers or fan actuator setup.
docker = APP_DEST / "Dockerfile"
text = docker.read_text(encoding="utf-8")
text = replace_one(text, "COPY run.sh /\n",
                   "COPY run.sh /\nCOPY rc_exclusive_guard.sh /rc_exclusive_guard.sh\n", "Dockerfile copy")
text = replace_one(text, 'ENTRYPOINT ["/run.sh"]',
                   'RUN chmod a+x /rc_exclusive_guard.sh\nENTRYPOINT ["/rc_exclusive_guard.sh"]', "entrypoint")
docker.write_text(text, encoding="utf-8")
shutil.copy2(ROOT / "scripts/rc_exclusive_guard.sh", APP_DEST / "rc_exclusive_guard.sh")

# run.sh's image-version markers must match RC, independently of the
# runtime image patch for run_legacy.sh.
run = APP_DEST / "run.sh"
text = run.read_text(encoding="utf-8")
text = replace_one(text, 'APP_VERSION="3.2.0"', f'APP_VERSION="{VERSION}"', "run.sh")
text = replace_one(text, 'REQUIRED_PACKAGE_VERSION="3.2.0"',
                   f'REQUIRED_PACKAGE_VERSION="{VERSION}"', "package version")
run.write_text(text, encoding="utf-8")

# The HACS integration continues to have the original domain. The same code
# and config flow are used; it cannot coexist with the Stable integration.
integration = json.loads((HACS_DEST / "manifest.json").read_text(encoding="utf-8"))
assert integration["version"] == VERSION
assert integration["domain"] == "sbc5_control_center"
assert (APP_DEST / "bridge" / "__init__.py").read_bytes() == (HACS_DEST / "__init__.py").read_bytes()

assert (ROOT / "scripts/rc_exclusive_guard.sh").read_bytes() == (APP_DEST / "rc_exclusive_guard.sh").read_bytes()
assert 'ENTRYPOINT ["/rc_exclusive_guard.sh"]' in docker.read_text(encoding="utf-8")
print(f"SBC5 RC distribution staged: App + HACS {VERSION}")
