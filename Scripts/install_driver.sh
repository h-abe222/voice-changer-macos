#!/bin/bash
#
# install_driver.sh
# Virtual Mic Driver のインストールスクリプト
#
# 使用方法: sudo ./Scripts/install_driver.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build/driver"
DRIVER_NAME="VirtualMicDriver.driver"
INSTALL_PATH="/Library/Audio/Plug-Ins/HAL"

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

# root 権限チェック
if [ "$EUID" -ne 0 ]; then
    echo_error "Please run as root: sudo $0"
    exit 1
fi

# ビルド済みドライバ確認
SOURCE_DRIVER="$BUILD_DIR/$DRIVER_NAME"
if [ ! -d "$SOURCE_DRIVER" ]; then
    echo_error "Driver not found. Please build first: ./Scripts/build_driver.sh"
    exit 1
fi

# インストールディレクトリ確認
if [ ! -d "$INSTALL_PATH" ]; then
    echo_info "Creating HAL plug-ins directory..."
    mkdir -p "$INSTALL_PATH"
fi

# 既存ドライバ削除
TARGET_DRIVER="$INSTALL_PATH/$DRIVER_NAME"
if [ -d "$TARGET_DRIVER" ]; then
    echo_info "Removing existing driver..."
    rm -rf "$TARGET_DRIVER"
fi

# ドライバコピー
echo_info "Installing driver..."
cp -R "$SOURCE_DRIVER" "$INSTALL_PATH/"

# 権限設定
echo_info "Setting permissions..."
chown -R root:wheel "$TARGET_DRIVER"
chmod -R 755 "$TARGET_DRIVER"

# CoreAudio 再起動
echo_info "Restarting CoreAudio daemon..."
launchctl kickstart -k system/com.apple.audio.coreaudiod

# 確認
sleep 2
echo_info "Verifying installation..."

# デバイス一覧確認
if system_profiler SPAudioDataType 2>/dev/null | grep -q "VoiceChanger"; then
    echo_info "Driver installed and recognized successfully!"
else
    echo_warn "Driver installed but may need a system restart to be recognized."
fi

echo ""
echo_info "Installation complete: $TARGET_DRIVER"
echo ""
echo "To uninstall, run: sudo ./Scripts/uninstall_driver.sh"
