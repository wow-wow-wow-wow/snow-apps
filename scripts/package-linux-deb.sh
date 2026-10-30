#!/bin/bash
# Package a staged Snow Shot AppDir into a Debian archive. With --payload-tar
# the same /opt/snow-shot payload is emitted as a tarball for the Arch makepkg
# job, so every distro package ships byte-identical application files.
set -euo pipefail

snow_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
snow_repo_root="$(cd "$snow_script_dir/.." && pwd)"
snow_die() { printf '%s\n' "$*" >&2; exit 1; }

app_dir=''
version=''
output_dir="$snow_repo_root/build/linux-packages"
payload_tar=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --appdir) [[ $# -ge 2 ]] || snow_die '--appdir needs a directory'; app_dir="$2"; shift 2 ;;
        --version) [[ $# -ge 2 ]] || snow_die '--version needs a value'; version="$2"; shift 2 ;;
        --output-dir) [[ $# -ge 2 ]] || snow_die '--output-dir needs a directory'; output_dir="$2"; shift 2 ;;
        --payload-tar) [[ $# -ge 2 ]] || snow_die '--payload-tar needs a path'; payload_tar="$2"; shift 2 ;;
        *) snow_die "Unknown argument: $1" ;;
    esac
done
[[ -n "$app_dir" && -d "$app_dir/usr/bin" ]] || snow_die "Not a staged AppDir (missing usr/bin): $app_dir"
[[ -n "$version" ]] || snow_die '--version is required'
[[ "$(uname -s)" == Linux ]] || snow_die 'Debian packaging requires a Linux host.'


mkdir -p "$output_dir"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
pkg_root="$stage/pkg"

# 1. Application tree under /opt/snow-shot plus system integration in /usr.
mkdir -p "$pkg_root/opt/snow-shot" "$pkg_root/usr/bin" \
    "$pkg_root/usr/share/applications" "$pkg_root/usr/share/metainfo"
cp -a "$app_dir/usr/." "$pkg_root/opt/snow-shot/"
cp "$snow_repo_root/packaging/linux/snow-shot.sh.in" "$pkg_root/usr/bin/snow-shot"
chmod 755 "$pkg_root/usr/bin/snow-shot"
cp "$app_dir/usr/share/applications/snow_shot.desktop" "$pkg_root/usr/share/applications/snow_shot.desktop"
cp "$app_dir/usr/share/metainfo/top.snowshot.snow-shot.metainfo.xml" \
    "$pkg_root/usr/share/metainfo/top.snowshot.snow-shot.metainfo.xml"
if [[ -d "$app_dir/usr/share/icons/hicolor" ]]; then
    mkdir -p "$pkg_root/usr/share/icons"
    cp -a "$app_dir/usr/share/icons/hicolor" "$pkg_root/usr/share/icons/hicolor"
fi

# 2. Debian control metadata.
installed_size="$(du -sk "$pkg_root" | cut -f1)"
mkdir -p "$pkg_root/DEBIAN"
cat > "$pkg_root/DEBIAN/control" <<CONTROL
Package: snow-shot
Version: $version
Section: graphics
Priority: optional
Architecture: amd64
Installed-Size: $installed_size
Maintainer: Snow Apps <chao@mgchao.top>
Homepage: https://snowshot.top
Depends: libc6 (>= 2.31), libgcc-s1, libstdc++6, libwayland-client0, libwayland-cursor0, libwayland-egl1, libxkbcommon0, libxkbcommon-x11-0, libfontconfig1, libdbus-1-3, libglib2.0-0, libgl1, libegl1, libgbm1, libdrm2
Description: Screenshot utility for capturing, annotating, pinning, and recognizing screen content
 Snow Shot offers region and fullscreen capture, annotation tools, pinned
 snapshots, OCR, and screen recording. This package bundles its Qt runtime
 under /opt/snow-shot and integrates with the desktop through
 /usr/bin/snow-shot.
CONTROL

# 3. Emit the deb, and optionally the payload tarball for the Arch job.
if [[ -n "$payload_tar" ]]; then
    tar -C "$pkg_root" --exclude=./DEBIAN -caf "$payload_tar" .
    printf 'Payload tarball: %s\n' "$payload_tar"
fi
if command -v dpkg-deb >/dev/null; then
    deb_path="$output_dir/snow-shot_${version}_amd64.deb"
    dpkg-deb --root-owner-group --build "$pkg_root" "$deb_path"
    printf 'Debian package: %s\n' "$deb_path"
elif [[ -z "$payload_tar" ]]; then
    snow_die 'dpkg-deb is required unless --payload-tar output is requested.'
else
    printf 'dpkg-deb unavailable; emitted the payload tarball only.\n'
fi
