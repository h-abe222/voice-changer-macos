#!/bin/bash
#
# build_driver.sh
# Virtual Mic Driver のビルドスクリプト
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DRIVER_DIR="$PROJECT_ROOT/VirtualMicDriver"
BUILD_DIR="$PROJECT_ROOT/build/driver"
DRIVER_NAME="VirtualMicDriver.driver"

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ビルドディレクトリ作成
mkdir -p "$BUILD_DIR"

echo_info "Building Virtual Mic Driver..."

# ソースファイル
SOURCES=(
    "$DRIVER_DIR/Sources/VirtualMicDriver.c"
    "$DRIVER_DIR/Sources/VirtualMicProperties.c"
)

# コンパイラフラグ
CFLAGS=(
    -arch x86_64
    -arch arm64
    -mmacosx-version-min=13.0
    -O2
    -Wall
    -Wextra
    -fvisibility=hidden
    -I"$DRIVER_DIR/Sources"
)

# リンカフラグ
LDFLAGS=(
    -bundle
    -framework CoreFoundation
    -framework CoreAudio
    -framework AudioToolbox
)

# オブジェクトファイルビルド
OBJECTS=()
for src in "${SOURCES[@]}"; do
    obj="$BUILD_DIR/$(basename "${src%.c}.o")"
    echo_info "Compiling $(basename "$src")..."
    clang "${CFLAGS[@]}" -c "$src" -o "$obj"
    OBJECTS+=("$obj")
done

# バンドル構造作成
BUNDLE_DIR="$BUILD_DIR/$DRIVER_NAME"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"

# リンク
echo_info "Linking..."
clang "${LDFLAGS[@]}" "${OBJECTS[@]}" -o "$MACOS_DIR/VirtualMicDriver"

# Info.plist コピー
cp "$DRIVER_DIR/Info.plist" "$CONTENTS_DIR/"

# PkgInfo 作成
echo "BNDL????" > "$CONTENTS_DIR/PkgInfo"

echo_info "Build complete: $BUNDLE_DIR"

# サイズ確認
BINARY_SIZE=$(stat -f%z "$MACOS_DIR/VirtualMicDriver" 2>/dev/null || echo "unknown")
echo_info "Binary size: $BINARY_SIZE bytes"

# アーキテクチャ確認
echo_info "Architectures:"
file "$MACOS_DIR/VirtualMicDriver"

echo ""
echo_info "To install, run: sudo ./Scripts/install_driver.sh"
