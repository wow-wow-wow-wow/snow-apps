#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/snow-build-linux-environment.sh"
if [[ "${1:-}" == --help ]]; then
    echo 'Usage: bootstrap-linux.sh [linux-preset] [--skip-dependency-install]'
    printf 'Requires GCC/G++, Rust (rustup), Qt %s, CMake >= 4.2, Ninja, pkg-config and libclang.\n' \
        "$(python3 -c 'import json; print(json.load(open("scripts/qt-toolchain.json"))["qtVersion"])' 2>/dev/null || echo 6.12.0)"
    exit 0
fi
snow_require_linux
preset=''
if [[ $# -gt 0 && "$1" != --* ]]; then preset="$1"; shift; fi
snow_select_preset "$preset"
skip_dependencies=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-dependency-install) skip_dependencies=1 ;;
        *) snow_die "Unknown argument: $1" ;;
    esac
    shift
done
snow_setup_tools
cd "$snow_repo_root"
if [[ "$skip_dependencies" == 0 ]]; then
    snow_install_vcpkg_dependencies
fi
