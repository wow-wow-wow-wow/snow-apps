#!/bin/bash
# Stage the Snow Shot Linux build tree into a self-contained AppDir with
# bundled Qt and vcpkg libraries, ready for appimagetool / dpkg-deb / makepkg.
set -euo pipefail

snow_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
snow_repo_root="$(cd "$snow_script_dir/.." && pwd)"
snow_die() { printf '%s\n' "$*" >&2; exit 1; }

build_dir=''
app_dir="$snow_repo_root/build/linux-appdir"
version=''
tools_cache="$snow_repo_root/.tools/linuxdeploy"
skip_qt_plugin=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-dir) [[ $# -ge 2 ]] || snow_die '--build-dir needs a directory'; build_dir="$2"; shift 2 ;;
        --appdir) [[ $# -ge 2 ]] || snow_die '--appdir needs a directory'; app_dir="$2"; shift 2 ;;
        --version) [[ $# -ge 2 ]] || snow_die '--version needs a value'; version="$2"; shift 2 ;;
        --tools-cache) [[ $# -ge 2 ]] || snow_die '--tools-cache needs a directory'; tools_cache="$2"; shift 2 ;;
        # Distro packages rely on the system Qt instead of bundling its plugins.
        --skip-qt-plugin) skip_qt_plugin=1; shift ;;
        *) snow_die "Unknown argument: $1" ;;
    esac
done
[[ -n "$build_dir" ]] || snow_die '--build-dir is required'
[[ -n "$version" ]] || snow_die '--version is required'
[[ -f "$build_dir/CMakeCache.txt" ]] || snow_die "Not a CMake build directory: $build_dir"
[[ "$(uname -s)" == Linux ]] || snow_die 'Linux packaging requires a Linux host.'

app_dir="$(mkdir -p "$app_dir" && cd "$app_dir" && pwd)"
printf 'Staging Snow Shot %s into %s\n' "$version" "$app_dir"

# 1. Install the Snow Shot component into the AppDir/usr prefix.
rm -rf "$app_dir"
mkdir -p "$app_dir"
DESTDIR="$app_dir" cmake --install "$build_dir" --prefix /usr --strip
[[ -x "$app_dir/usr/bin/snow_shot" ]] || snow_die 'The install tree has no usr/bin/snow_shot executable.'

# 2. Desktop integration inside the AppDir.
mkdir -p "$app_dir/usr/share/applications" "$app_dir/usr/share/metainfo"
cp "$snow_repo_root/packaging/linux/snow_shot.desktop" "$app_dir/usr/share/applications/snow_shot.desktop"
sed -e "s/@VERSION@/$version/g" -e "s/@DATE@/$(date +%Y-%m-%d)/g" \
    "$snow_repo_root/packaging/linux/top.snowshot.snow-shot.metainfo.xml" \
    > "$app_dir/usr/share/metainfo/top.snowshot.snow-shot.metainfo.xml"

# 3. Icons rendered from the committed SVG.
command -v rsvg-convert >/dev/null || snow_die 'rsvg-convert is required (librsvg2-bin).'
icon_svg="$snow_repo_root/snow_shot/resources/app-icon.svg"
for size in 64 128 256 512; do
    icon_dir="$app_dir/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    rsvg-convert -w "$size" -h "$size" "$icon_svg" -o "$icon_dir/snow-shot.png"
done
mkdir -p "$app_dir/usr/share/icons/hicolor/scalable/apps"
cp "$icon_svg" "$app_dir/usr/share/icons/hicolor/scalable/apps/snow-shot.svg"

# 4. AppRun entry point.
cp "$snow_repo_root/packaging/linux/AppRun.in" "$app_dir/AppRun"
chmod 755 "$app_dir/AppRun"

# 5. Bundle shared libraries with linuxdeploy + the Qt plugin.
qt_cmake_dir="$(sed -n 's/^Qt6_DIR:[^=]*=//p' "$build_dir/CMakeCache.txt" | head -n 1)"
qt_bin_dir=''
for candidate in "$qt_cmake_dir/../../bin" "$(dirname "$(command -v qmake6 2>/dev/null)")" \
    "$(dirname "$(command -v qmake 2>/dev/null)")"; do
    if [[ -n "$candidate" && (-x "$candidate/qmake" || -x "$candidate/qmake6") ]]; then
        qt_bin_dir="$(cd "$candidate" && pwd)"
        break
    fi
done
# The aqt kit resolves through <kit>/lib/cmake/Qt6 -> <kit>/bin; distro kits
# (e.g. Arch's /usr/lib/cmake/Qt6) fall through to the system qmake6.
[[ -n "$qt_bin_dir" ]] ||
    snow_die "Unable to resolve the Qt bin directory from the build cache: $qt_cmake_dir"
if [[ -x "$qt_bin_dir/qmake" ]]; then
    export QMAKE="$qt_bin_dir/qmake"
else
    export QMAKE="$qt_bin_dir/qmake6"
fi
export PATH="$qt_bin_dir:$PATH"

mkdir -p "$tools_cache"
linuxdeploy="$tools_cache/linuxdeploy-x86_64.AppImage"
plugin_qt="$tools_cache/linuxdeploy-plugin-qt-x86_64.AppImage"
fetch_tool() {
    local url="$1" output="$2"
    if [[ ! -x "$output" ]]; then
        printf 'Downloading %s\n' "$url"
        curl -fL --retry 3 -o "$output" "$url"
        chmod +x "$output"
    fi
}
fetch_tool 'https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage' "$linuxdeploy"
fetch_tool 'https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage' "$plugin_qt"

# linuxdeploy resolves DT_NEEDED entries against the search path; the vcpkg
# libraries live outside the default directories, so expose them here and let
# linuxdeploy copy the needed ones into the AppDir.
vcpkg_installed_dir="$(sed -n 's/^VCPKG_INSTALLED_DIR:[^=]*=//p' "$build_dir/CMakeCache.txt" | head -n 1)"
vcpkg_triplet="$(sed -n 's/^VCPKG_TARGET_TRIPLET:[^=]*=//p' "$build_dir/CMakeCache.txt" | head -n 1)"
if [[ -d "$vcpkg_installed_dir/$vcpkg_triplet/lib" ]]; then
    # Debug builds link the *d-suffixed libraries from the triplet's
    # debug/lib; expose both trees so linuxdeploy can resolve either.
    export LD_LIBRARY_PATH="$vcpkg_installed_dir/$vcpkg_triplet/lib:$vcpkg_installed_dir/$vcpkg_triplet/debug/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
# Project-shared libraries live across the build tree; make them resolvable
# too so linuxdeploy bundles them next to the executable.
while IFS= read -r so_dir; do
    export LD_LIBRARY_PATH="$so_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
done < <(find "$build_dir" -maxdepth 4 -name '*.so*' -printf '%h\n' 2>/dev/null | sort -u)

deploy_args=(--executable "$app_dir/usr/bin/snow_shot")
while IFS= read -r executable; do
    deploy_args+=(--executable "$executable")
done < <(find "$app_dir/usr/bin" -maxdepth 1 -type f -executable ! -name snow_shot)
while IFS= read -r shared_library; do
    deploy_args+=(--executable "$shared_library")
done < <(find "$app_dir/usr/lib" -maxdepth 1 -type f -name '*.so*' 2>/dev/null || true)

linuxdeploy_args=(--appdir "$app_dir" "${deploy_args[@]}"
    --desktop-file "$app_dir/usr/share/applications/snow_shot.desktop"
    --icon-file "$app_dir/usr/share/icons/hicolor/256x256/apps/snow-shot.png")
if [[ "$skip_qt_plugin" == 0 ]]; then
    linuxdeploy_args+=(--plugin qt)
else
    # Distro-package mode: Qt libraries and their plugins come from the
    # system packages, so keep them out of the payload.
    linuxdeploy_args+=(--exclude-library 'libQt6*')
fi

"$linuxdeploy" --appimage-extract-and-run "${linuxdeploy_args[@]}"

printf 'AppDir ready: %s\n' "$app_dir"
