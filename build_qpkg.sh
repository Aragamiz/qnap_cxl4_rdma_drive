#!/bin/bash
# ==============================================================================
# Build & Self-Sign Mellanox ConnectX-4 Lx RDMA QPKG for QuTS hero
# ==============================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$DIR/build"
SRC_DIR="$DIR/src"
CERT_DIR="$DIR/cert"

mkdir -p "$BUILD_DIR" "$CERT_DIR"

# 1. Ensure Self-Signed Certificate and Private Key exist locally
if [ ! -f "$CERT_DIR/cert.pem" ] || [ ! -f "$CERT_DIR/key.pem" ]; then
    echo "==> Generating X.509 RSA-2048 self-signed certificate..."
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$CERT_DIR/key.pem" \
        -out "$CERT_DIR/cert.pem" \
        -days 3650 -nodes \
        -subj "/CN=CX4L RoCEv2 Community Driver/O=Mellanox-CX4-RDMA/C=TW"
fi

export PATH="/usr/share/QDK/bin:$PATH"

# 2. Prepare QDK build environment
WORKDIR=$(mktemp -d /tmp/qpkg_build_XXXXXX)

cp -r "$SRC_DIR/"* "$WORKDIR/"
cp "$CERT_DIR/cert.pem" "$WORKDIR/certificate"
cp "$CERT_DIR/key.pem" "$WORKDIR/private_key"

echo "==> Building QPKG via QDK qbuild..."
cd "$WORKDIR"
# Note: Self-signed certificates produce a verification notice which returns non-zero, allow continuation
qbuild --root "$WORKDIR" || true

echo "==> Packaging completed. Collecting artifact..."
PKG_FILE=$(find "$WORKDIR/build" -name "*.qpkg" | head -n 1)
if [ -z "$PKG_FILE" ] || [ ! -f "$PKG_FILE" ]; then
    echo "ERROR: No .qpkg built in $WORKDIR/build!"
    rm -rf "$WORKDIR"
    exit 1
fi

echo "==> Found built package: $PKG_FILE (size: $(stat -c%s "$PKG_FILE") bytes)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cp -f "$PKG_FILE" "$BUILD_DIR/qnap_cxl4_rdma_drive_v1.0.qpkg"
md5sum "$BUILD_DIR/qnap_cxl4_rdma_drive_v1.0.qpkg" > "$BUILD_DIR/qnap_cxl4_rdma_drive_v1.0.qpkg.md5"
rm -rf "$WORKDIR"

echo "==> Successfully updated artifact: $BUILD_DIR/qnap_cxl4_rdma_drive_v1.0.qpkg"
