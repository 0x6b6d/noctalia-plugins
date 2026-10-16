#!/usr/bin/env python3
"""Lightweight checks for a personal multi-plugin Noctalia source repo.

Inspired by community-plugins' validator, but only the basics useful for solo
maintenance — no store/website rules, no PR policy.

Adapted from https://github.com/OHMCFXG/noctalia-plugins (.github/scripts/validate_plugins.py)
"""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*$")
ENTRY_TYPES = (
    "widget",
    "panel",
    "shortcut",
    "desktop_widget",
    "launcher_provider",
    "service",
)
REQUIRED_ROOT = ("id", "name", "version", "plugin_api", "author")


class Findings:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)


def load_toml(path: Path) -> dict:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def plugin_dirs(root: Path) -> list[Path]:
    dirs = []
    for path in sorted(root.iterdir()):
        if path.is_dir() and not path.name.startswith(".") and (path / "plugin.toml").is_file():
            dirs.append(path)
    return dirs


def validate_plugin(plugin_dir: Path, findings: Findings) -> dict | None:
    rel = plugin_dir.name
    manifest_path = plugin_dir / "plugin.toml"
    try:
        manifest = load_toml(manifest_path)
    except Exception as exc:  # noqa: BLE001 — surface parse errors as findings
        findings.error(f"{rel}/plugin.toml: parse error: {exc}")
        return None

    for field in REQUIRED_ROOT:
        if field not in manifest:
            findings.error(f"{rel}/plugin.toml: missing `{field}`")

    plugin_id = manifest.get("id")
    if isinstance(plugin_id, str):
        if not ID_RE.match(plugin_id):
            findings.error(f"{rel}/plugin.toml: id must look like author/plugin (got {plugin_id!r})")
        else:
            suffix = plugin_id.split("/", 1)[1]
            if suffix != plugin_dir.name:
                findings.error(
                    f"{rel}/plugin.toml: id suffix {suffix!r} must match directory name {plugin_dir.name!r}"
                )
    else:
        findings.error(f"{rel}/plugin.toml: id must be a string")

    version = manifest.get("version")
    if isinstance(version, str) and not SEMVER_RE.match(version):
        findings.warn(f"{rel}/plugin.toml: version {version!r} is not semver X.Y.Z")

    plugin_api = manifest.get("plugin_api")
    if not isinstance(plugin_api, int) or isinstance(plugin_api, bool) or plugin_api <= 0:
        findings.error(f"{rel}/plugin.toml: plugin_api must be a positive integer")

    if not (plugin_dir / "README.md").is_file():
        findings.error(f"{rel}/: missing README.md")

    if not (plugin_dir / "thumbnail.webp").is_file():
        findings.warn(f"{rel}/: missing thumbnail.webp (optional for personal use)")

    # Entry files must exist
    has_entry = False
    for entry_type in ENTRY_TYPES:
        for entry in manifest.get(entry_type, []) or []:
            if not isinstance(entry, dict):
                continue
            has_entry = True
            entry_file = entry.get("entry")
            if not isinstance(entry_file, str) or not entry_file:
                findings.error(f"{rel}/plugin.toml: {entry_type} entry missing `entry` path")
                continue
            path = plugin_dir / entry_file
            if not path.is_file():
                findings.error(f"{rel}/plugin.toml: {entry_type} entry file missing: {entry_file}")

    if not has_entry:
        findings.warn(f"{rel}/plugin.toml: no entries declared")

    # Settings with label_key need translations/en.json
    settings = list(manifest.get("setting", []) or [])
    for entry_type in ENTRY_TYPES:
        for entry in manifest.get(entry_type, []) or []:
            if isinstance(entry, dict):
                settings.extend(entry.get("setting", []) or [])

    label_keys: list[str] = []
    for setting in settings:
        if not isinstance(setting, dict):
            continue
        for field in ("label_key", "description_key"):
            key = setting.get(field)
            if isinstance(key, str) and key:
                label_keys.append(key)
        for option in setting.get("options", []) or []:
            if isinstance(option, dict):
                key = option.get("label_key")
                if isinstance(key, str) and key:
                    label_keys.append(key)

    if label_keys:
        en_path = plugin_dir / "translations" / "en.json"
        if not en_path.is_file():
            findings.error(f"{rel}/: settings use label_key but translations/en.json is missing")
        else:
            try:
                import json

                raw = json.loads(en_path.read_text(encoding="utf-8"))
            except Exception as exc:  # noqa: BLE001
                findings.error(f"{rel}/translations/en.json: {exc}")
            else:
                flat: set[str] = set()

                def walk(node: object, prefix: str = "") -> None:
                    if isinstance(node, dict):
                        for k, v in node.items():
                            walk(v, f"{prefix}.{k}" if prefix else str(k))
                    elif isinstance(node, str) and prefix:
                        flat.add(prefix)

                walk(raw)
                for key in label_keys:
                    if key not in flat:
                        findings.error(f"{rel}/: translation key missing in en.json: {key}")

    return manifest


def validate_catalog(root: Path, manifests: list[dict], findings: Findings) -> None:
    catalog_path = root / "catalog.toml"
    if not catalog_path.is_file():
        findings.warn("catalog.toml missing (run update-catalog script)")
        return

    try:
        catalog = load_toml(catalog_path)
    except Exception as exc:  # noqa: BLE001
        findings.error(f"catalog.toml: parse error: {exc}")
        return

    rows = catalog.get("plugin", [])
    if not isinstance(rows, list):
        findings.error("catalog.toml: expected [[plugin]] array")
        return

    catalog_ids = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        pid = row.get("id")
        if isinstance(pid, str):
            catalog_ids.append(pid)

    manifest_ids = [m["id"] for m in manifests if isinstance(m.get("id"), str)]
    for pid in manifest_ids:
        if pid not in catalog_ids:
            findings.error(f"catalog.toml: missing plugin id {pid!r} (regenerate catalog)")
    for pid in catalog_ids:
        if pid not in manifest_ids:
            findings.warn(f"catalog.toml: stale plugin id {pid!r} (no matching directory)")


def main() -> int:
    findings = Findings()
    manifests: list[dict] = []

    dirs = plugin_dirs(ROOT)
    if not dirs:
        findings.error("no plugin directories with plugin.toml found")

    for plugin_dir in dirs:
        manifest = validate_plugin(plugin_dir, findings)
        if manifest is not None:
            manifests.append(manifest)

    validate_catalog(ROOT, manifests, findings)

    for msg in findings.warnings:
        print(f"warning: {msg}")
    for msg in findings.errors:
        print(f"error: {msg}", file=sys.stderr)

    print(f"checked {len(dirs)} plugin(s): {len(findings.errors)} error(s), {len(findings.warnings)} warning(s)")
    return 1 if findings.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())