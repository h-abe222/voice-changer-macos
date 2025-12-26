#!/bin/bash
#
# build_all.sh
# App と Driver の両方をビルド
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

echo_header "Building Virtual Mic Driver"
"$SCRIPT_DIR/build_driver.sh"

echo_header "Building Voice Changer App"
"$SCRIPT_DIR/build_app.sh" "$@"

echo ""
echo -e "${GREEN}All builds completed successfully!${NC}"
echo ""
echo "Next steps:"
echo "  1. Install driver: sudo ./Scripts/install_driver.sh"
echo "  2. Run app: ./build/app/release/VoiceChangerApp"
