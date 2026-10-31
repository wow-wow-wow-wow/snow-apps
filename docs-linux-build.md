# Building Snow Shot for Linux x64 (KDE / Wayland)

This document describes the Linux x86_64 port of Snow Shot and Snow Image
Viewer: toolchain requirements, presets, build commands, and packaging. The
Linux support follows the same structure as the macOS port
(`docs-macos-build.md`): repository-managed vcpkg, a pinned Qt 6.12.0 kit, and
`scripts/bootstrap-linux.sh` / `scripts/build-linux.sh` entry points.

## Scope of the Linux port

Snow Shot builds and runs on Linux x86_64 with Qt 6.12.0. Feature parity with
Windows/macOS is delivered in milestones:

- **Working now**: the application shell (settings/storage/i18n/single
  instance), tray menu, image editing, history, collage, LaTeX rendering, QR
  recognition (OpenCV wechat_qrcode), image export (PNG/JPEG/WebP/HEIF/JXL),
  the Rust recording/export/OCR/stitching engine surface, and Snow Image
  Viewer (QRhi OpenGL renderer on Linux).
- **Platform backends with graceful fallbacks**: screen capture, global
  hotkeys, window enumeration, selected-file queries, and per-monitor effects
  currently return "unsupported" through the existing platform factories. The
  xdg-desktop-portal / PipeWire / LayerShellQt capture pipeline (plan
  P3/P5) is follow-up work; see `snow-apps-linux-port-plan.md`.
- **Autostart** writes an XDG autostart entry
  (`~/.config/autostart/snow_shot.desktop`).
- **Crash diagnostics** use systemd coredumps; Crashpad stays Windows/macOS
  only.
- **Tier C features** (mouse gestures, input injection, self-update, store
  channel) are intentionally absent; the Windows updater flow is compiled out
  on Linux.

## Prerequisites

- Debian/Ubuntu:

  ```bash
  sudo apt-get install -y --no-install-recommends \
      ninja-build pkg-config g++ gcc libclang-dev clang \
      desktop-file-utils librsvg2-bin patchelf file curl zip unzip tar
  python3 -m pip install --user --break-system-packages 'cmake>=4.2'
  ```

- Rust >= 1.97.1 via rustup with the `x86_64-unknown-linux-gnu` target
  (`rustup target add x86_64-unknown-linux-gnu`).
- Git submodules: `git submodule update --init --recursive` (the OCR workspace
  pins its own dated nightly toolchain; bootstrap installs it).
- Qt **6.12.0** (exact) shared kit. Either install it with aqtinstall:

  ```bash
  python3 -m pip install --user --break-system-packages aqtinstall
  aqt install-qt linux desktop 6.12.0 gcc_64 --outputdir "$HOME/Qt"
  ```

  or point `Qt6_DIR` at a self-provisioned 6.12.0 kit.

## Bootstrap and build

```bash
# One-time per machine: vcpkg clone + dependency install (ffmpeg, opencv4,
# codecs, vulkan headers) into .tools/vcpkg/installed/dynamic
scripts/bootstrap-linux.sh linux-gcc-release

# Configure + build snow-all
scripts/build-linux.sh linux-gcc-release --parallel "$(nproc)"
```

`build-linux.sh` resolves Qt from `$Qt6_DIR`, `$SNOW_QT_DIR`, or
`$HOME/Qt/6.12.0/gcc_64` and passes `-D Qt6_DIR=...` to CMake.

| Preset | Build type | Tests | Use |
|---|---|---|---|
| `linux-gcc-debug` | Debug | ON | Development, unit tests |
| `linux-gcc-performance` | Release | ON | Benchmarks (`SNOW_APPS_BUILD_BENCHMARKS=ON`) |
| `linux-gcc-release` | Release | OFF | Packaging |

Run the app from the build tree:

```bash
QT_QPA_PLATFORM=wayland ./build/linux-gcc-release/snow_shot/snow_shot
./build/linux-gcc-release/snow_image_viewer/snow_image_viewer
```

Native Wayland is the target session (`echo $XDG_SESSION_TYPE` → `wayland`);
Qt falls back to X11/XWayland automatically when Wayland is unavailable.

Tests (only the ones relevant to a change, per `AGENTS.md`):

```bash
ctest --preset test-linux-gcc-debug -R "snow-shot-file-manager" -L unit
cargo test -p snow-capture      # in snow-crates/
```

## Packaging

`scripts/stage-linux-appdir.sh` turns the `linux-gcc-release` build tree into
a self-contained AppDir: `cmake --install`, hicolor icons rendered from
`snow_shot/resources/app-icon.svg`, and Qt/vcpkg shared libraries bundled via
linuxdeploy + linuxdeploy-plugin-qt. Three package formats are produced from
that AppDir:

| Format | Producer | Notes |
|---|---|---|
| `.deb` | `scripts/package-linux-deb.sh` | App under `/opt/snow-shot`, integration in `/usr/bin` + `/usr/share`; needs `dpkg-deb` |
| `.pkg.tar.zst` | `packaging/linux/PKGBUILD.in` + makepkg | Consumes the payload tarball emitted by the deb script |
| `.AppImage` | `appimagetool build/linux-appdir out.AppImage` | Universal; glibc baseline of the build host |

Continuous integration (`.github/workflows/snow-shot-linux.yml`) builds and
packages all three formats on every pull request and `main` push, and
publishes them as release assets for `v*` tags. The `configure_only` input
gives fast feedback for build system changes.

## Packaging layout

```
/opt/snow-shot/bin/snow_shot            main executable
/opt/snow-shot/bin/snow_ocr_process     OCR worker (Rust)
/opt/snow-shot/bin/snow-shot-mcp        MCP bridge (Rust)
/opt/snow-shot/bin/assets/qrcode/       WeChat QR models
/opt/snow-shot/lib, /plugins, ...       bundled Qt + vcpkg libraries (RPATH $ORIGIN-based)
/usr/bin/snow-shot                      launcher
/usr/share/applications/snow_shot.desktop
/usr/share/icons/hicolor/*/apps/snow-shot.{png,svg}
/usr/share/metainfo/top.snowshot.snow-shot.metainfo.xml
```

## Deviations from snow-apps-linux-port-plan.md

- Qt 6.12.0 comes from the official shared kit (aqt) instead of a source-built
  static kit; the static-Qt release path (`SNOW_APPS_QT_STATIC`) is not wired
  for Linux yet.
- VA-API hwaccels are enabled in the ffmpeg feature set, but no code consumes
  them yet (plan P5-T3); software encoding (libx264/libx265) is the encoding
  path.
- Linux unit tests are not executed in CI yet (the release preset builds with
  tests off); the `--distribution-probe` smoke check runs instead.
- Milestone tasks that require a real KDE Wayland session (portal capture,
  LayerShellQt overlays, hotkey portal) are pending; the plan's【VM】items are
  marked BLOCKED(manual) until such an environment is available.
