# Scoop Arch Bucket

个人 Scoop bucket，收录常用软件与工具。

## 安装

```powershell
scoop bucket add Arch https://github.com/liarchgh/ArchBucket
```

添加后安装某个软件：`scoop install Arch/<app>`（见下表）。

## 软件列表

<!-- STATUS:START -->
> 维护状态于 2026-08-14 检查。

| 软件 | 安装命令 | 用途 | 维护状态 |
| --- | --- | --- | --- |
| AirtestIDE | `scoop install Arch/AirtestIDE` | 跨平台 UI 自动化测试 IDE（Airtest 官方） | 维护中（新版 1.2.17 待自动更新） |
| biliup-rs | `scoop install Arch/biliup-rs` | B站命令行投稿（支持多P）与视频下载工具 | 已归档 |
| ContextMenuManager | `scoop install Arch/ContextMenuManager` | Windows 右键菜单管理程序 | 停滞（2024-08 后无更新） |
| fennel | `scoop install Arch/fennel` | 一种 Lisp 方言编程语言，编译为 Lua | 维护中 |
| ghc | `scoop install Arch/ghc` | Haskell 函数式语言编译器与交互环境 | 维护中（新版 9.12.4 待自动更新） |
| keymousego | `scoop install Arch/keymousego` | 鼠标键盘录制与自动化操作（类似按键精灵） | 维护中 |
| pasteex | `scoop install Arch/pasteex` | 把剪贴板内容直接粘贴为文件 | 停滞（2022-03 后无更新） |
| vidupe | `scoop install Arch/vidupe` | 视频查重：按视频内容比对相似/重复，无视格式与压缩 | 停滞（2019-09 后无更新） |
<!-- STATUS:END -->

> 状态表由 `scripts/check-health.ps1 -UpdateReadme` 自动生成，GitHub Action「Update Status」定期刷新。

### 维护状态说明

- **维护中**：上游持续发布更新；「待自动更新」指新版已发布，将由 Excavator 自动升级 manifest。
- **停滞**：一年以上无提交或无新发布（版本本身仍可用）。
- **已归档**：上游仓库已归档（只读），版本可用但不再更新。

## 本地扩展（相对官方模板）

以下为相对 [ScoopInstaller/BucketTemplate](https://github.com/ScoopInstaller/BucketTemplate) 的本地新增/自定义，**同步模板时请保留**：

- `scripts/check-health.ps1` — 软件健康检查脚本（URL 存活 / checkver 版本比对 / 上游维护状态），`-UpdateReadme` 可自动刷新下方状态表
- `.github/workflows/update-status.yml` — 定期运行健康检查并自动更新 README 状态表（每周 + manifest 变更时 + 手动触发）
- `bucket/*.json` — 各软件 manifest（模板中仅含 `app-name.json.template`）
- `README.md` — 本仓库自述；`<!-- STATUS:START -->` ～ `<!-- STATUS:END -->` 状态区块由脚本自动生成，**勿删标记**

## Refs

[ScoopInstaller/BucketTemplate](https://github.com/ScoopInstaller/BucketTemplate)
