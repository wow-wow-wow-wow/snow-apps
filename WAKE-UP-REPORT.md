# WAKE-UP-REPORT — 2026-10-30 执行会话收尾

会话目标:把项目推进到"能产出一个可安装、能启动、核心截图流程可用的原生软件包"并推送 GitHub。
本报告只陈述有证据支撑的事实。恢复上下文的顺序:**本文件 → ~/AGENT-STATE.md → plan §9.5**。

---

## 1. 任务卡完成情况

| ID | 状态 | 说明 / 证据 |
|---|---|---|
| P0-T1 | DROPPED(转 fork) | 直接在 fork 仓库执行(沿用上一会话决策) |
| P0-T2 | DONE(待VM) | bootstrap-linux.sh 工具链检查替代;P3+ 系统库检查未做 |
| P0-T3 | DONE | vcpkg 34 端口本机安装成功(evidence/P0-T3/vcpkg-install.log);CI 侧此前已绿 |
| P0-T4 | DONE(部分) | 仅共享 Qt kit 路径(系统 qt6-base 6.12.0);静态 Qt 未做 |
| P0-T5 | DONE | presets+脚本落地;本机 configure 绿(evidence/P0-T5/configure.log);修复 libclang 探测 SIGPIPE bug |
| P0-T6 | DONE | 三处 else() 默认 Windows 源已消灭(上一会话)+ 本轮把 linux 平台源挂进各目标(evidence/P0-T6/audit.md) |
| P0-T7 | DONE | libsnow_shot_rust_ffi.a 存在(483MB debug,evidence/P0-T7/artifact.txt);snow-linux/capture 等 crate clippy -D warnings 全过;FFMPEG_DIR 走 vcpkg 树(ffmpeg-link.md) |
| P0-T8 | DONE | snow-linux crate 建立;**snow-all 783/783 目标编译+链接全绿**(GCC 16.2.1 严格警告,evidence/P0-T8/snow-all.log);ctest -L unit 已跑(见 §3) |
| P0-GATE | DONE(待CI) | `--clean-first` 干净重编 5695/5695 全绿(evidence/P0-GATE/clean-rebuild.log);CI 编译+链接已在 run 41127295313 验证通过;打包步骤两轮脚本修复后由 run 41137556133 终判 |
| P2-T4 | DONE(待VM) | XDG autostart + 更新器禁用(上一会话遗留状态,未变) |
| P8-T1 | DONE(待VM) | 打包链本机实跑:修复 3 个脚本 bug 后 AppDir 就绪(94 个库),payload tar + makepkg 产出 .pkg.tar.zst;安装/启动验证 BLOCKED(manual);AppImage 路径(--plugin qt)失败待适配 |
| P1-T1 及之后 | TODO | 未开始(P0-GATE 是前置) |

## 2. 可安装产物与安装命令

| 产物 | 路径 |
|---|---|
| **Arch 包(本机可用)** | `/home/ygh/code/snow-apps/build/linux-packages/snow-shot-1.4.3-1-x86_64.pkg.tar.zst`(127MB) |
| payload tar(CI 的 Arch job 输入) | `/home/ygh/code/snow-apps/build/linux-packages/snow-shot_1.4.3_amd64-payload.tar.gz` |
| 已组装 AppDir | `/home/ygh/code/snow-apps/build/linux-appdir/`(94 个捆绑库 + usr/bin/snow_shot + desktop/icon/metainfo) |

安装命令(需要 root,本会话 sudo 无密码不可用 → **BLOCKED(manual)**,请真人执行):

```bash
sudo pacman -U /home/ygh/code/snow-apps/build/linux-packages/snow-shot-1.4.3-1-x86_64.pkg.tar.zst
snow-shot   # 启动(依赖系统 qt6-base/qt6-wayland,本机已装 6.12.0)
```

注意:该包是 **debug 构建**(build/linux-gcc-debug 打包),未捆绑 Qt(依赖系统 Qt,发行版模式 `--skip-qt-plugin`),仅供本机验证;发布包应走 release preset + CI。

## 3. 已在本机验证通过的内容(命令 + 输出摘要)

| 验证 | 命令 | 结果 |
|---|---|---|
| vcpkg 34 端口安装 | `bash scripts/bootstrap-linux.sh linux-gcc-debug`(VCPKG_MAX_CONCURRENCY=6) | 34/34 成功,约 1h20m(evidence/P0-T3/vcpkg-install.log) |
| CMake configure | `cmake --preset linux-gcc-debug -D Qt6_DIR=/usr/lib/cmake/Qt6 -D CMAKE_C_COMPILER_LAUNCHER=ccache -D CMAKE_CXX_COMPILER_LAUNCHER=ccache` | 退出 0(evidence/P0-T5/configure.log) |
| **全库编译+链接** | `cmake --build --preset build-linux-gcc-debug --target snow-all --parallel 6` | **退出 0,783/783 目标**(evidence/P0-T8/snow-all.log;经 14 轮 GCC 16 严格警告修复) |
| Rust FFI 静态库 | `find build/linux-gcc-debug/cargo -name libsnow_shot_rust_ffi.a` | 存在,483MB(debug)(evidence/P0-T7/artifact.txt) |
| Rust clippy | `cargo clippy -p snow-linux / snow-capture / snow-ui-selector / snow-audio-recorder / snow-recording-export -- -D warnings` | 全过(rust 1.99 lint 迁移 commit dd3ad4c3) |
| 单元测试 | `ctest --preset test-linux-gcc-debug -L unit` | **818/875 通过(93%),57 失败**(evidence/P0-T8/ctest-unit.log + ctest-failures.txt)。失败集中在 GUI/渲染/录制预览/OCR 服务/HEIF HEVC 编码类;抽查 snow_image_core_tests 失败点 = "HEIC encode succeeds when the HEVC backend is available"(libheif HEVC 后端能力缺口,非代码回归)。57 个未逐一归因,见 §4 |
| 打包链 | `stage-linux-appdir.sh --skip-qt-plugin` → `package-linux-deb.sh --payload-tar` → `makepkg` | AppDir 就绪(STAGE_EXIT=0,94 库,Qt 正确排除)→ payload tar → `.pkg.tar.zst` 产出(makepkg "完成创建") |

修复过程中顺带建立(已提交):snow-linux crate 骨架、linux/windowcaptureexclusion.cpp 优雅降级实现、linux/autostartregistration.cpp 挂进构建、P0-T6 audit.md、CI 诊断 evidence/ci-diagnosis.md。

## 4. 需要真人在真实 KDE Wayland 会话验证的清单【VM】

1. **安装与启动**(最高优先):
   - `sudo pacman -U /home/ygh/code/snow-apps/build/linux-packages/snow-shot-1.4.3-1-x86_64.pkg.tar.zst && snow-shot`
   - 预期:主窗口出现、不崩溃。若起不来:`QT_LOGGING_RULES="qt.qpa.*=true" snow-shot 2>&1 | head -50` 抓日志。
2. **AppDir 直跑(免安装)**:
   - `cd /home/ygh/code/snow-apps/build/linux-appdir && LD_LIBRARY_PATH=$PWD/usr/lib QT_QPA_PLATFORM=wayland ./usr/bin/snow_shot`
   - 预期:同上(本会话尝试执行时被中断,未取得结果,不算通过)。
3. **ctest 57 个失败逐一定性**(evidence/P0-T8/ctest-failures.txt):
   - GUI/渲染类(magnifier/text/toolbar/recording-preview 等)预期在真实会话中转绿或确认为【VM】项;
   - `snow-shot-screenshot-tool-palette-tests`、`snow-shot-mcp-recording-tests` 是 SEGFAULT,值得优先查;
   - `snow_image_heif_tests`/`snow_image_core_tests` 的 HEVC 编码断言需核对 vcpkg libheif(hevc) 的编码后端是否真的可用。
4. **托盘/热键/自启/通知**(P2-T2/T3/T4 的【VM】项,代码已在):启动后确认 KDE 托盘图标、portal 热键授权、`~/.config/autostart/snow_shot.desktop` 生效。

## 5. 未完成项与下一会话起点

1. **CI 终判**:run 41127295313 证明 CI 编译+链接全绿(gcc-13 的 subobject-linkage 批次已修);Stage AppDir 的 qt bin 解析 bug 已修(d420c2da),由 run 41137556133 终判。红了按 log-failed 继续。
2. **P1-T1**(viewer 平台后端)是 P0-GATE 后第一张功能卡;P1-T2 的 `scripts/package-linux-dev.sh` 未建。
3. 欠账清单:snow-recording-export 6 个 Linux 既有测试失败(键盘渲染 Win-only ×3、muxer 全量注册、ffmpeg_util rgba_copy ×2,已用 stash 对照确认非本轮引入);vcpkg ffmpeg muxer 白名单问题(P5-T7);AppImage 的 qt 插件适配。
4. 本会话新增的构建环境事实(下一会话直接复用):Qt6_DIR=/usr/lib/cmake/Qt6;并行 -j6;ccache 已挂;sudo 不可用;~/.local/bin 有自编译 zip 3.0。

## 6. CI 诊断结论与本轮修复

- 数据源:gh run list + log-failed(evidence/ci-diagnosis.md,10 轮全轨迹)。
- 结论:前 7 轮 = 环境缺失(aqt 参数、exec bit、nasm、libdrm、GL/Vulkan dev 头);后 3 轮 = GCC 严格警告;**没有真实代码缺陷类失败**。
- 本轮修复并推送的 CI 阻塞问题:`snowimagecodecbackend.cpp:1408` 的 `-Werror=extra`(枚举/uint32 三元混用)——即 run 40819132985 的唯一 error。
- 本会话推送的 8 个提交(044c761a→78a48e78)涵盖:SIGPIPE 探测修复、snow-linux crate、rust 1.99 lint 迁移、GCC 16 全量警告清理、linux 平台源挂接、打包链修复。**推送后 CI 尚未跑完,结果待确认**(下一会话先 `gh run list --branch port/linux --limit 1`)。

## 7. 磁盘使用

- 会话起始 /home 可用 73G;收尾时 **39G**(debug 构建树 + cargo target 是主要增量)。
- 清理动作:bootstrap 全程 `--clean-after-build`(vcpkg buildtrees 峰值仅 109M,现 44M);无 OOM/写满事件。
- 建议下一会话开始时若 <15G:删 `build/linux-gcc-debug` 下无用的测试中间产物或整树重配(release preset 产物小得多)。

## 8. 事实边界声明

- "编译绿"= 本机增量构建 783/783 链接成功,有日志;**不代表** `--clean-first` 干净构建绿、不代表 CI 绿、不代表运行时可用。
- "打包产出"= makepkg 退出 0 且 .pkg.tar.zst 存在(127MB);**未经**安装验证、未经启动验证(尝试被中断)。
- "93% 单测通过"= ctest -L unit 一次性结果;57 个失败未逐一归因,不能据此断言功能完好。
