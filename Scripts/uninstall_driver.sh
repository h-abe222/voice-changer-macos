#!/bin/bash
#
# uninstall_driver.sh
# Virtual Mic Driver のアンインストールスクリプト
#
# 使用方法: sudo ./Scripts/uninstall_driver.sh
#

set -e

DRIVER_NAME="VirtualMicDriver.driver"
INSTALL_PATH="/Library/Audio/Plug-Ins/HAL"
TARGET_DRIVER="$INSTALL_PATH/$DRIVER_NAME"

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

# ドライバ確認
if [ ! -d "$TARGET_DRIVER" ]; then
    echo_warn "Driver not installed: $TARGET_DRIVER"
    exit 0
fi

# 削除
echo_info "Removing driver..."
rm -rf "$TARGET_DRIVER"

# CoreAudio 再起動
echo_info "Restarting CoreAudio daemon..."
launchctl kickstart -k system/com.apple.audio.coreaudiod

echo ""
echo_info "Uninstallation complete."
