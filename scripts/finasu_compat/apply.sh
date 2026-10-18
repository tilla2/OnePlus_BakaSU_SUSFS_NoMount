#!/usr/bin/env bash
# FinaSU kernel-side SUSFS integration patch applier
#
# susfs4ksu's kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch for each
# GKI branch is generated against FinaSU's (new directory layout) kernel
# source and rewrites FinaSU from inline syscall hook mode to SUSFS manual
# hook mode (the patch is byte-identical across the five GKI branches).
#
# Files where FinaSU master has drifted from the patch baseline cannot take
# the upstream patch directly — step 1 excludes those files, step 2 applies
# this repo's susfs_drift_fixes.patch (re-adapted from a three-way merge of
# the post-patch shape of susfs4ksu after its sync with official KernelSU
# and FinaSU master, preserving FinaSU's own features: dynamic manager,
# avc_spoof, app_profile init, late-load, module preinit, KSU_GET_INFO_FLAG_*, etc.).
#
# Current drifted file set (upstream refactors between the 10_enable baseline
# 9a0fd7d3 and master 40c97e24):
#   kernel/Makefile                   (format target refactored into the FORMAT_FILES variable)
#   kernel/Kbuild                     (preinit runner depends on direct ksu_syscall_table calls;
#                                        in SUSFS manual-hook mode it is force-disabled via KSU_NO_PREINIT)
#   kernel/core/init.c                (late-load dual-branch skeleton + preinit)
#   kernel/feature/selinux_hide.c     (inline hook machinery fully replaced by SUSFS manual hooks)
#   kernel/feature/sucompat.c         (userspace_stack_buffer moved into util.h,
#                                        su_compat_handler registration, etc.)
#   kernel/include/ksu.h              (restore the ksu_late_loaded declaration wrongly removed
#                                        by 10_enable; master's late-load/get_info code still needs it)
#   kernel/runtime/boot_event.c       (input hook converted to a static key)
#   kernel/runtime/ksud_integration.c (preinit integration, userspace_stack_buffer removal,
#                                        ksu_handle_execveat_ksud signature kept in its old shape)
#   kernel/supercall/dispatch.c       (get_info gained late-load/preinit/PR flags)
#
# If any step fails because of upstream structural changes in FinaSU,
# susfs_drift_fixes.patch must be regenerated against the new master:
# check out the 10_enable baseline commit (the FinaSU commit matching the
# uapi/supercall.h version number), apply 10_enable + the old drift patch,
# three-way merge with master, and regenerate the diff for the drifted files.
#
# Usage: apply.sh [KSU_DIR] (default: KernelSU; expects the SUSFS4KSU env var
#        pointing to a susfs4ksu checkout cloned for the GKI branch)
set -euo pipefail

KSU_DIR="${1:-KernelSU}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT_PATCH="$SCRIPT_DIR/susfs_drift_fixes.patch"
UPSTREAM_PATCH="${SUSFS4KSU:-$PWD/susfs4ksu}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"

# Drifted files (exactly matching the coverage of susfs_drift_fixes.patch)
DRIFT_FILES=(
  kernel/Makefile
  kernel/Kbuild
  kernel/core/init.c
  kernel/feature/selinux_hide.c
  kernel/feature/sucompat.c
  kernel/include/ksu.h
  kernel/runtime/boot_event.c
  kernel/runtime/ksud_integration.c
  kernel/supercall/dispatch.c
)

[ -f "$UPSTREAM_PATCH" ] || { echo "::error::susfs4ksu KSU-side patch not found: $UPSTREAM_PATCH"; exit 1; }
[ -f "$DRIFT_PATCH" ] || { echo "::error::FinaSU drift-fixes patch not found: $DRIFT_PATCH"; exit 1; }
[ -d "$KSU_DIR/.git" ] || { echo "::error::$KSU_DIR is not a git checkout; cannot apply patches"; exit 1; }

EXCLUDES=()
for f in "${DRIFT_FILES[@]}"; do
  EXCLUDES+=(--exclude="$f")
done

echo "Step 1/2: applying susfs4ksu 10_enable_susfs_for_ksu.patch (excluding ${#DRIFT_FILES[@]} drifted files)..."
git -C "$KSU_DIR" apply "${EXCLUDES[@]}" "$UPSTREAM_PATCH"

echo "Step 2/2: applying FinaSU drift-fixes (re-adaptation of ${#DRIFT_FILES[@]} drifted files)..."
git -C "$KSU_DIR" apply "$DRIFT_PATCH"

# ---- Post-apply verification ----
fail() { echo "::error::$1"; exit 1; }

grep -q "config KSU_SUSFS" "$KSU_DIR/kernel/Kconfig" \
  || fail "Kconfig is missing the KSU_SUSFS config entry; the 10_enable patch was not applied correctly"
grep -q "susfs_init" "$KSU_DIR/kernel/core/init.c" \
  || fail "init.c is missing the susfs_init call; drift-fixes application incomplete"
grep -q "ksu_handle_sys_reboot" "$KSU_DIR/kernel/supercall/dispatch.c" \
  || fail "dispatch.c is missing ksu_handle_sys_reboot (SUSFS manual-hook entry point); drift-fixes application incomplete"
grep -q "ksu_selinux_hide_drop_backup_if_unused" "$KSU_DIR/kernel/feature/selinux_hide.c" \
  || fail "selinux_hide.c is missing the backup-release interface; drift-fixes application incomplete"
if grep -qE 'find_kernel_symbol_exact|patch_text' "$KSU_DIR/kernel/feature/selinux_hide.c"; then
  fail "selinux_hide.c still contains the inline hook machinery (resolver/patch_text); drift-fixes application incomplete"
fi
if grep -qE 'kernelsu-objs \+= hook/(lsm_hook|syscall_event_bridge|syscall_hook_manager|tp_marker)' "$KSU_DIR/kernel/Kbuild"; then
  fail "Kbuild still contains inline syscall hook objects; the 10_enable patch was not applied correctly"
fi
grep -q "DEFINE_STATIC_KEY_TRUE(ksu_su_compat_enabled)" "$KSU_DIR/kernel/feature/sucompat.c" \
  || fail "sucompat.c is missing the su_compat static-key conversion; drift-fixes application incomplete"
grep -q "## For susfs stuff ##" "$KSU_DIR/kernel/Makefile" \
  || fail "Makefile is missing the SUSFS version probe section; drift-fixes application incomplete"
grep -q 'ksu_preinit_init();' "$KSU_DIR/kernel/core/init.c" \
  || fail "init.c is missing the ksu_preinit_init call (FinaSU preinit feature lost)"
grep -q 'extern bool ksu_late_loaded;' "$KSU_DIR/kernel/include/ksu.h" \
  || fail "ksu.h is missing the ksu_late_loaded declaration (late-load/get_info code would fail to compile)"
grep -q 'ccflags-y += -DKSU_NO_PREINIT' "$KSU_DIR/kernel/Kbuild" \
  || fail "Kbuild is missing the forced KSU_NO_PREINIT disable (preinit depends on ksu_syscall_table and must be disabled in SUSFS mode)"
if grep -qE 'kernelsu-objs \+= preinit/' "$KSU_DIR/kernel/Kbuild"; then
  fail "Kbuild still compiles the preinit objects (their ksu_syscall_table reference would fail to link)"
fi

REJS=$(find "$KSU_DIR/kernel" -name '*.rej' 2>/dev/null | wc -l)
[ "$REJS" -eq 0 ] || fail "Found $REJS .rej conflict files"
if grep -rq '^<<<<<<< ' "$KSU_DIR/kernel" 2>/dev/null; then
  fail "Unresolved conflict markers present"
fi

echo "FinaSU SUSFS kernel-side integration patches applied"
