#!/bin/bash
# ==============================================================================
# Build Mellanox ConnectX-4 Lx RDMA Kernel Modules from Linux 6.6.32 Source
# Target: Linux 6.6.32-qnap SMP preempt mod_unload (x86_64)
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$DIR/src/x86_64/driver"
KERNEL_VER="6.6.32"
KERNEL_TAR="linux-${KERNEL_VER}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_TAR}"

echo "=== [1/5] Checking Build Environment ==="
if ! command -v gcc &>/dev/null || ! command -v make &>/dev/null; then
    echo "ERROR: gcc and make are required to build kernel modules."
    exit 1
fi

echo "=== [2/5] Preparing Kernel Source Tree (${KERNEL_VER}) ==="
BUILD_TMP=$(mktemp -d /tmp/kbuild_XXXXXX)
cd "$BUILD_TMP"

if [ ! -f "$DIR/$KERNEL_TAR" ]; then
    echo "Downloading ${KERNEL_TAR} from kernel.org..."
    wget -c "$KERNEL_URL" -O "$KERNEL_TAR"
else
    cp "$DIR/$KERNEL_TAR" "$KERNEL_TAR"
fi

tar -xf "$KERNEL_TAR"
cd "linux-${KERNEL_VER}"

echo "=== [3/5] Configuring Kernel for Target System ==="
make x86_64_defconfig
scripts/config --set-str LOCALVERSION "-qnap"
scripts/config --disable MODVERSIONS
scripts/config --enable MODULES
scripts/config --enable MODULE_UNLOAD
scripts/config --enable PREEMPT
scripts/config --enable DYNAMIC_DEBUG
scripts/config --enable INFINIBAND
scripts/config --module INFINIBAND_USER_MAD
scripts/config --module INFINIBAND_USER_ACCESS
scripts/config --module MLX5_CORE
scripts/config --module MLX5_INFINIBAND
scripts/config --enable MODULE_ALLOW_MISSING_NAMESPACE_IMPORTS

make modules_prepare

echo "=== [4/5] Building Infiniband & MLX5 Driver Modules ==="
KBUILD_MODPOST_WARN=1 make -j$(nproc) M=drivers/infiniband/hw/mlx5 modules
KBUILD_MODPOST_WARN=1 make -j$(nproc) M=drivers/infiniband/core modules

echo "=== [5/5] Deploying Output Modules to ${OUTPUT_DIR} ==="
mkdir -p "$OUTPUT_DIR"
for ko in drivers/infiniband/hw/mlx5/mlx5_ib.ko \
          drivers/infiniband/core/ib_uverbs.ko \
          drivers/infiniband/core/ib_umad.ko \
          drivers/infiniband/core/rdma_ucm.ko; do
    if [ -f "$ko" ]; then
        cp -f "$ko" "$OUTPUT_DIR/"
        echo "Installed: $(basename "$ko")"
    fi
done

cd "$DIR"
rm -rf "$BUILD_TMP"
echo "Build complete. Driver modules saved in $OUTPUT_DIR"
