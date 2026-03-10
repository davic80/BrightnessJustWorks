#!/bin/bash
# build_pkg.sh — builds BrightnessJustWorks-<version>.pkg
# Usage: bash installer/build_pkg.sh <build-dir> <version>
#   <build-dir>  path containing BrightnessJustWorks.app (already signed)
#   <version>    e.g. v1.2.0
#
# Produces: <build-dir>/BrightnessJustWorks-<version>.pkg
set -euo pipefail

BUILD_DIR="${1:?Usage: $0 <build-dir> <version>}"
VERSION="${2:?Usage: $0 <build-dir> <version>}"
SCRIPT_DIR="$(cd "$(dirname "$0")/installer" && pwd)"
WORK_DIR="$(mktemp -d)"

echo "==> Building installer pkg for $VERSION"
echo "    App:      $BUILD_DIR/BrightnessJustWorks.app"
echo "    Pkg root: $WORK_DIR"

# 1. Build component package (places app at /Applications)
pkgbuild \
    --install-location /Applications \
    --component "$BUILD_DIR/BrightnessJustWorks.app" \
    --scripts "$SCRIPT_DIR/scripts" \
    --identifier com.brightnessjustworks.pkg \
    --version "${VERSION#v}" \
    "$WORK_DIR/component.pkg"

# 2. Build product installer with welcome/license UI
productbuild \
    --distribution "$SCRIPT_DIR/distribution.xml" \
    --resources "$SCRIPT_DIR/Resources" \
    --package-path "$WORK_DIR" \
    "$BUILD_DIR/BrightnessJustWorks-${VERSION}.pkg"

rm -rf "$WORK_DIR"
echo "==> Done: $BUILD_DIR/BrightnessJustWorks-${VERSION}.pkg"
