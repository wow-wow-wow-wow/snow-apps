#!/bin/bash
# Shared by the Linux entry points; keeps the macOS helpers out of scope.
set -euo pipefail
snow_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
snow_die() { printf '%s\n' "$*" >&2; exit 1; }
snow_require_linux() {
    [[ "$(uname -s)" == Linux ]] || snow_die 'This entry point requires Linux.'
    [[ "$(uname -m)" == x86_64 ]] || snow_die 'Only x86_64 Linux hosts are supported by the linux-gcc presets.'
}
snow_require_rust() {
    local minimum version
    minimum="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rustMinimum"])' \
        "$snow_repo_root/scripts/build-toolchain.json")"
    version="$(cd "$snow_repo_root" && rustc --version)" || snow_die 'Unable to determine the active Rust version.'
    python3 - "$version" "$minimum" <<'PY' || snow_die "Rust $minimum or newer is required; found: $version"
import re
import sys

match = re.match(r"rustc (\d+)\.(\d+)\.(\d+)", sys.argv[1])
minimum = tuple(map(int, sys.argv[2].split(".")))
sys.exit(0 if match and tuple(map(int, match.groups())) >= minimum else 1)
PY
}
snow_qt_contract_version() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["qtVersion"])' \
        "$snow_repo_root/scripts/qt-toolchain.json"
}
snow_select_preset() {
    snow_preset="${1:-linux-gcc-debug}"
    [[ "$snow_preset" =~ ^linux-gcc-(debug|performance|release)$ ]] || snow_die "Unsupported Linux preset: $snow_preset"
    snow_rust_target=x86_64-unknown-linux-gnu
    snow_vcpkg_triplet=x64-linux-snow-shot
    snow_vcpkg_installed="$snow_repo_root/.tools/vcpkg/installed/dynamic"
    snow_build_dir="$snow_repo_root/build/$snow_preset"
}
snow_require_system_tools() {
    local tool
    for tool in "$@"; do
        command -v "$tool" >/dev/null || snow_die "Missing $tool. Install the prerequisites listed in docs-linux-build.md."
    done
}
snow_check_cmake_version() {
    local cmake_version
    cmake_version="$(cmake --version | head -n 1)"
    if [[ ! "$cmake_version" =~ ^cmake[[:space:]]version[[:space:]]([0-9]+)\.([0-9]+) ]] ||
        (( BASH_REMATCH[1] < 4 || (BASH_REMATCH[1] == 4 && BASH_REMATCH[2] < 2) )); then
        snow_die "CMake 4.2 or newer is required; found: ${cmake_version:-unknown}"
    fi
}
snow_check_libclang() {
    # bindgen (through ffmpeg-sys-next) needs a shared libclang at build time.
    if [[ -n "${LIBCLANG_PATH:-}" && -e "$LIBCLANG_PATH/libclang.so" ]]; then
        return
    fi
    if ldconfig -p 2>/dev/null | grep -q 'libclang.*\.so' ||
        compgen -G '/usr/lib/llvm-*/lib/libclang.so*' >/dev/null; then
        return
    fi
    snow_die 'libclang is required for the Rust FFI bindings. Install the libclang development package or set LIBCLANG_PATH.'
}
snow_setup_rust() {
    snow_require_rust
    local rust_host
    rust_host="$(rustc -vV | sed -n 's/^host: //p')"
    [[ -n "$rust_host" ]] || snow_die 'Unable to determine the active Rust host.'
    if [[ "$snow_rust_target" != "$rust_host" ]] &&
        ! rustup target list --installed | grep -Fqx "rust-std-$snow_rust_target"; then
        rustup target add "$snow_rust_target"
    fi
    printf 'Using the active Rust toolchain with target %s.\n' "$snow_rust_target"
}
snow_setup_ocr_toolchain() {
    # The OCR workspace keeps its own pinned nightly toolchain; pre-install it so
    # CMake-driven cargo builds never stall on a toolchain download.
    local ocr_pin="$snow_repo_root/snow-crates/crates/simd-paddle-ocr-rs/rust-toolchain.toml"
    [[ -f "$ocr_pin" ]] || snow_die 'Initialize Git submodules before building OCR: git submodule update --init --recursive'
    local ocr_toolchain
    ocr_toolchain="$(sed -n 's/^channel *= *"\([^"]*\)".*/\1/p' "$ocr_pin")"
    [[ "$ocr_toolchain" == nightly-* ]] || snow_die 'Invalid OCR toolchain pin.'
    if ! rustup toolchain list | grep -Fq "$ocr_toolchain-$snow_rust_target"; then
        rustup toolchain install "$ocr_toolchain" --profile minimal --component clippy --target "$snow_rust_target"
    fi
}
snow_setup_qt() {
    snow_qt_version="$(snow_qt_contract_version)"
    snow_qt_dir="${Qt6_DIR:-${SNOW_QT_DIR:-$HOME/Qt/$snow_qt_version/gcc_64/lib/cmake/Qt6}}"
    [[ -f "$snow_qt_dir/Qt6Config.cmake" ]] || snow_die "Set Qt6_DIR to the Qt $snow_qt_version Linux lib/cmake/Qt6 directory."
    snow_qt_dir="$(cd "$snow_qt_dir" && pwd)"
    export Qt6_DIR="$snow_qt_dir"
}
snow_setup_tools() {
    snow_require_system_tools cmake ninja pkg-config gcc g++ cargo rustc rustup python3 git curl zip unzip tar
    snow_check_cmake_version
    snow_check_libclang
    snow_setup_rust
    snow_setup_ocr_toolchain
    snow_setup_qt
    snow_vcpkg_root="$snow_repo_root/.tools/vcpkg"
    export VCPKG_ROOT="$snow_vcpkg_root"
}
snow_install_vcpkg_dependencies() {
    local vcpkg_root="$snow_repo_root/.tools/vcpkg"
    local vcpkg_baseline=4497409a47f19db373a410a0efb84eca4747adbf
    if [[ ! -d "$vcpkg_root/.git" ]]; then
        [[ ! -e "$vcpkg_root" ]] || snow_die "Repository-local vcpkg must be a Git checkout: $vcpkg_root"
        git clone https://github.com/microsoft/vcpkg.git "$vcpkg_root"
    fi
    local vcpkg_head
    vcpkg_head="$(git -C "$vcpkg_root" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$vcpkg_head" != "$vcpkg_baseline" ]]; then
        git -C "$vcpkg_root" fetch origin "$vcpkg_baseline" --depth=1
        git -C "$vcpkg_root" checkout --detach "$vcpkg_baseline"
    fi
    if [[ ! -x "$vcpkg_root/vcpkg" ]]; then
        "$vcpkg_root/bootstrap-vcpkg.sh" -disableMetrics
    fi
    "$vcpkg_root/vcpkg" install \
        "--x-manifest-root=$snow_repo_root" \
        "--x-install-root=$snow_vcpkg_installed" \
        "--triplet=$snow_vcpkg_triplet" \
        --x-feature=snow-shot \
        --x-feature=full-codecs \
        --x-feature=image-viewer \
        "--overlay-ports=$snow_repo_root/cmake/vcpkg-overlay-ports" \
        "--overlay-triplets=$snow_repo_root/cmake/vcpkg-overlay-triplets" \
        --clean-after-build
}
snow_cache_aligned() {
    local cache_path="$1"
    local cached_qt
    [[ -f "$cache_path" ]] || return 1
    cached_qt="$(sed -n 's/^Qt6_DIR:[^=]*=//p' "$cache_path" | head -n 1)"
    [[ "$cached_qt" == "$snow_qt_dir" ]] &&
        grep -Eq "^VCPKG_TARGET_TRIPLET:.*=$snow_vcpkg_triplet$" "$cache_path" &&
        grep -Fqx "VCPKG_INSTALLED_DIR:PATH=$snow_vcpkg_installed" "$cache_path" &&
        grep -Fqx "CMAKE_HOME_DIRECTORY:INTERNAL=$snow_repo_root" "$cache_path" &&
        grep -Fqx 'CMAKE_GENERATOR:INTERNAL=Ninja' "$cache_path"
}
