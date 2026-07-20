[CmdletBinding()]
param(
    [ValidateSet('Install', 'Status', 'Remove')]
    [string]$Action = 'Install',

    [string]$PatchRoot = (Join-Path $env:LOCALAPPDATA 'CodexChineseMenu'),

    [switch]$SkipDesktopShortcut,

    [string]$AppUserModelId
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Utf8NoBom = [Text.UTF8Encoding]::new($false)
$PatchMarker = '__codexChineseMenuPatchV2'
$AppIdentityMarker = '__codexOfficialAppUserModelId'

$MenuTranslations = [ordered]@{
    'File' = '文件'
    'Edit' = '编辑'
    'View' = '查看'
    'Window' = '窗口'
    'Help' = '帮助'
    'New Window' = '新建窗口'
    'New Chat' = '新建对话'
    'New standalone chat' = '新建独立对话'
    'Open Folder…' = '打开文件夹…'
    'Close' = '关闭'
    'Close Window' = '关闭窗口'
    'Settings…' = '设置…'
    'Quit' = '退出'
    'Exit' = '退出'
    'Quit ChatGPT' = '退出 ChatGPT'
    'Exit ChatGPT' = '退出 ChatGPT'
    'Archive chat' = '归档对话'
    'Copy conversation path' = '复制对话路径'
    'Copy deeplink' = '复制深层链接'
    'Copy session id' = '复制会话 ID'
    'Copy working directory' = '复制工作目录'
    'Find' = '查找'
    'Focus Browser Address Bar' = '聚焦浏览器地址栏'
    'Force Reload Browser Page' = '强制重新加载浏览器页面'
    'Back' = '后退'
    'Forward' = '前进'
    'Next Chat' = '下一个对话'
    'Open Browser Tab' = '打开浏览器标签页'
    'Open command menu' = '打开命令菜单'
    'Process Manager' = '进程管理器'
    'Previous Chat' = '上一个对话'
    'Reload Browser Page' = '重新加载浏览器页面'
    'Rename chat' = '重命名对话'
    'Search Chats…' = '搜索对话…'
    'Search Files…' = '搜索文件…'
    'Keyboard Shortcuts' = '键盘快捷键'
    'Toggle Bottom Panel' = '切换底部面板'
    'Toggle Browser Panel' = '切换浏览器面板'
    'Toggle File Tree' = '切换文件树'
    'Toggle Pinned Summary' = '切换置顶摘要'
    'Toggle Sidebar' = '切换边栏'
    'Toggle Review Panel' = '切换审阅面板'
    'Open Terminal' = '打开终端'
    'Pin/unpin chat' = '置顶/取消置顶对话'
    'Start Trace Recording' = '开始跟踪记录'
    'Stop Trace Recording' = '停止跟踪记录'
    'Start Performance Trace' = '开始性能跟踪'
    'Stop Performance Trace' = '停止性能跟踪'
    'Actual Size' = '实际大小'
    'Browser Back' = '浏览器后退'
    'Browser Forward' = '浏览器前进'
    'Check for Updates…' = '检查更新…'
    'Documentation' = '文档'
    'Find Next' = '查找下一个'
    'Find Previous' = '查找上一个'
    'Log Out' = '退出登录'
    'Open Deeplink from Clipboard' = '从剪贴板打开深层链接'
    'Reload Window' = '重新加载窗口'
    'Send Feedback' = '发送反馈'
    'System Status' = '系统状态'
    'Toggle Debug Menu' = '切换调试菜单'
    'Toggle Full Screen' = '切换全屏'
    'Toggle Query Devtools' = '切换查询开发者工具'
    'Toggle React Scan' = '切换 React 扫描'
    'Troubleshooting' = '疑难解答'
    "What's New" = '新增功能'
    'Zoom In' = '放大'
    'Zoom Out' = '缩小'
    'Undo' = '撤销'
    'Redo' = '重做'
    'Cut' = '剪切'
    'Copy' = '复制'
    'Paste' = '粘贴'
    'Paste and Match Style' = '粘贴并匹配样式'
    'Delete' = '删除'
    'Select All' = '全选'
    'Toggle Developer Tools' = '切换开发者工具'
    'Minimize' = '最小化'
    'Resume Chronicle' = '恢复 Chronicle'
    'Pause Chronicle' = '暂停 Chronicle'
    'Starting Chronicle...' = '正在启动 Chronicle…'
    'Stopping Chronicle...' = '正在停止 Chronicle…'
}

$NativeStrings = [ordered]@{
    'computerUseOverlay.usingComputer' = 'ChatGPT 正在使用你的电脑'
    'computerUseOverlay.escToCancel' = '按 Esc 取消'
    'electron.appMenu.help.systemStatus' = '系统状态'
    'codex.commandMenuTitle.archiveThread' = '归档对话'
    'codex.commandMenuTitle.closeWindow' = '关闭'
    'codex.commandMenuTitle.copyConversationPath' = '复制对话路径'
    'codex.commandMenuTitle.copyDeeplink' = '复制深层链接'
    'codex.commandMenuTitle.copySessionId' = '复制会话 ID'
    'codex.commandMenuTitle.copyWorkingDirectory' = '复制工作目录'
    'codex.commandMenuTitle.findInThread' = '查找'
    'codex.commandMenuTitle.focusBrowserAddressBar' = '聚焦浏览器地址栏'
    'codex.commandMenuTitle.hardReloadBrowserPage' = '强制重新加载浏览器页面'
    'codex.commandMenuTitle.navigateBack' = '后退'
    'codex.commandMenuTitle.navigateForward' = '前进'
    'codex.commandMenuTitle.newProjectlessTask' = '新建独立对话'
    'codex.commandMenuTitle.newThread' = '新建对话'
    'codex.commandMenuTitle.newWindow' = '新建窗口'
    'codex.commandMenuTitle.nextThread' = '下一个对话'
    'codex.commandMenuTitle.openBrowserTab' = '打开浏览器标签页'
    'codex.commandMenuTitle.openCommandMenu' = '打开命令菜单'
    'codex.commandMenuTitle.openFolder' = '打开文件夹…'
    'codex.commandMenuTitle.openProcessManager' = '进程管理器'
    'codex.commandMenuTitle.previousThread' = '上一个对话'
    'codex.commandMenuTitle.reloadBrowserPage' = '重新加载浏览器页面'
    'codex.commandMenuTitle.renameThread' = '重命名对话'
    'codex.commandMenuTitle.searchChats' = '搜索对话…'
    'codex.commandMenuTitle.searchFiles' = '搜索文件…'
    'codex.commandMenuTitle.settings' = '设置…'
    'codex.commandMenuTitle.showKeyboardShortcuts' = '键盘快捷键'
    'codex.commandMenuTitle.toggleBottomPanel' = '切换底部面板'
    'codex.commandMenuTitle.toggleBrowserPanel' = '切换浏览器面板'
    'codex.commandMenuTitle.toggleFileTreePanel' = '切换文件树'
    'codex.commandMenuTitle.togglePinnedSummary' = '切换置顶摘要'
    'codex.commandMenuTitle.toggleSidebar' = '切换边栏'
    'codex.commandMenuTitle.toggleReviewPanel' = '切换审阅面板'
    'codex.commandMenuTitle.toggleTerminal' = '打开终端'
    'codex.commandMenuTitle.toggleThreadPin' = '置顶/取消置顶对话'
    'codex.commandMenuTitle.toggleTraceRecording' = '开始跟踪记录'
    'trayMenu.openApp' = '打开 {appName}'
    'trayMenu.newChat' = '新建对话'
    'trayMenu.pinnedThreads' = '已置顶'
    'trayMenu.runningThreads' = '运行中'
    'trayMenu.recentThreads' = '最近'
    'trayMenu.unreadThreads' = '未读'
    'trayMenu.more' = '更多'
    'trayMenu.projectlessThreads' = '对话'
}

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path)
}

function Assert-PathUnderRoot([string]$Path, [string]$Root) {
    $fullPath = (Get-FullPath $Path).TrimEnd('\')
    $fullRoot = (Get-FullPath $Root).TrimEnd('\')
    if (-not $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing operation outside patch root: $fullPath"
    }
}

function Invoke-Native([string]$FilePath, [string[]]$ArgumentList) {
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Asar([string[]]$ArgumentList) {
    Invoke-Native 'npx' (@('--yes', '@electron/asar') + $ArgumentList)
}

function Get-FileHashMap([string]$Root) {
    $map = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
        $map[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $map
}

function Assert-SameFileTree([string]$ExpectedRoot, [string]$ActualRoot) {
    if (-not (Test-Path -LiteralPath $ExpectedRoot -PathType Container)) {
        throw "Expected unpacked directory is missing: $ExpectedRoot"
    }
    if (-not (Test-Path -LiteralPath $ActualRoot -PathType Container)) {
        throw "Repacked unpacked directory is missing: $ActualRoot"
    }

    $expected = Get-FileHashMap $ExpectedRoot
    $actual = Get-FileHashMap $ActualRoot
    if ($expected.Count -ne $actual.Count) {
        throw "Unpacked file count changed: expected $($expected.Count), got $($actual.Count)"
    }
    foreach ($key in $expected.Keys) {
        if (-not $actual.ContainsKey($key) -or $actual[$key] -ne $expected[$key]) {
            throw "Unpacked file mismatch: $key"
        }
    }
}

function Patch-MainMenu([string]$MainPath) {
    $text = [IO.File]::ReadAllText($MainPath)
    if ($text.Contains($PatchMarker, [StringComparison]::Ordinal)) {
        return
    }

    $pattern = '(?<call>(?<receiver>[A-Za-z_$][A-Za-z0-9_$]*)\.Menu\.setApplicationMenu\((?<menu>[A-Za-z_$][A-Za-z0-9_$]*)\))'
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected one application-menu install call, found $($matches.Count); no patch was applied."
    }

    $match = $matches[0]
    $menuVariable = $match.Groups['menu'].Value
    $receiver = $match.Groups['receiver'].Value
    $translationJson = $MenuTranslations | ConvertTo-Json -Compress
    $injection = '(()=>{const ' + $PatchMarker + '=' + $translationJson +
        ';const __walk=e=>{for(const t of e.items??[]){const e=(t.label??``).replaceAll(`&`,``);t.label=' +
        $PatchMarker + '[e]??t.label,t.submenu&&__walk(t.submenu)}};const __build=' + $receiver +
        '.Menu.buildFromTemplate.bind(' + $receiver + '.Menu);' + $receiver +
        '.Menu.buildFromTemplate=(...e)=>{const t=__build(...e);return __walk(t),t};__walk(' + $menuVariable + ')})(),'

    $patched = $text.Substring(0, $match.Index) + $injection + $match.Value +
        $text.Substring($match.Index + $match.Length)
    [IO.File]::WriteAllText($MainPath, $patched, $Utf8NoBom)
}

function Patch-NativeLocale([string]$LocalePath) {
    $locale = Get-Content -LiteralPath $LocalePath -Raw | ConvertFrom-Json
    foreach ($entry in $NativeStrings.GetEnumerator()) {
        $locale | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value -Force
    }
    $json = $locale | ConvertTo-Json -Compress -Depth 10
    [IO.File]::WriteAllText($LocalePath, $json, $Utf8NoBom)
}

function Patch-AppIdentity([string]$BuildRoot, [string]$Identity) {
    if (-not $Identity) { return $null }
    $buildFiles = @(Get-ChildItem -LiteralPath $BuildRoot -Filter '*.js' -File)
    foreach ($file in $buildFiles) {
        $existingText = [IO.File]::ReadAllText($file.FullName)
        if ($existingText.Contains($AppIdentityMarker, [StringComparison]::Ordinal)) {
            return $file.Name
        }
    }

    $pattern = '(?<receiver>[A-Za-z_$][A-Za-z0-9_$]*)\.app\.setAppUserModelId\((?<argument>[A-Za-z_$][A-Za-z0-9_$]*\.[A-Za-z_$][A-Za-z0-9_$]*\([^)]*\)|[^)]*)\)'
    $targets = @()
    foreach ($file in $buildFiles) {
        $text = [IO.File]::ReadAllText($file.FullName)
        foreach ($match in [regex]::Matches($text, $pattern)) {
            $targets += [pscustomobject]@{ File = $file; Text = $text; Match = $match }
        }
    }
    if ($targets.Count -ne 1) {
        throw "Expected one AppUserModelID assignment, found $($targets.Count); no identity patch was applied."
    }

    $target = $targets[0]
    $text = $target.Text
    $match = $target.Match
    $receiver = $match.Groups['receiver'].Value
    $identityJson = $Identity | ConvertTo-Json -Compress
    $replacement = $receiver + '.app.setAppUserModelId(' + $identityJson + '/*' + $AppIdentityMarker + '*/)'
    $patched = $text.Substring(0, $match.Index) + $replacement +
        $text.Substring($match.Index + $match.Length)
    [IO.File]::WriteAllText($target.File.FullName, $patched, $Utf8NoBom)
    return $target.File.Name
}

function Get-CodexPackage {
    $packages = @(
        Get-AppxPackage | Where-Object {
            $appRoot = Join-Path $_.InstallLocation 'app'
            (Test-Path -LiteralPath (Join-Path $appRoot 'resources\app.asar') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $appRoot 'ChatGPT.exe') -PathType Leaf)
        }
    )
    $package = $packages | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $package) {
        throw 'No installed Codex/ChatGPT package was found.'
    }
    return $package
}

function Write-LauncherAndShortcut(
    $Package,
    [string]$PatchedApp,
    [string]$VersionRoot,
    [switch]$SkipShortcut
) {
    $appExe = Join-Path $PatchedApp 'ChatGPT.exe'
    $cliExe = Join-Path $PatchedApp 'resources\codex.exe'
    $packageUserData = Join-Path $env:LOCALAPPDATA "Packages\$($Package.PackageFamilyName)\LocalCache\Roaming\Codex\web\Codex"
    $userData = if (Test-Path -LiteralPath $packageUserData -PathType Container) {
        $packageUserData
    } else {
        Join-Path $PatchRoot 'electron-user-data'
    }

    $launcher = Join-Path $VersionRoot 'Launch-Codex-Chinese-Menu.vbs'
    $vbs = @"
Option Explicit
Dim shell, env
Set shell = CreateObject("WScript.Shell")
Set env = shell.Environment("PROCESS")
env("CODEX_HOME") = "$env:USERPROFILE\.codex"
env("CODEX_ELECTRON_USER_DATA_PATH") = "$userData"
env("CODEX_CLI_PATH") = "$cliExe"
shell.Run Chr(34) & "$appExe" & Chr(34) & " --lang=zh-CN", 0, False
"@
    [IO.File]::WriteAllText($launcher, $vbs, [Text.Encoding]::ASCII)

    $shortcutPath = $null
    if (-not $SkipShortcut) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $shortcutPath = Join-Path $desktop 'ChatGPT 中文菜单.lnk'
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $shortcut.Arguments = '"' + $launcher + '"'
        $shortcut.WorkingDirectory = $VersionRoot
        $shortcut.Description = 'Codex / ChatGPT Chinese native menu launcher'

        $officialShortcut = Join-Path $desktop 'ChatGPT.lnk'
        if (Test-Path -LiteralPath $officialShortcut -PathType Leaf) {
            $official = $wsh.CreateShortcut($officialShortcut)
            if ($official.IconLocation -and (Test-Path -LiteralPath ($official.IconLocation -replace ',\d+$', '') -PathType Leaf)) {
                $shortcut.IconLocation = $official.IconLocation
            }
        }
        if (-not $shortcut.IconLocation) {
            $shortcut.IconLocation = "$appExe,0"
        }
        $shortcut.Save()
    }

    return [pscustomobject]@{
        Launcher = $launcher
        Shortcut = $shortcutPath
        UserData = $userData
    }
}

$fullPatchRoot = Get-FullPath $PatchRoot
$allowedBase = (Get-FullPath $env:LOCALAPPDATA).TrimEnd('\') + '\'
if (-not $fullPatchRoot.StartsWith($allowedBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Patch root must remain under LOCALAPPDATA: $fullPatchRoot"
}

if ($Action -eq 'Remove') {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ChatGPT 中文菜单.lnk'
    if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
        Remove-Item -LiteralPath $shortcutPath -Force
    }
    if (Test-Path -LiteralPath $fullPatchRoot -PathType Container) {
        Remove-Item -LiteralPath $fullPatchRoot -Recurse -Force
    }
    Write-Host 'Removed the local Chinese-menu runtime and shortcut.'
    return
}

$package = Get-CodexPackage
$versionRoot = Join-Path $fullPatchRoot ([string]$package.Version)
$patchedApp = Join-Path $versionRoot 'app'
$patchedAsar = Join-Path $patchedApp 'resources\app.asar'
$markerPath = Join-Path $versionRoot 'patch-status.json'

if ($Action -eq 'Status') {
    [pscustomobject]@{
        InstalledPackageVersion = [string]$package.Version
        PatchedRuntimeExists = Test-Path -LiteralPath $patchedAsar -PathType Leaf
        MarkerExists = Test-Path -LiteralPath $markerPath -PathType Leaf
        ShortcutExists = Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ChatGPT 中文菜单.lnk') -PathType Leaf
        PatchRoot = $fullPatchRoot
    } | Format-List
    return
}

New-Item -ItemType Directory -Force -Path $versionRoot | Out-Null
$sourceApp = Join-Path $package.InstallLocation 'app'
if (-not (Test-Path -LiteralPath $patchedAsar -PathType Leaf)) {
    if (Test-Path -LiteralPath $patchedApp) {
        Assert-PathUnderRoot $patchedApp $fullPatchRoot
        Remove-Item -LiteralPath $patchedApp -Recurse -Force
    }
    Write-Host "Copying Codex $($package.Version) to the reversible local runtime..."
    Copy-Item -LiteralPath $sourceApp -Destination $patchedApp -Recurse -Force
}

$officialBackup = "$patchedAsar.official"
if (-not (Test-Path -LiteralPath $officialBackup -PathType Leaf)) {
    Copy-Item -LiteralPath $patchedAsar -Destination $officialBackup -Force
}

$staging = Join-Path $fullPatchRoot "staging-$PID"
Assert-PathUnderRoot $staging $fullPatchRoot
if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $staging | Out-Null

try {
    Write-Host 'Extracting the application archive...'
    # ASAR resolves unpacked native modules from a sibling named app.asar.unpacked,
    # so extract from the working copy while retaining the separately named backup.
    Invoke-Asar @('extract', $patchedAsar, $staging)

    $mainFiles = @(Get-ChildItem -LiteralPath (Join-Path $staging '.vite\build') -Filter 'main-*.js' -File)
    if ($mainFiles.Count -ne 1) {
        throw "Expected one main application bundle, found $($mainFiles.Count)."
    }
    $mainFile = $mainFiles[0]
    $localeFile = Join-Path $staging 'native-menu-locales\zh-CN.json'
    if (-not (Test-Path -LiteralPath $localeFile -PathType Leaf)) {
        throw "Chinese native locale file is missing: $localeFile"
    }

    Patch-MainMenu $mainFile.FullName
    Patch-NativeLocale $localeFile
    $identityBundle = Patch-AppIdentity (Join-Path $staging '.vite\build') $AppUserModelId
    Invoke-Native 'node' @('--check', $mainFile.FullName)
    if ($identityBundle) {
        Invoke-Native 'node' @('--check', (Join-Path $staging ".vite\build\$identityBundle"))
    }

    $newAsar = "$patchedAsar.new"
    $newUnpacked = "$newAsar.unpacked"
    if (Test-Path -LiteralPath $newAsar) { Remove-Item -LiteralPath $newAsar -Force }
    if (Test-Path -LiteralPath $newUnpacked) { Remove-Item -LiteralPath $newUnpacked -Recurse -Force }

    Write-Host 'Repacking and validating the localized runtime...'
    $originalUnpacked = "$patchedAsar.unpacked"
    $unpackedPaths = @(
        Get-ChildItem -LiteralPath $originalUnpacked -Recurse -File -Force |
            ForEach-Object { $_.FullName.Substring($originalUnpacked.Length + 1).Replace('\', '/') }
    )
    if ($unpackedPaths.Count -eq 0) {
        throw 'The original ASAR has no unpacked native-module file list.'
    }
    # @electron/asar matches --unpack against each absolute source filename.
    # Use exact, slash-normalized staging paths so only the files that were
    # unpacked by the official archive are unpacked again.
    $unpackedAbsolutePaths = @(
        $unpackedPaths | ForEach-Object {
            (Join-Path $staging $_).Replace('\', '/')
        }
    )
    $unpackExpression = if ($unpackedAbsolutePaths.Count -eq 1) {
        $unpackedAbsolutePaths[0]
    } else {
        '{' + ($unpackedAbsolutePaths -join ',') + '}'
    }
    Invoke-Asar @(
        'pack', $staging, $newAsar,
        '--unpack', $unpackExpression
    )

    Assert-SameFileTree "$patchedAsar.unpacked" $newUnpacked
    $archiveList = @(Invoke-Asar @('list', $newAsar))
    $mainEntry = '\.vite\build\' + $mainFile.Name
    $identityEntry = if ($identityBundle) { '\.vite\build\' + $identityBundle } else { $null }
    if ($archiveList -notcontains $mainEntry -or
        $archiveList -notcontains '\native-menu-locales\zh-CN.json' -or
        ($identityEntry -and $archiveList -notcontains $identityEntry)) {
        throw 'The repacked archive is missing a required localized file.'
    }

    Remove-Item -LiteralPath $newUnpacked -Recurse -Force
    Move-Item -LiteralPath $newAsar -Destination $patchedAsar -Force

    $verifyDir = Join-Path $fullPatchRoot "verify-$PID"
    Assert-PathUnderRoot $verifyDir $fullPatchRoot
    New-Item -ItemType Directory -Force -Path $verifyDir | Out-Null
    try {
        Push-Location $verifyDir
        Invoke-Asar @('extract-file', $patchedAsar, ".vite\build\$($mainFile.Name)")
        Invoke-Asar @('extract-file', $patchedAsar, 'native-menu-locales\zh-CN.json')
        if ($identityBundle) {
            Invoke-Asar @('extract-file', $patchedAsar, ".vite\build\$identityBundle")
        }
        Pop-Location
        $verifiedMain = Join-Path $verifyDir $mainFile.Name
        $verifiedLocale = Join-Path $verifyDir 'zh-CN.json'
        if (-not ([IO.File]::ReadAllText($verifiedMain).Contains($PatchMarker, [StringComparison]::Ordinal))) {
            throw 'The localized application-menu marker was not found after repacking.'
        }
        if ($identityBundle) {
            $verifiedIdentity = Join-Path $verifyDir $identityBundle
            if (-not ([IO.File]::ReadAllText($verifiedIdentity).Contains($AppIdentityMarker, [StringComparison]::Ordinal))) {
                throw 'The AppUserModelID marker was not found after repacking.'
            }
            Invoke-Native 'node' @('--check', $verifiedIdentity)
        }
        $verifiedStrings = Get-Content -LiteralPath $verifiedLocale -Raw | ConvertFrom-Json
        if ($verifiedStrings.'computerUseOverlay.usingComputer' -ne 'ChatGPT 正在使用你的电脑') {
            throw 'The Chinese locale verification failed after repacking.'
        }
    } finally {
        if ((Get-Location).Path -eq $verifyDir) { Pop-Location }
        if (Test-Path -LiteralPath $verifyDir) { Remove-Item -LiteralPath $verifyDir -Recurse -Force }
    }

    $launchInfo = Write-LauncherAndShortcut $package $patchedApp $versionRoot -SkipShortcut:$SkipDesktopShortcut
    $status = [ordered]@{
        schemaVersion = 1
        packageVersion = [string]$package.Version
        sourcePackageFullName = $package.PackageFullName
        sourceAsarSha256 = (Get-FileHash -LiteralPath $officialBackup -Algorithm SHA256).Hash.ToLowerInvariant()
        patchedAsarSha256 = (Get-FileHash -LiteralPath $patchedAsar -Algorithm SHA256).Hash.ToLowerInvariant()
        mainBundle = $mainFile.Name
        menuTranslationCount = $MenuTranslations.Count
        nativeStringCount = $NativeStrings.Count
        appUserModelId = $AppUserModelId
        appIdentityBundle = $identityBundle
        installedAt = [DateTimeOffset]::Now.ToString('o')
        shortcut = $launchInfo.Shortcut
        userData = $launchInfo.UserData
    }
    [IO.File]::WriteAllText($markerPath, ($status | ConvertTo-Json -Depth 5), $Utf8NoBom)

    Write-Host ''
    Write-Host "Installed localized runtime: $patchedApp"
    Write-Host "Desktop shortcut: $($launchInfo.Shortcut)"
    Write-Host 'The official Store package was not modified.'
} finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}
