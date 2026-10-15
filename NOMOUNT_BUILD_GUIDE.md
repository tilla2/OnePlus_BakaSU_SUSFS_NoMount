# Complete Guide: Building OnePlus 13R Custom Kernel with BakaSU + NoMount

This comprehensive guide covers:
1. **Fetching OnePlus 13R kernel source** (`/get_oki` alternative)
2. **Applying NoMount patches** (dev branch integration)
3. **Automated build script** (kernel compilation)
4. **GitHub Actions CI/CD** (automated building & releasing)

---

## Table of Contents
- [Part 1: Fetching the Kernel](#part-1-fetching-the-kernel)
- [Part 2: Integrating NoMount Patches](#part-2-integrating-nomount-patches)
- [Part 3: Build Script](#part-3-automated-build-script)
- [Part 4: GitHub Actions Workflow](#part-4-github-actions-workflow)

---

## Part 1: Fetching the Kernel

### Background: `/get_oki` Command
The `/get_oki` command does not exist as an official OnePlus tool. Instead, use these official sources:

### Official Methods

#### Method A: OnePlus OSS GitHub (Recommended)
```bash
#!/bin/bash
# fetch_oneplus_kernel.sh

DEVICE="13R"
KERNEL_VERSION="6.1.118"
KERNEL_SOURCE_DIR="kernel_sources"

echo "🔍 Fetching OnePlus $DEVICE kernel source..."

# Create working directory
mkdir -p "$KERNEL_SOURCE_DIR"
cd "$KERNEL_SOURCE_DIR"

# Clone from official OnePlus OSS
echo "📥 Cloning OnePlus kernel repository..."
git clone https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550.git kernel_op13r

cd kernel_op13r

# List all branches to find the right one
echo ""
echo "Available branches:"
git branch -a | grep -i "a15\|android15\|15\|6.1"

# Checkout the correct branch
echo ""
echo "Attempting to checkout A15 branch..."
git checkout A15 2>/dev/null || \
git checkout android-15 2>/dev/null || \
git checkout oneplus13r-a15 2>/dev/null || \
echo "⚠️  Branch not found. Use 'git branch -a' to see available options and checkout manually."

# Verify kernel version
echo ""
echo "✅ Kernel Source Information:"
grep -E "^VERSION|^PATCHLEVEL|^SUBLEVEL" Makefile

echo ""
echo "✅ Kernel source ready at: $(pwd)"
echo "📍 Next: Apply NoMount patches"
```

#### Method B: OnePlus Official Portal
1. Visit: https://opensource.oneplus.com/
2. Search for "OnePlus 13R" or "OnePlus 12 Android 15"
3. Download the kernel source package
4. Extract: `tar -xzf <kernel-package>.tar.gz`

#### Method C: Fallback (If Official 13R Not Available)
```bash
# Use OnePlus 12 kernel as base (closest match)
git clone https://github.com/OnePlusOSS/android_kernel_oneplus_sm8650.git
cd android_kernel_oneplus_sm8650
git checkout android15  # or A15
```

### Verification
```bash
cd kernel_op13r
cat Makefile | grep -E "VERSION|PATCHLEVEL|SUBLEVEL"

# Should output something like:
# VERSION = 6
# PATCHLEVEL = 1
# SUBLEVEL = 118
```

---

## Part 2: Integrating NoMount Patches

### Step 1: Clone NoMount Repository
```bash
git clone --branch dev https://github.com/maxsteeel/nomount.git nomount_patch
cd nomount_patch
git log --oneline | head -5  # Verify dev branch commits
```

### Step 2: Identify Correct Patch
```bash
cd ../kernel_op13r

# NoMount provides patches for different kernel versions
# For kernel 6.1.118, use the 6.1 patch

# List available patches
ls ../nomount_patch/kernel/patches/
# Available: nomount_6.1_kernel_integration.patch, etc.

# Check kernel version again to confirm
head -3 Makefile
```

### Step 3: Apply NoMount Patch
```bash
cd kernel_op13r

# Apply the appropriate patch
echo "Applying NoMount patch for kernel 6.1..."
patch -p1 < ../nomount_patch/kernel/patches/nomount_6.1_kernel_integration.patch

# If patch fails, see ADVANCED PATCHING section below
```

### Step 4: Copy NoMount Source Code
```bash
cd kernel_op13r

# Copy NoMount kernel source files to fs directory
echo "Copying NoMount source files..."
cp -v ../nomount_patch/kernel/src/* fs/

# Verify files were copied
ls -la fs/nomount*
```

### Step 5: Enable NoMount in Kernel Config
```bash
cd kernel_op13r

# Edit defconfig (device-specific config)
# Look for the right defconfig file:
find . -name "*defconfig" -type f | grep -i "13r\|oneplus\|sm8550"

# Example: arch/arm64/configs/vendor/gki_defconfig
# Add or ensure this line is present:
# CONFIG_NOMOUNT=y

echo "CONFIG_NOMOUNT=y" >> arch/arm64/configs/vendor/gki_defconfig

# Or use menuconfig if building interactively
make menuconfig
# Navigate to: Filesystems → NoMount Path Redirection Subsystem → Enable
```

### Step 6: Apply BakaSU Patches
```bash
cd kernel_op13r

# Clone BakaSU
git clone https://github.com/Baka-SU/BakaSU.git bakasu_patches

# Apply KernelSU integration (BakaSU is based on KernelSU)
if [ -f bakasu_patches/kernel/patches/*.patch ]; then
  for patch in bakasu_patches/kernel/patches/*.patch; do
    echo "Applying: $patch"
    patch -p1 < "$patch" || echo "⚠️  Patch conflict detected. Manual review needed."
  done
fi
```

### Advanced Patching: Manual Conflict Resolution
```bash
# If automatic patching fails:
patch -p1 --dry-run < ../nomount_patch/kernel/patches/nomount_6.1_kernel_integration.patch

# Review conflicts
# Then apply with fuzz to allow minor deviations:
patch -p1 -l --fuzz=2 < ../nomount_patch/kernel/patches/nomount_6.1_kernel_integration.patch

# Or manually edit affected files following INTEGRATION.md
```

---

## Part 3: Automated Build Script

See `scripts/build_kernel.sh` for the complete automated build script.

### Usage
```bash
chmod +x scripts/build_kernel.sh
./scripts/build_kernel.sh
```

---

## Part 4: GitHub Actions Workflow

See `.github/workflows/build-nomount-kernel.yml` for automated CI/CD building and releasing.

### Trigger the Workflow

**Manual trigger:**
```bash
gh workflow run build-nomount-kernel.yml
```

**Automatic trigger on push:**
```bash
git add kernel/
git commit -m "Update kernel patches"
git push origin main
```

**Create release:**
```bash
git tag v6.1.118-nomount-001
git push origin v6.1.118-nomount-001
```

---

## Quick Start Summary

```bash
# 1. Setup directories
mkdir -p custom-kernel && cd custom-kernel

# 2. Fetch kernel
git clone https://github.com/OnePlusOSS/android_kernel_oneplus_sm8550.git kernel_source
cd kernel_source && git checkout A15 && cd ..

# 3. Get patches
git clone --branch dev https://github.com/maxsteeel/nomount.git nomount_patch
git clone https://github.com/Baka-SU/BakaSU.git bakasu_patches

# 4. Run build script
chmod +x bakasu_patches/scripts/build_kernel.sh
./bakasu_patches/scripts/build_kernel.sh

# 5. Find output
ls -lh build_output/
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Patch fails to apply | Use `patch -p1 -l --fuzz=2` for fuzzy patching |
| CONFIG_NOMOUNT not enabled | Check `.config` file, ensure `CONFIG_NOMOUNT=y` |
| Build fails (missing headers) | Run `make headers_install` before build |
| Git clone hangs | Use `git clone --depth 1` for faster clone |
| Kernel version mismatch | Verify `Makefile` matches NoMount patch version |

---

## References
- [NoMount GitHub](https://github.com/maxsteeel/nomount)
- [BakaSU GitHub](https://github.com/Baka-SU/BakaSU)
- [OnePlus OSS](https://github.com/OnePlusOSS)
- [KernelSU Documentation](https://kernelsu.org)
