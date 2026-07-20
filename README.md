# Codex Windows Unified Patch

一个面向 Windows 商店版 ChatGPT / Codex 桌面应用的非官方、可回滚补丁工具集。

它会保留 Microsoft Store 原版作为更新来源，在 `%LOCALAPPDATA%` 下生成独立运行副本，并提供一个稳定启动入口。当前功能包括：

- 补齐顶部原生菜单和托盘菜单的简体中文翻译；
- 让长文本保持在编辑框中，而不是自动转换成文本附件；
- 让本地副本采用官方 AppUserModelID，与官方任务栏图标分组；
- 自动检测商店版本变化，并为新版本重新生成联合副本；
- 校验 ASAR、外置原生模块和补丁唯一目标；
- 保留官方底包、中文单独版和旧版本，支持状态检查与回滚。

> [!IMPORTANT]
> 本项目与 OpenAI 无关，也不包含或分发 ChatGPT / Codex 的程序文件、资源、账户数据或访问凭据。脚本只处理用户本人已经安装的本地商店包。

## 要求

- Windows 11；
- 已从 Microsoft Store 安装 ChatGPT / Codex；
- PowerShell 7；
- Node.js 22.12 或更高版本，以及可用的 `npx`；
- 首次安装和商店版本更新后的首次启动需要额外磁盘空间与一些处理时间。

## 安装

下载或克隆本仓库，在 PowerShell 7 中运行：

```powershell
pwsh -NoProfile -File .\Install-Codex-Unified.ps1 -Action Install
```

三个 `.ps1` 文件应放在同一个目录中。安装成功后：

1. 完全退出当前 ChatGPT / Codex；
2. 双击桌面的 `ChatGPT`；
3. 如需让任务栏固定项在冷启动时也打开联合版，取消固定旧项，然后在开始菜单中固定“ChatGPT 联合版”。

商店原版不会被修改或卸载。它仍然负责正常更新；稳定启动器检测到新版本时会重新构建联合副本。若新版结构不再满足唯一、安全的补丁条件，构建会停止并继续保留上一个可用版本。

## 状态与移除

查看状态：

```powershell
pwsh -NoProfile -File .\Install-Codex-Unified.ps1 -Action Status
```

只重建桌面和开始菜单入口：

```powershell
pwsh -NoProfile -File .\Install-Codex-Unified.ps1 -Action RefreshShortcuts
```

移除联合副本并恢复安装前的快捷方式：

```powershell
pwsh -NoProfile -File .\Install-Codex-Unified.ps1 -Action Remove
```

移除操作不会卸载商店原版，也不会删除 `CODEX_HOME`、任务、账户或浏览器用户数据。

## 工作方式

`Install-Codex-Chinese-Menu.ps1` 从已安装商店包复制应用运行时，解包 `app.asar`，补充中文菜单、动态托盘菜单和官方 AppUserModelID，再按官方的 `app.asar.unpacked` 文件清单重新打包并逐文件校验。

`codex-long-paste-patch.ps1` 在 Web 界面脚本中寻找唯一的 `addPastedTextHandler(...)` 功能门控，以等字节长度方式关闭自动附件处理，并更新 ASAR 中相应的 SHA-256 完整性数据。

`Install-Codex-Unified.ps1` 负责串联两项补丁、生成稳定启动器、跟随商店版本、写入快捷方式身份并保留回滚材料。

## 已知限制

- 补丁依赖应用内部结构，商店新版可能需要更新匹配规则；
- 已经固定的官方 MSIX 任务栏项在没有窗口运行时仍可能冷启动原版，需要按上文重新固定“ChatGPT 联合版”；
- 脚本不会自动删除旧版本副本，以免在尚未验收新版本时丢失可用回退点；
- 真实界面效果仍应在每个新应用版本首次构建后人工确认一次。

## 安全边界

- 不修改 `C:\Program Files\WindowsApps`；
- 不停止、重启或注入正在运行的 ChatGPT / Codex；
- 补丁目标不唯一、语法检查失败、原生模块清单变化或哈希校验失败时停止安装；
- 不收集遥测，不上传本地文件，也不读取账户凭据。

## License

本项目脚本采用 [MIT License](LICENSE)。OpenAI、ChatGPT、Codex 及其相关名称和资产归各自权利人所有。
