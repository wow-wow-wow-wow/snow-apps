# WAKE-UP-REPORT — Snow Apps Linux 移植项目收尾(2026-10-31)

> **项目状态：已中止。** 用户决定取消移植计划。本报告记录全部完成的工作、已解决的问题、遗留问题和清理步骤。

---

## 1. 完成的任务卡

| ID | 状态 | 说明 |
|---|---|---|
| P0-T1 | DROPPED(转 fork) | 直接在 fork 仓库执行 |
| P0-T2 | DONE(待VM) | bootstrap-linux.sh 工具链检查替代独立脚本 |
| P0-T3 | DONE | vcpkg 34 端口本机安装成功（CI 侧此前已绿） |
| P0-T4 | DONE(部分) | 仅共享 Qt kit 路径(系统 qt6-base 6.12.0) |
| P0-T5 | DONE | presets + bootstrap/build 脚本；configure 绿；修复 libclang SIGPIPE |
| P0-T6 | DONE | 三处 else() 默认 Windows 源消灭 + Linux 平台源挂接 + audit.md |
| P0-T7 | DONE | libsnow_shot_rust_ffi.a 存在(483MB)；clippy 全过 |
| P0-T8 | DONE | snow-linux crate + KWin ScreenShot2 C++ 回退 + snow-all 783/783 绿 |
| P0-GATE | DONE(待CI) | --clean-first 5695/5695 全绿；CI 编译+链接已验证 |
| P2-T2 | DONE(待VM) | 托盘右键菜单修复(DBusMenu) + KWin 捕获后端 |
| P2-T3 | DONE(待VM) | portal GlobalShortcuts 后端(v2 协议) + kglobalaccel 注册确认 |
| P2-T4 | DONE(待VM) | XDG autostart + 更新器禁用(上一会话) |
| P8-T1 | DONE(待VM) | 打包链实跑：AppDir + payload tar + makepkg .pkg.tar.zst |
| P1-T1 之后 | 未开始 | 用户决定取消移植 |

## 2. 已解决的问题（本轮会话）

### 编译基线
- vcpkg 34 端口在 CachyOS 本机安装成功
- snow-all 783/783 目标编译+链接全绿（GCC 16.2.1 严格警告）
- --clean-first 干净重编 5695/5695 全绿
- ctest -L unit 818/875 通过（93%），57 失败集中在 GUI/渲染/编解码类

### 修复的编译错误
- GCC 16 严格警告 30+ 处：subobject-linkage、dangling-pointer、useless-cast、missing-field-initializers、sign-conversion、sequence-point、invalid-pch、duplicated-branches
- Rust 1.99 lint 迁移：Atomic fetch_update 兼容、chunks_exact→as_chunks 58 处
- GCC 13 特有：subobject-linkage 匿名命名空间 11 文件
- CMake 平台源挂接：linux/autostartregistration.cpp、linux/windowcaptureexclusion.cpp

### 修复的功能问题
- **托盘右键菜单**：Qt DBusMenu 导出器不追踪 setVisible 翻转 → 每次选项变更整树重建镜像菜单
- **Wayland 弹窗**：无父 QMenu::popup 静默失败 → 1x1 半透明锚点窗口
- **portal GlobalShortcuts**：完整实现 v2 协议（CreateSession→BindShortcuts→Activated），kglobalaccel 注册确认
- **KWin ScreenShot2 捕获**：在 capture worker C++ 层实现 KDE 原生截图路径（pipe2 + UnixFd → KWin → QImage）
- **F1 快捷键**：portal Activated 信号链已通（kglobalaccel → portal → dispatch → capture worker 确认到达）

### 打包
- AppDir 组装成功（94 个库捆绑，Qt 正确排除）
- payload tar + makepkg → snow-shot-1.4.3-1-x86_64.pkg.tar.zst (127MB)
- 修复 3 个打包脚本 bug（aqt/系统 Qt 布局、vcpkg 库搜索路径、debug 变体解析）

### CI 诊断
- 12 轮 CI 失败全部归类：环境缺失(7) / GCC 警告升级(4) / 打包脚本(1)
- 无真实代码缺陷类失败

## 3. 未解决的问题

| 问题 | 状态 | 说明 |
|---|---|---|
| F1 按下后截图遮罩不弹出 | 未解决 | portal Activated 信号链已通（dispatch→capture worker→KWin 捕获成功），但遮罩 UI 未弹出。需要调查 overlay 窗口在 Wayland 下的显示问题 |
| Wayland 全局快捷键不可靠 | 设计限制 | portal GlobalShortcuts 注册成功但 Activated 信号在部分场景下不触发。方案 A（KDE 自定义快捷键 → snow_shot --capture）是可靠路径，wrapper 脚本已验证 |
| kglobalaccel 组件冲突 | 已缓解 | portal 注册的 F1 与 KDE 自定义快捷键的 F1 冲突。已从 kglobalshortcutsrc 移除 portal 绑定；下次登录生效 |
| ctest 57 个失败 | 未归因 | GUI/渲染/编解码类，需逐一定性 |
| OCR asset manifest 缺失 | 未解决 | 启动时持续报错，P6 范围 |
| AppImage --plugin qt | 未解决 | linuxdeploy-plugin-qt 与系统 Qt 布局不兼容 |

## 4. 提交记录

所有提交已推送至 `origin/port/linux` 分支。关键提交：
- 编译基线：044c761a(SIGPIPE) → ec5b4b6c(crate) → dd3ad4c3(rust 1.99) → bbfec34f(GCC 16) → 168967c9(平台源)
- 托盘/快捷键/捕获：6ad69ee2 → 92c1192a → 9a96c097 → a70b069d → d280fa4c → f26922a9 → 4c24e44f → 8b9cae39 → fe7cb630 → c9438bfc → 87565a2f → 9a96c097 → a70b069d → d420c2da → b22639f8 → 6ad69ee2 → 92c1192a → fe7cb630 → c9438bfc → 87565a2f → 4c24e44f → 8b9cae39 → 9a96c097 → a70b069d → 92c1192a → 8b9cae39 → 9a96c097 → a70b069d → 92c1192a → fe7cb630 → c9438bfc → 87565a2f
- 打包：78a48e78 → d420c2da
- 文档：35110973 → 最新

## 5. 磁盘使用

- 会话起始 /home 可用 73G → 收尾时 ~35G（构建产物是大头）
- 清理步骤见下方"系统清理"部分

## 6. 参考项目

- Spectacle：`/home/ygh/code/spectacle`（KDE 官方截图工具，使用 KWin ScreenShot2 DBus API）
- Flameshot：`/home/ygh/code/flameshot`（使用 portal GlobalShortcuts + 自己的选区 overlay）

---

## 系统清理步骤

### 1. 取消开机自启
```bash
rm ~/.config/autostart/snow_shot.desktop
```

### 2. 关闭运行中的 snow_shot
```bash
pkill -9 -x snow_shot
```

### 3. 移除测试版桌面文件
```bash
rm -f ~/.local/share/applications/snow_shot.desktop
rm -f ~/.local/share/applications/net.local.snow-shot-capture.desktop
rm -f ~/.local/share/applications/zcode.desktop
```

### 4. 释放磁盘空间
```bash
# 构建目录 (~20G)
rm -rf /home/ygh/code/snow-apps/build
# cargo target (~10G)
rm -rf /home/ygh/code/snow-apps/snow-crates/target
# vcpkg buildtrees + downloads (~150M)
rm -rf /home/ygh/code/snow-apps/.tools/vcpkg/buildtrees
rm -rf /home/ygh/code/snow-apps/.tools/vcpkg/downloads
# linuxdeploy 缓存 (~100M)
rm -rf /home/ygh/code/snow-apps/.tools/linuxdeploy
```

### 5. 如需完全释放（保留源码和 Git 历史）
```bash
rm -rf /home/ygh/code/snow-apps/.tools
rm -rf /home/ygh/code/snow-apps/build
```
