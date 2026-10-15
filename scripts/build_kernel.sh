#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
KERNEL_DIR="kernel_op13r"
NOMOUNT_PATCH_DIR="nomount_patch"
BAKASU_DIR="bakasu_patches"
BUILD_OUTPUT="build_output"
DEVICE="OnePlus13R"
KERNEL_VERSION="6.1.118"

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Step 1: Validate directories
step_validate() {
  log_info "Step 1: Validating directories..."
  
  [ -d "$KERNEL_DIR" ] || log_error "Kernel directory not found: $KERNEL_DIR"
  [ -f "$KERNEL_DIR/Makefile" ] || log_error "Makefile not found in $KERNEL_DIR"
  [ -d "$NOMOUNT_PATCH_DIR" ] || log_warn "NoMount directory not found. Skipping NoMount integration."
  
  log_info "✅ Directories validated"
}

# Step 2: Apply patches
step_apply_patches() {
  log_info "Step 2: Applying patches..."
  
  cd "$KERNEL_DIR"
  
  # Get kernel major.minor version
  KERNEL_MAJOR=$(grep "^VERSION" Makefile | awk '{print $NF}')
  KERNEL_MINOR=$(grep "^PATCHLEVEL" Makefile | awk '{print $NF}')
  KERNEL_VERSION_STRING="${KERNEL_MAJOR}.${KERNEL_MINOR}"
  
  log_info "Kernel version: $KERNEL_VERSION_STRING"
  
  # Apply NoMount patch
  if [ -d "../$NOMOUNT_PATCH_DIR" ]; then
    NOMOUNT_PATCH="../$NOMOUNT_PATCH_DIR/kernel/patches/nomount_${KERNEL_VERSION_STRING}_kernel_integration.patch"
    
    if [ -f "$NOMOUNT_PATCH" ]; then
      log_info "Applying NoMount patch: $(basename $NOMOUNT_PATCH)"
      if patch -p1 --dry-run < "$NOMOUNT_PATCH" > /dev/null 2>&1; then
        patch -p1 < "$NOMOUNT_PATCH"
        log_info "✅ NoMount patch applied successfully"
      else
        log_warn "NoMount patch conflicts detected. Attempting fuzzy patch..."
        patch -p1 -l --fuzz=2 < "$NOMOUNT_PATCH" || log_warn "Manual patch resolution required"
      fi
    else
      log_warn "No NoMount patch found for kernel $KERNEL_VERSION_STRING"
    fi
  fi
  
  # Copy NoMount source
  if [ -d "../$NOMOUNT_PATCH_DIR/kernel/src" ]; then
    log_info "Copying NoMount source files..."
    cp -v "../$NOMOUNT_PATCH_DIR/kernel/src"/* fs/ 2>/dev/null || true
  fi
  
  # Apply BakaSU patches
  if [ -d "../$BAKASU_DIR/kernel/patches" ]; then
    log_info "Applying BakaSU patches..."
    for patch in "../$BAKASU_DIR/kernel/patches"/*.patch; do
      if [ -f "$patch" ]; then
        log_info "Applying: $(basename $patch)"
        patch -p1 < "$patch" || log_warn "Failed to apply $(basename $patch)"
      fi
    done
  fi
  
  cd ..
  log_info "✅ Patches applied"
}

# Step 3: Configure kernel
step_configure() {
  log_info "Step 3: Configuring kernel..."
  
  cd "$KERNEL_DIR"
  
  # Find and prepare defconfig
  DEFCONFIG=$(find . -name "*defconfig" -type f | grep -i "vendor\|gki" | head -1)
  
  if [ -z "$DEFCONFIG" ]; then
    log_error "Could not find defconfig file"
  fi
  
  log_info "Using defconfig: $DEFCONFIG"
  
  # Copy to .config
  cp "$DEFCONFIG" .config
  
  # Enable NoMount
  echo "CONFIG_NOMOUNT=y" >> .config
  
  # Make oldconfig to update and validate
  log_info "Running 'make oldconfig' to validate configuration..."
  make oldconfig < /dev/null || true
  
  cd ..
  log_info "✅ Kernel configured"
}

# Step 4: Build kernel
step_build() {
  log_info "Step 4: Building kernel..."
  
  cd "$KERNEL_DIR"
  
  # Get number of CPU cores for parallel build
  CORES=$(nproc)
  log_info "Building with $CORES cores..."
  
  # Build
  make -j"$CORES" 2>&1 | tee ../build.log
  
  if [ $? -ne 0 ]; then
    log_error "Kernel build failed. Check build.log for details."
  fi
  
  cd ..
  log_info "✅ Kernel built successfully"
}

# Step 5: Collect output
step_collect_output() {
  log_info "Step 5: Collecting build outputs..."
  
  mkdir -p "$BUILD_OUTPUT"
  
  # Find and copy kernel image
  KERNEL_IMAGE=$(find "$KERNEL_DIR" -name "Image*" -o -name "vmlinux*" | head -1)
  if [ -n "$KERNEL_IMAGE" ]; then
    cp "$KERNEL_IMAGE" "$BUILD_OUTPUT/"
    log_info "Copied kernel image: $(basename $KERNEL_IMAGE)"
  fi
  
  # Copy device tree files
  if [ -d "$KERNEL_DIR/arch/arm64/boot/dts" ]; then
    cp "$KERNEL_DIR/arch/arm64/boot/dts"/*.dtb "$BUILD_OUTPUT/" 2>/dev/null || true
    log_info "Copied device tree binaries"
  fi
  
  # Copy build config
  cp "$KERNEL_DIR/.config" "$BUILD_OUTPUT/kernel.config"
  cp "$KERNEL_DIR/System.map" "$BUILD_OUTPUT/" 2>/dev/null || true
  
  log_info "✅ Build artifacts collected in $BUILD_OUTPUT"
  echo ""
  log_info "Build artifacts:"
  ls -lh "$BUILD_OUTPUT/"
}

# Main execution
main() {
  log_info "======================================"
  log_info "OnePlus 13R Custom Kernel Build"
  log_info "BakaSU + NoMount Integration"
  log_info "======================================"
  log_info "Device: $DEVICE"
  log_info "Target Kernel: $KERNEL_VERSION"
  log_info ""
  
  step_validate
  step_apply_patches
  step_configure
  step_build
  step_collect_output
  
  echo ""
  log_info "======================================"
  log_info "✅ Build completed successfully!"
  log_info "======================================"
  log_info "Next steps:"
  log_info "1. Verify kernel image: $BUILD_OUTPUT/Image"
  log_info "2. Create flashable boot.img using mkbootimg"
  log_info "3. Flash to device using fastboot"
}

main "$@"
