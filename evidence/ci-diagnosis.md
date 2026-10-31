# CI 诊断(Phase A, 2026-10-29)

数据源:`gh run list --branch port/linux --limit 6` + `gh run view <id> --log-failed`。
分类标准:**环境缺失** = runner 缺系统包/工具;**警告升级** = 上游代码在 GCC 严格警告下报错,非逻辑缺陷;**真实代码缺陷** = 逻辑错误。

## 全部失败 run 轨迹(10 轮,含 §9.3 的 9 轮 + 本轮新发现)

| # | Run ID | 耗时 | 失败点 | 分类 | 根因 / 修复(已推送 commit) |
|---|---|---|---|---|---|
| 1 | 40786618253 | 35s | Install Qt | 环境缺失 | aqt `--archives` 短名与 6.12.0 linux 元数据不匹配 → 去掉 --archives |
| 2 | 40790619775 | 1m23s | Install Qt | 环境缺失 | 同上(默认安装仍报) → 根因是 6.12.0 desktop arch 名改 `linux_gcc_64`(b2a309d1) |
| 3 | 40787068806 | 9min | Install Qt | 环境缺失 | 解压目录仍叫 `gcc_64` → QT_ROOT 保持 `gcc_64`(980dd570) |
| 4 | 40788378953 | 8min | Configure 脚本 | 环境缺失 | Windows 检出不保留 exec bit → `git update-index --chmod=+x`(09abf292) |
| 5 | 40789390464 | 56s | Configure(vcpkg) | 环境缺失 | x265 端口需要 nasm,Linux vcpkg 不自动下载 → workflow apt 加 nasm(d31acce1) |
| 6 | 40791527334 | 14min | Configure(vcpkg) | 环境缺失 | libva port 需要系统 libdrm-dev(meson 探测失败)→ vaapi 从 snow-linux-media 移除,P5-T3 再加回(d9b0a1ed);vcpkg 其余 34 端口全绿 ✔ |
| 7 | 40793894220 | 40min | Configure(CMake) | 环境缺失 | aqt Qt 在干净 CI 需要 GL/Vulkan/X11 dev 头(Qt6GuiConfig 存在但 Qt6_FOUND=FALSE)→ apt 加 libgl1-mesa-dev 等 11 个包(20469112) |
| 8 | 40815981782 | 26min | 编译 | 警告升级 | GCC 特有 `-Werror=missing-declarations` / `-Werror=shadow`(ant_design_qt/snow_image 首批)→ ProjectWarnings.cmake GNU 分支暂不启用这两类(cb78efe9) |
| 9 | **40819132985**(本轮诊断对象) | 40m46s | 编译 | **警告升级** | `snow_shot/src/image/snowimagecodecbackend.cpp:1408:32: error: enumerated and non-enumerated type in conditional expression [-Werror=extra]`。三元 `decoded ? SNOW_SHOT_IMAGE_CODEC_SKIN_ERROR_INVALID_IMAGE(枚举常量) : skinFailure(...)(返回 std::uint32_t)` 混用枚举与非枚举。全 run 仅此 1 个 error。修复:枚举常量加 `static_cast<std::uint32_t>`(本轮 Phase B 修复) |

注:表中 run 顺序按 gh 输出时间排列,§9.3 的编号与实际 run id 有出入(40786618253 与 40790619775 顺序),以 run id + 耗时为准,不影响分类结论。

## 关键结论

1. **vcpkg 35 端口在 ubuntu-24.04 全部编译通过**(run 40819132985 中 vcpkg 阶段完整走完并进入 C++ 编译)。
2. **Configure 阶段已全绿**:Qt 6.12.0 kit 解析、Rust FFI 工具链探测均通过。
3. 编译已推进到 709 个目标中的第 20+ 个(snow_image、ant_design_qt、snow_draw_engine_qt、snow_shot 部分源),唯一失败点即上表第 9 行的 1 个 GCC 警告。
4. 至今没有"真实代码缺陷"类失败;全部是环境缺失(前 7 轮)或 GCC 严格警告(第 8-9 轮)。
5. 预期后续失败点(§9.5-2):a) 更多 GCC `-Wextra` 警告(同类);b) Rust FFI 链接(ffmpeg pkg-config/libclang);c) 打包阶段(linuxdeploy/makepkg/appimagetool)。
6. 本机(CachyOS, gcc? 待确认版本)与 CI(ubuntu-24.04 gcc-13)的 GCC 警告行为可能有差异,本地验证时同样开 `SNOW_APPS_STRICT_COMPILE=ON`(preset 已带),能覆盖 CI 的警告集合;GCC 版本越新警告越严,本地更严是好事。

## 追加轮次(2026-10-31)

| Run ID | 耗时 | 失败点 | 分类 | 根因 / 修复 |
|---|---|---|---|---|
| 40978668164 | 42m39s | 编译(snow_shot_settings unity_3) | 警告升级 | gcc-13 特有 `-Wsubobject-linkage`:settingscustomwidget/settingspagewidget 的外部链接类成员引用全局匿名命名空间类型。GCC 16 不再报此警告(本地漏网)。修复:两个文件的相关类型提升出匿名 ns(329a62e1 的一部分,commit bbfec34f 后续) |
| 41127295313 | 1h15m | Stage AppDir | 环境缺失(脚本 bug) | 编译全过(subobject-linkage 修复生效)!我改的 qt bin 解析在 ubuntu(aqt kit,无 qmake6)上回退为空。修复:候选列表式解析(aqt $/../../bin → 系统 qmake6 → qmake),commit d420c2da。**注意:此 run 证明 CI 编译+链接全绿** |
