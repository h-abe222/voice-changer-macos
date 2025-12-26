#!/bin/bash
#
# build_app.sh
# Voice Changer App のビルドスクリプト（Swift Package Manager）
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build/app"

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

# 引数パース
CONFIGURATION="release"
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            CONFIGURATION="debug"
            shift
            ;;
        --release)
            CONFIGURATION="release"
            shift
            ;;
        *)
            echo_error "Unknown option: $1"
            echo "Usage: $0 [--debug|--release]"
            exit 1
            ;;
    esac
done

echo_info "Building Voice Changer App ($CONFIGURATION)..."

cd "$PROJECT_ROOT"

# クリーン（オプション）
if [ "$CLEAN" = "1" ]; then
    echo_info "Cleaning build..."
    swift package clean
fi

# ビルド
if [ "$CONFIGURATION" = "release" ]; then
    swift build -c release --build-path "$BUILD_DIR"
else
    swift build -c debug --build-path "$BUILD_DIR"
fi

echo_info "Build complete!"

# 成果物の場所
if [ "$CONFIGURATION" = "release" ]; then
    BINARY_PATH="$BUILD_DIR/release/VoiceChangerApp"
else
    BINARY_PATH="$BUILD_DIR/debug/VoiceChangerApp"
fi

if [ -f "$BINARY_PATH" ]; then
    echo_info "Binary: $BINARY_PATH"
    echo_info "Size: $(stat -f%z "$BINARY_PATH") bytes"
fi
