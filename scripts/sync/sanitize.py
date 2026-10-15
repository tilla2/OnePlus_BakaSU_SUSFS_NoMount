#!/usr/bin/env python3
"""Post-merge fork sanitizer for the ChimeraKernel repository.

Run after merging upstream WildKernels/OnePlus_KernelSU_SUSFS (branch ``main``).
The script is standalone and idempotent; a second run on a clean tree reports
"no changes needed".

Naming direction is strictly one-way: oos -> a.  Leftover ``oos1x`` trees become
``a1x`` and ``"os_version": "OOS1x"`` becomes ``"A1x"``.  Nothing in this file
ever maps a -> oos.

Fork transforms applied:
  1. configs/ and manifests/: ``oos1x`` directories -> ``a1x`` (merge-safe).
  2. configs: ``os_version`` OOS1x -> A1x.
  3. configs: fork/upstream-branded ``uname`` placeholders (any
     ``OP-<WORD>`` value, e.g. OP-BAKASU, OP-WILD, OP-KSUN) are replaced by the
     device's genuine stock suffix from ``scripts/sync/stock_unames.json``,
     or by an empty string when no genuine suffix is known.
  4. configs: ``root_tag`` is forced to ``ChimeraKernel``.
  5. manifests: AnyKernel3 is fetched from huangdihd/AnyKernel3 @ gki-2.0.
  6. build-kernel action: AnyKernel3 URL -> huangdihd, KernelSU-Next "Add
     KernelSU-Next"/"Add KSUN" steps removed (upstream-only steps).
  7. The upstream kernel-monitor workflow is deleted.

Usage:
  python3 scripts/sync/sanitize.py [--dry-run] [--root DIR]
                                   [--report FILE] [--diff FILE]
  python3 scripts/sync/sanitize.py --refresh-uname-table

Exit code 0 on success (changes or not), 1 on any error.
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT_TAG = "ChimeraKernel"
OS_TREES = ("14", "15", "16")
TREE_BASES = ("configs", "manifests")
ACTION_PATH = ".github/actions/build-kernel/action.yml"
MONITOR_WORKFLOW = ".github/workflows/oplus-kernel-monitor.yml"
UNAME_TABLE = "scripts/sync/stock_unames.json"

# A genuine stock suffix starts with a digit (e.g. "8-g97a9aaefab9a-ab14519050-4k").
# Any "OP-<WORD>" value is a branding placeholder, never data.
# Any OP-<WORD> uname is a brand placeholder (OP-BAKASU, OP-WILD, OP-KSUN, the retired fork brand, ...).
BRANDED_UNAME = re.compile(r"^OP-[A-Za-z0-9]+$")

RE_OS_VERSION = re.compile(r'("os_version"\s*:\s*")OOS(1[0-9])(")')
RE_UNAME = re.compile(r'("uname"\s*:\s*")([^"]*)(")')
RE_ROOT_TAG = re.compile(r'("root_tag"\s*:\s*")([^"]*)(")')

MANIFEST_RULES = (
    (re.compile(r"github\.com/WildKernels/AnyKernel3"), "github.com/huangdihd/AnyKernel3"),
    (re.compile(r'fetch="https://github\.com/WildKernels" name="wild"'),
     'fetch="https://github.com/huangdihd" name="wild"'),
    (re.compile(r'(name="AnyKernel3".*revision=")[^"]+(")'), r"\g<1>gki-2.0\g<2>"),
)


class Sanitizer:
    def __init__(self, root: Path, dry_run: bool):
        self.root = root
        self.dry_run = dry_run
        self.log: list[str] = []
        self.diffs: list[str] = []
        self.counts = {
            "paths_renamed": 0,
            "configs_rewritten": 0,
            "os_versions_changed": 0,
            "unames_stripped": 0,
            "root_tags_set": 0,
            "manifests_rewritten": 0,
            "action_rewritten": 0,
            "files_deleted": 0,
        }
        self.uname_table = self._load_uname_table()

    # ---------- helpers ----------
    def _load_uname_table(self) -> dict[str, str]:
        path = self.root / UNAME_TABLE
        if not path.is_file():
            return {}
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError(f"{UNAME_TABLE} must be a JSON object")
        return {k: v for k, v in data.items() if isinstance(v, str)}

    def _rel(self, p: Path) -> str:
        return p.relative_to(self.root).as_posix()

    def _write(self, path: Path, old: str, new: str) -> None:
        rel = self._rel(path)
        self.diffs.extend(difflib.unified_diff(
            old.splitlines(keepends=True), new.splitlines(keepends=True),
            fromfile=f"a/{rel}", tofile=f"b/{rel}"))
        if not self.dry_run:
            path.write_text(new, encoding="utf-8")

    # ---------- 1. oos -> a tree rename ----------
    def rename_trees(self) -> None:
        for ver in OS_TREES:
            for base in TREE_BASES:
                oos_dir = self.root / base / f"oos{ver}"
                a_dir = self.root / base / f"a{ver}"
                if not oos_dir.is_dir():
                    continue
                if not a_dir.is_dir():
                    self.log.append(f"RENAME  {self._rel(oos_dir)} -> {self._rel(a_dir)}")
                    self.counts["paths_renamed"] += 1
                    if not self.dry_run:
                        os.rename(oos_dir, a_dir)
                    continue
                # Both exist: the a* tree is canonical; move only files it lacks.
                for src in sorted(oos_dir.rglob("*")):
                    if not src.is_file():
                        continue
                    dst = a_dir / src.relative_to(oos_dir)
                    if dst.exists():
                        self.log.append(f"DROP    {self._rel(src)} (a-tree copy {self._rel(dst)} wins)")
                    else:
                        self.log.append(f"MOVE    {self._rel(src)} -> {self._rel(dst)}")
                        self.counts["paths_renamed"] += 1
                        if not self.dry_run:
                            dst.parent.mkdir(parents=True, exist_ok=True)
                            shutil.move(str(src), str(dst))
                self.log.append(f"REMOVE  {self._rel(oos_dir)} (merged into {self._rel(a_dir)})")
                self.counts["paths_renamed"] += 1
                if not self.dry_run:
                    shutil.rmtree(oos_dir)

    # ---------- 2-4. config JSONs ----------
    def sanitize_configs(self) -> None:
        cfg_root = self.root / "configs"
        if not cfg_root.is_dir():
            return
        # In dry-run the oos dirs were not renamed on disk: scan everything and
        # key the uname table by the post-rename (a*) path.
        for path in sorted(cfg_root.rglob("*.json")):
            rel_cfg = path.relative_to(cfg_root).as_posix()
            key = re.sub(r"^oos(1[0-9])/", r"a\1/", rel_cfg)
            old = path.read_text(encoding="utf-8")
            json.loads(old)  # hard fail on invalid JSON before touching it
            new = old
            changes: list[str] = []

            def os_sub(m: re.Match) -> str:
                changes.append(f"os_version OOS{m.group(2)} -> A{m.group(2)}")
                self.counts["os_versions_changed"] += 1
                return f"{m.group(1)}A{m.group(2)}{m.group(3)}"
            new = RE_OS_VERSION.sub(os_sub, new)

            def uname_sub(m: re.Match) -> str:
                val = m.group(2)
                if not BRANDED_UNAME.match(val):
                    return m.group(0)
                stock = self.uname_table.get(key, "")
                if BRANDED_UNAME.match(stock):
                    stock = ""
                changes.append(f"uname {val!r} -> {stock!r}" + ("" if stock else " (no genuine suffix known)"))
                self.counts["unames_stripped"] += 1
                return f"{m.group(1)}{stock}{m.group(3)}"
            new = RE_UNAME.sub(uname_sub, new)

            def tag_sub(m: re.Match) -> str:
                if m.group(2) == ROOT_TAG:
                    return m.group(0)
                changes.append(f"root_tag {m.group(2)!r} -> {ROOT_TAG!r}")
                self.counts["root_tags_set"] += 1
                return f"{m.group(1)}{ROOT_TAG}{m.group(3)}"
            new = RE_ROOT_TAG.sub(tag_sub, new)

            if new != old:
                json.loads(new)  # never emit broken JSON
                self.counts["configs_rewritten"] += 1
                self.log.append(f"CONFIG  configs/{rel_cfg}: " + "; ".join(changes))
                self._write(path, old, new)

    # ---------- 5. manifests ----------
    def sanitize_manifests(self) -> None:
        man_root = self.root / "manifests"
        if not man_root.is_dir():
            return
        for path in sorted(man_root.rglob("*.xml")):
            old = path.read_text(encoding="utf-8")
            new = old
            for rx, repl in MANIFEST_RULES:
                new = rx.sub(repl, new)
            if new != old:
                self.counts["manifests_rewritten"] += 1
                self.log.append(f"MANIFEST {self._rel(path)}: AnyKernel3 -> huangdihd @ gki-2.0")
                self._write(path, old, new)

    # ---------- 6. build-kernel action ----------
    def sanitize_action(self) -> None:
        path = self.root / ACTION_PATH
        if not path.is_file():
            return
        old = path.read_text(encoding="utf-8")
        new = old.replace("https://github.com/WildKernels/AnyKernel3", "https://github.com/huangdihd/AnyKernel3")
        out: list[str] = []
        skip = False
        removed: list[str] = []
        for line in new.splitlines(keepends=True):
            if "- name: Add KernelSU-Next" in line or "- name: Add KSUN" in line:
                skip = True
                removed.append(line.strip())
            elif skip and line.startswith("    - name:"):
                skip = False
            if not skip:
                out.append(line)
        new = "".join(out)
        if new != old:
            self.counts["action_rewritten"] += 1
            detail = f"removed steps: {removed}" if removed else "AnyKernel3 URL -> huangdihd"
            self.log.append(f"ACTION  {ACTION_PATH}: {detail}")
            self._write(path, old, new)

    # ---------- 7. kernel monitor ----------
    def delete_monitor(self) -> None:
        path = self.root / MONITOR_WORKFLOW
        if path.exists():
            self.counts["files_deleted"] += 1
            self.log.append(f"DELETE  {MONITOR_WORKFLOW}")
            if not self.dry_run:
                path.unlink()

    def run(self) -> None:
        self.rename_trees()
        self.sanitize_configs()
        self.sanitize_manifests()
        self.sanitize_action()
        self.delete_monitor()

    def report(self) -> str:
        mode = "DRY-RUN (nothing written)" if self.dry_run else "APPLY"
        total = len(self.log)  # one entry per touched file/path; counters can overlap
        lines = [
            "ChimeraKernel sync sanitizer report",
            f"Mode: {mode}",
            "Direction: oos -> a only",
            "",
            "Counts:",
        ]
        lines += [f"  {k:<22} {v}" for k, v in self.counts.items()]
        lines.append("")
        if total == 0:
            lines.append("No changes needed — tree is already sanitized (A-naming, unbranded unames, fork transforms in place).")
        else:
            lines.append(f"{total} change(s) {'would be' if self.dry_run else 'were'} made:")
            lines += [f"  {entry}" for entry in self.log]
        return "\n".join(lines) + "\n"


def refresh_uname_table(root: Path) -> int:
    """Rebuild stock_unames.json from every genuine (non-branded, non-empty) uname in configs/a*/."""
    table: dict[str, str] = {}
    for path in sorted((root / "configs").glob("a1[0-9]/*.json")):
        uname = json.loads(path.read_text(encoding="utf-8")).get("uname", "")
        if uname and not BRANDED_UNAME.match(uname):
            table[path.relative_to(root / "configs").as_posix()] = uname
    (root / UNAME_TABLE).write_text(json.dumps(table, indent=2) + "\n", encoding="utf-8")
    print(f"✅ {UNAME_TABLE} refreshed with {len(table)} genuine stock suffix(es)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="ChimeraKernel post-merge sanitizer (oos -> a only)")
    ap.add_argument("--dry-run", action="store_true", help="report what would change; write nothing to the tree")
    ap.add_argument("--root", default=".", help="repository root (default: current directory)")
    ap.add_argument("--report", default="sanitize-report.txt", help="report file (default: sanitize-report.txt)")
    ap.add_argument("--diff", default="sanitize-changes.diff", help="unified diff of content changes (written only when non-empty)")
    ap.add_argument("--refresh-uname-table", action="store_true", help=f"rebuild {UNAME_TABLE} from the current configs and exit")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not (root / "configs").is_dir():
        print(f"::error::{root} does not look like the repository root (configs/ missing)", file=sys.stderr)
        return 1
    if args.refresh_uname_table:
        return refresh_uname_table(root)

    try:
        s = Sanitizer(root, args.dry_run)
        s.run()
    except Exception as exc:  # noqa: BLE001 - surface any failure as a hard error
        print(f"::error::sanitizer failed: {exc}", file=sys.stderr)
        return 1

    text = s.report()
    print(text, end="")
    Path(args.report).write_text(text, encoding="utf-8")
    diff_path = Path(args.diff)
    if s.diffs:
        diff_path.write_text("".join(s.diffs), encoding="utf-8")
    elif diff_path.exists():
        diff_path.unlink()
    # Machine-readable counts for the workflow summary.
    Path(args.report).with_suffix(".json").write_text(json.dumps({**s.counts, "change_entries": len(s.log)}, indent=2) + "\n", encoding="utf-8")
    print("✅ Sanitizer finished")
    return 0


if __name__ == "__main__":
    sys.exit(main())
