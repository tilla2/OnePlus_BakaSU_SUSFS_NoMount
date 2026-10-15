# ChimeraKernel Repository Guidelines

This is the single rulebook for this repository. It applies to human maintainers, to interactive agent sessions, and to any automation that touches the tree. If a change alters how the repository behaves — a workflow, the build action, the config schema, the clean-up semantics, the sync procedure — this file is updated in the same pull request. A rule that is not written down here is not a rule; a behaviour that contradicts a rule here is a bug.

The rules are grouped by topic. Each section explains not only what to do but why, because most of these rules exist to stop a specific failure that has already happened once.

---

## 1. Naming: A for Android, everywhere

The repository names every OS generation after the Android version it ships with. Config and manifest trees are `configs/a14`, `configs/a15`, `configs/a16` and `manifests/a14`, `manifests/a15`, `manifests/a16`. Inside every config the `os_version` value is `"A14"`, `"A15"` or `"A16"`. The build dispatch menus follow the same pattern: the tree selector offers `A14+A15+A16`, `A15+A16`, `A14+A15`, `A16`, `A15` and `A14`, and the per-tree device menus are `device_a14`, `device_a15` and `device_a16`. Derived names inherit the value automatically, so a build of OP15 on A16 produces `patch-status-OP15_A16` and `AK3_OP15_A16_…zip`.

The old `oos`/`OOS` convention is forbidden. It must not reappear in a directory name, a config value, a jq filter, a sort key, an input id, a help text or a script. The reason is practical: upstream WildKernels already uses `a14/a15/a16` and `A1x`, so matching it means upstream merges need no naming surgery at all, while any surviving `OOS` literal (for example a `gsub("OOS"; "")` sort key) silently breaks matrix generation the moment it meets an `A1x` value.

Mapping only ever travels from oos to a. Any tool, script or agent that encounters a leftover `oos1x` directory or an `"OOS1x"` value converts it to the `a1x`/`"A1x"` form; nothing in this repository is ever allowed to convert in the other direction. A script that contains an a→oos mapping is rejected on sight.

The phrase "Stock ROM (OOS/COS)" in the issue templates refers to the user's actual operating system, not to repository naming, and is intentionally kept. The user-facing release text still renders A16 as "OxygenOS 16"; that is display wording, not a naming convention.

## 2. Branding: ChimeraKernel root tag, unbranded uname

Every device config carries `"root_tag": "ChimeraKernel"`. The build action's root-tag step keys off this value, so every kernel banner reads `ChimeraKernel@<repository>`. Do not leave a config with an empty root tag and do not introduce a different tag.

The `uname` field carries no fork branding of any kind. It holds either the device's genuine stock kernel suffix (for example `5-g16e473de48a3-abogki462654244-4k`), copied verbatim from a trustworthy source for the same SoC, the same kernel version and the same Android generation, or the empty string when no genuine suffix is known. Placeholders such as `OP-RESUKISU`, `OP-BAKASU`, `OP-WILD`, `OP-KSUN` or any other `OP-<WORD>` value are branding, not data, and are never valid. Never invent a plausible-looking build suffix: an empty uname is honest, a fake one is not. When `uname` is empty the build action appends no branding suffix at all and the local version becomes just `-<android_version>`; non-empty values are capped at 44 characters.

Genuine suffixes are OS-specific build strings. An A16 suffix is never reused for an A15 or A14 config of the same device. Known-good suffixes are recorded in `scripts/sync/stock_unames.json`, which the sanitizer uses to restore a genuine suffix if an upstream merge reintroduces a placeholder. When a config gains a genuine uname, refresh that table with `python3 scripts/sync/sanitize.py --refresh-uname-table` in the same commit.

## 3. Config schema

The reference config is the OP15 config on A16. Every device config uses its key set and its key order:

`model, soc, branch, manifest, android_version, kernel_version, os_version, lto, zyc_compiler, c_compiler, rust_compiler, bindgen, rust_build, disk_cleanup, hmbird, susfs, opt, ds, bbg, bbr, bbr3, bore, lz4_upgrade, zstd_upgrade, rtmutex_cve, adios, ttl, ip_set, unicode, ntsync, root_tag, blacklist_modules, uname, build_time`

Files are formatted with a two-space indent, UTF-8 without escaping, and a trailing newline. There are no stray keys. Every config validates with `jq -e`.

The default-on rule governs optional keys. A key that the build action treats as "apply always when omitted" stays omitted unless a normalization has a concrete, documented reason to write it, and in that case the written value must equal exactly what the action would have done for that device. `zstd_upgrade` and `rtmutex_cve` are the current example: the action defaults both to `true` when the key is absent and gates the actual steps to 6.12 kernels internally, so every config carries the literal `true`, which changes nothing at build time. Feature flags are never flipped as a side effect of renaming, reformatting or "making things consistent".

Consistency with the OP15 reference means schema, formatting and branding — never behaviour. The following values are per-config and must not be harmonised:

- `lto` is chosen per device. OP15's `"none"` is intentional and is not copied anywhere; no LTO value is "fixed" during maintenance.
- `build_time` exists only where a reproducible timestamp is genuinely needed. It is never fabricated for other configs; the workflow's `build_timestamp` dispatch input (empty means "now") governs everywhere else.
- `blacklist_modules` reflects real hardware. OP15's list is the reference for the OP15 family only. There are no global additions and no global removals. `qcom_iommu_debug` is present on the configs that need it and absent from the OP15 family. The Dimensity 9000 (MediaTek) configs deliberately lack `oplus_security_guard`, `oplus_secure_harden` and `oplus_security_keventupload`, because that trio is Qualcomm-only. These gaps are preserved and are never "filled in". Lists contain no empty items.

Every config owns its own artifact namespace. The build derives `PS_BASE` from model and OS version, so `model` plus `os_version` must be unique across the tree: two configs may share a manifest and every flag (Myron and OP15 do), but they may never share `PS_BASE`, because patch-status artifacts, AK3 zips and debug bundles would overwrite each other.

## 4. Patch policy: gen_patch or nothing

Kernel patches reach the tree exclusively through the gen_patch harness defined in the "Prepare patch generation harness" step of the build action. A patch is staged in a sandbox copy of the affected files, regenerated there with `diff -ruN`, and only the regenerated diff is applied to the real tree, at `--fuzz=0`. Fuzz is allowed only inside the sandbox staging; the real tree is never patched with fuzz. Never add direct `patch -p1` calls against the tree and never commit persistent manual patch files to work around a failing hunk.

Optional patches fail soft: on failure the harness warns, writes `key|failed` to the patch-status file, keeps forensics under `patch-faillogs/`, and the build continues. Do not turn optional patches into `exit 1` aborts. SUSFS is the exception and keeps its fatal-on-total-failure behaviour. The patch-hygiene workflow exists to exercise exactly this machinery and must stay in sync with the build workflow's menus.

The following build-action content is fork policy and must survive every upstream merge: the AnyKernel3 source is `https://github.com/huangdihd/AnyKernel3` (branch `gki-2.0`, also in the manifests); the BakaSU source is `https://github.com/Baka-SU/BakaSU`; the "Add USB DWC3 & OTG Support" step stays; upstream's KernelSU-Next ("KSUN"/"WildKSU") integration steps stay out of the build action; upstream's `normalized` artifact-naming scheme is not adopted in the build workflow; and the release notes keep the fork's MODEL column with clickable model links.

## 5. Workflow step discipline

Every `run:` step that is created or modified in a workflow or composite action ends with an explicit success marker of the form `echo "✅ …"`. A hard failure ends the step with `exit 1`, preceded by an `::error::` line that says what failed. Soft conditions use `::warning::` and continue. This makes every log scannable: a step either finished with a visible ✅ or it says why it did not.

When a workflow needs to check whether something is a release (for example a mirrored toolchain), it verifies a true release with `gh release view <tag>`; the existence of a tag alone proves nothing.

## 6. Permissions

`actions: write` is required in two places and must not be removed. The build workflow needs it to manage its rolling pins artifact (upload, then prune older copies) and to read workflow artifacts across runs. The clean-up workflow needs it to delete caches, workflow runs and artifacts, including the pins reset path. Every other workflow requests the least it needs; the sync-sanitize workflow, for instance, only needs `contents: read`, because it never pushes.

## 7. The rolling pins artifact

The build workflow remembers what last worked in a single rolling artifact named exactly `last-success-pins`, containing one file, `pins.json`. It is written by the `record-last-successful-pins` job, and only when the set-op-model, resolve-nomount and build jobs all succeeded on a non-dry-run build — a failed, cancelled or patch-dry-run build never touches it. Each write merges with the previous store, uploads a fresh copy with 90-day retention, and prunes every older `last-success-pins` copy, so exactly one live artifact exists at any time. There is no git branch, no history and no commit involved.

The store records the run that produced it, the root manager type and commit, the NoMount commit, and the SUSFS commit per GKI/KMI, keyed by GMKI strings such as `android15-6.6` and `android16-6.12`. SUSFS pins for GMKIs that were not part of the latest successful run survive the merge. The "same as last successful run" dispatch toggles read this store and fail loudly when it does not exist yet.

The pins artifact is infrastructure, not garbage. Every clean-up path treats `last-success-pins` as exempt by default. The only supported way to remove it is a clean-up run with `pin_policy: delete_pin` (together with `artifact_cleanup: true`); that is a reset, not a disable — the next successful build re-creates the store from scratch. The pins logic itself, the ccache "download once" mechanism (the `prepare_ccache` job, its `ccache-binary` artifact, and the build job's download plus apt fallback), the toolchain mirroring workflow and the kernel-source-sync internals are not modified as part of unrelated work.

## 8. Trigger-agnostic behaviour

A build behaves the same whatever started it: manual dispatch, a scheduled run, an API call or an agent. Behaviour is decided by inputs and config values, never by the event type. The root manager APKs are the clearest example: on every build, release or not, the workflow resolves the manager app that matches the exact root-manager commit that was built (falling back to the latest upstream release with a warning), and publishes each APK as a loose file — one unzipped artifact per APK (`archive: false`) on non-release runs, and as plain release assets on release runs. APKs are never bundled into a zip.

## 9. Menu maintenance

The device menus in the dispatch inputs of the build and patch-hygiene workflows are static choice lists, maintained by hand with one config name per line. Every config that is added, renamed or removed is reflected in the matching menu in the same commit: an A16 config goes under `device_a16`, and so on, placed next to its family (Myron sits beside the OP15 family). The tree selector options and the os-version filters in both workflows are kept identical. A config that exists but is missing from its menu is a bug, as is a menu entry with no config behind it.

## 10. Git protocol

The default branch, `The-Big-One`, is protected and is only ever changed by the maintainer merging a pull request. Nobody and nothing pushes to it directly. Every task or migration uses a single working branch and lands as one pull request, so that the whole change can be reviewed in one place and reverted with a single `git revert` of the merge. A multi-step migration never leaves the branch head half-migrated: if a rename touches configs, workflows and the build action, all of it lands in the same pull request. Commits are logical, one per phase or concern, with descriptive messages. Workflows never push and never open pull requests on their own.

## 11. Credits

Credits are sacred. Every developer and module credit in the README and in the compatibility notes stays when the repository is renamed, rebranded or reorganised — Nostalgic/RealS3S, maxsteeel, huangdihd, fatalcoder524, TheWildJames, Bouteillepleine, cctv18, danmagisk and everyone else listed there. Renaming touches conventions, never attribution.

The repository has no Telegram channel of its own and contains no Telegram bot plumbing, no Telegram secrets and no announcement workflows. The only `t.me` links allowed to exist are third-party credits and community references:

- `t.me/RealS3S`, `t.me/maxsteeel`, `t.me/huangdihd` — contributor credits in the README;
- `t.me/danmgk` — module credit badge in the README;
- `t.me/huangdihd_wildkernel` — the upstream WildKernels community group, referenced in the compatibility notes and in the sync section below.

## 12. Documentation

Documentation describes behaviour; it does not link to repository-local files that the GitHub UI already exposes. Mentioning a path in code formatting is fine, linking to it is not. The README does not link this rulebook. Stale documents inherited from older lineages are deleted rather than kept around, and the repository has no GitHub Pages site or download page.

## 13. Upstream sync protocol

Upstream is `WildKernels/OnePlus_KernelSU_SUSFS`, branch `main`. Synchronisation is done interactively by the maintainer (or an agent session acting for the maintainer) on a working branch; there is no sync bot and nothing in GitHub Actions calls an external AI service. The procedure is:

1. Create a working branch from `The-Big-One` and merge upstream `main` into it, resolving conflicts in favour of the fork policies in this file.
2. Run the "Sync Sanitize" workflow on that branch (dry run first). It executes `scripts/sync/sanitize.py`, which converts any leftover oos naming to a naming, replaces branded unames with the genuine suffix from `scripts/sync/stock_unames.json` (or empty), forces the ChimeraKernel root tag, points AnyKernel3 at huangdihd @ `gki-2.0` in the manifests and the build action, removes upstream's KernelSU-Next steps, and deletes upstream's kernel-monitor workflow. The same script can be run locally with or without `--dry-run`.
3. Apply the reported changes (rerun locally without `--dry-run`, or apply the published diff), update the device menus for any new configs, and commit.
4. Open one pull request into `The-Big-One`. A dry run on the result should report "no changes needed".

The sync-sanitize workflow never pushes and never opens pull requests; it only reports and publishes its report and diff as artifacts. Questions about upstream behaviour go to the WildKernels community at `t.me/huangdihd_wildkernel`.

## 14. Clean-up policy

The clean-up workflow is dry-run-first and opt-in destructive. Every default is non-destructive: nothing is deleted unless the operator explicitly asks for it, and a dry run previews everything, artifacts included. Before a real clean-up, run `analyze_only` or a dry run and read the ordered preview.

Caches are collected first and deleted afterwards, never inline while listing. A cache is a candidate when it matches the device filter, the cache pattern, the age gate and the minimum size floor (`min_cache_size_mb`). The newest `keep_count` caches per device are then protected, the remainder is ordered by `delete_order` (oldest first by default, newest first, or largest first), and `delete_count` caps how many are deleted.

Workflow runs are filtered by `workflow_filter` and `status_filter` (all, failed only, or unsuccessful only — failure, cancelled and skipped). `days_to_keep: 0` means no age gate at all, so everything that passes the filters is eligible; any positive value keeps runs younger than that many days. The newest `keep_last_successful` successful runs of each workflow are protected regardless of age, which makes "delete everything except the last three successful runs" a single invocation: `days_to_keep=0, keep_last_successful=3`.

Artifact clean-up is off unless `artifact_cleanup` is true; it deletes artifacts older than `artifact_days_to_keep` (`0` = no age gate). The `last-success-pins` artifact is exempt from every clean-up path unless `pin_policy` is `delete_pin`, which is the supported pin reset described in section 7: with `delete_pin` the pins artifact is removed regardless of its age. Because deleting a run also deletes its artifacts, the run that owns the live pins artifact is protected from run deletion under `keep_pin`. Runs that are still queued or in progress, the clean-up run itself, and artifacts belonging to active runs are never touched.

All selection logic lives in one planner shared by the analyze preview and the deleting jobs, so the preview and the real run always agree.

---

When in doubt, prefer the change that keeps existing safety mechanisms intact, keeps behaviour identical, and leaves the decision to the maintainer.
