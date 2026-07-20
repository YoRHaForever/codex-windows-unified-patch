#requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet('Install', 'Status', 'RefreshShortcuts', 'Remove')]
    [string]$Action = 'Install',

    [string]$PatchRoot = (Join-Path $env:LOCALAPPDATA 'CodexUnifiedPatch'),

    [string]$ChineseMenuScript,

    [string]$LongPasteScript
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Utf8NoBom = [Text.UTF8Encoding]::new($false)
$LongPasteOriginalPattern = '(?<gate>[A-Za-z_$][A-Za-z0-9_$]*)&&(?<editor>[A-Za-z_$][A-Za-z0-9_$]*)\.addPastedTextHandler\((?<handler>[A-Za-z_$][A-Za-z0-9_$]*)\)'
$LongPastePatchedPattern = '!1\s*&&[A-Za-z_$][A-Za-z0-9_$]*\.addPastedTextHandler\([A-Za-z_$][A-Za-z0-9_$]*\)'

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path)
}

function Assert-PatchRoot([string]$Path) {
    $fullPath = Get-FullPath $Path
    $allowedBase = (Get-FullPath $env:LOCALAPPDATA).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($allowedBase, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Patch root must remain under LOCALAPPDATA: $fullPath"
    }
    return $fullPath
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
        throw 'No installed Codex/ChatGPT Store package was found.'
    }
    return $package
}

function Resolve-RequiredScript(
    [string]$RequestedPath,
    [string]$SiblingName,
    [string]$FallbackPath
) {
    $candidates = @()
    if ($RequestedPath) { $candidates += $RequestedPath }
    $candidates += (Join-Path $PSScriptRoot $SiblingName)
    if ($FallbackPath) { $candidates += $FallbackPath }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Required script was not found: $SiblingName"
}

function Invoke-PowerShellScript([string]$ScriptPath, [string[]]$Arguments) {
    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    & $pwsh -NoProfile -File $ScriptPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$ScriptPath failed with exit code $LASTEXITCODE"
    }
}

function Get-LongPastePatchState([string]$AsarPath) {
    $bytes = [IO.File]::ReadAllBytes($AsarPath)
    if ($bytes.Length -lt 16) { throw 'Invalid ASAR: header is too short.' }
    $headerSize = [BitConverter]::ToUInt32($bytes, 4)
    $jsonLength = [BitConverter]::ToUInt32($bytes, 12)
    if ($headerSize -lt 16 -or (16L + $jsonLength) -gt $bytes.Length) {
        throw 'Invalid ASAR header sizes.'
    }

    $headerJson = [Text.Encoding]::UTF8.GetString($bytes, 16, $jsonLength)
    $header = $headerJson | ConvertFrom-Json
    $assetFiles = $header.files.webview.files.assets.files
    if ($null -eq $assetFiles) { throw 'Could not find webview/assets in ASAR.' }

    $originalCount = 0
    $patchedCount = 0
    $matchingNames = [Collections.Generic.List[string]]::new()
    foreach ($property in $assetFiles.PSObject.Properties) {
        if ($property.Name -notlike '*.js') { continue }
        $entry = $property.Value
        if ($null -eq $entry.offset -or $null -eq $entry.size) { continue }
        $offset = 8L + [long]$headerSize + [long]$entry.offset
        $fileBytes = New-Object byte[] ([int]$entry.size)
        [Array]::Copy($bytes, $offset, $fileBytes, 0, $fileBytes.Length)
        $text = [Text.Encoding]::UTF8.GetString($fileBytes)
        $original = [regex]::Matches($text, $LongPasteOriginalPattern).Count
        $patched = [regex]::Matches($text, $LongPastePatchedPattern).Count
        if ($original -or $patched) {
            $matchingNames.Add($property.Name)
            $originalCount += $original
            $patchedCount += $patched
        }
    }

    return [pscustomobject]@{
        OriginalCount = $originalCount
        PatchedCount = $patchedCount
        MatchingNames = @($matchingNames)
    }
}

function Copy-DurableScript([string]$Source, [string]$Destination) {
    $sourceFull = Get-FullPath $Source
    $destinationFull = Get-FullPath $Destination
    if (-not $sourceFull.Equals($destinationFull, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $sourceFull -Destination $destinationFull -Force
    }
}

function Write-StableLaunchers([string]$Root) {
    $launcherPath = Join-Path $Root 'Launch-Codex-Unified.ps1'
    $launcherText = @'
#requires -Version 7.0

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$logDirectory = Join-Path $root 'logs'
$logPath = Join-Path $logDirectory 'launcher.log'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

function Write-LaunchLog([string]$Message) {
    $line = '{0:o} {1}' -f [DateTimeOffset]::Now, $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
}

function Get-CodexPackage {
    $packages = @(
        Get-AppxPackage | Where-Object {
            $appRoot = Join-Path $_.InstallLocation 'app'
            (Test-Path -LiteralPath (Join-Path $appRoot 'resources\app.asar') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $appRoot 'ChatGPT.exe') -PathType Leaf)
        }
    )
    return $packages | Sort-Object Version -Descending | Select-Object -First 1
}

function Test-UnifiedRuntime([string]$VersionRoot) {
    $statusPath = Join-Path $VersionRoot 'unified-status.json'
    $asarPath = Join-Path $VersionRoot 'app\resources\app.asar'
    $exePath = Join-Path $VersionRoot 'app\ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $asarPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        return $false
    }
    try {
        $status = Get-Content -Raw -LiteralPath $statusPath | ConvertFrom-Json
        if (-not $status.chineseMenuPatched -or -not $status.longPastePatched) { return $false }
        $actualHash = (Get-FileHash -LiteralPath $asarPath -Algorithm SHA256).Hash.ToLowerInvariant()
        return $actualHash -eq [string]$status.patchedAsarSha256
    } catch {
        return $false
    }
}

function Start-UnifiedRuntime([string]$VersionRoot) {
    $status = Get-Content -Raw -LiteralPath (Join-Path $VersionRoot 'unified-status.json') | ConvertFrom-Json
    $app = Join-Path $VersionRoot 'app'
    $exe = Join-Path $app 'ChatGPT.exe'
    $env:CODEX_HOME = Join-Path $env:USERPROFILE '.codex'
    if ($status.userData) {
        $env:CODEX_ELECTRON_USER_DATA_PATH = [string]$status.userData
    }
    $env:CODEX_CLI_PATH = Join-Path $app 'resources\codex.exe'
    Write-LaunchLog "Launching unified runtime $($status.packageVersion)."
    Start-Process -FilePath $exe -ArgumentList '--lang=zh-CN' -WorkingDirectory $app
}

function Start-StoreFallback {
    $entry = Get-StartApps | Where-Object { $_.Name -match 'ChatGPT|Codex' } | Select-Object -First 1
    if ($null -ne $entry) {
        Write-LaunchLog "Falling back to Store entry $($entry.AppID)."
        Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList "shell:AppsFolder\$($entry.AppID)"
    }
}

$mutex = [Threading.Mutex]::new($false, 'Local\CodexUnifiedPatchLauncher')
$acquired = $false
try {
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { return }

    $running = Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" |
        Where-Object { $_.CommandLine -notmatch '\s--type=' } |
        Select-Object -First 1
    if ($null -ne $running -and $running.ExecutablePath) {
        Write-LaunchLog "ChatGPT is already running from $($running.ExecutablePath)."
        Start-Process -FilePath $running.ExecutablePath -ArgumentList '--lang=zh-CN'
        return
    }

    $package = Get-CodexPackage
    if ($null -eq $package) { throw 'No Store package was found.' }
    $currentRoot = Join-Path $root ([string]$package.Version)
    if (-not (Test-UnifiedRuntime $currentRoot)) {
        Write-LaunchLog "Building unified runtime for Store version $($package.Version)."
        $installer = Join-Path $root 'Install-Codex-Unified.ps1'
        $pwsh = Join-Path $PSHOME 'pwsh.exe'
        & $pwsh -NoProfile -File $installer -Action Install -PatchRoot $root
        if ($LASTEXITCODE -ne 0) {
            throw "Unified installer failed with exit code $LASTEXITCODE."
        }
    }

    if (Test-UnifiedRuntime $currentRoot) {
        Start-UnifiedRuntime $currentRoot
        return
    }

    $lastGood = Get-ChildItem -LiteralPath $root -Directory -Force |
        Where-Object { $_.Name -match '^\d+(\.\d+)+$' -and (Test-UnifiedRuntime $_.FullName) } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($null -ne $lastGood) {
        Write-LaunchLog "Using last known good runtime $($lastGood.Name)."
        Start-UnifiedRuntime $lastGood.FullName
        return
    }

    Start-StoreFallback
} catch {
    Write-LaunchLog "ERROR: $($_.Exception.Message)"
    $lastGood = Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+(\.\d+)+$' -and (Test-UnifiedRuntime $_.FullName) } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($null -ne $lastGood) {
        Start-UnifiedRuntime $lastGood.FullName
    } else {
        Start-StoreFallback
    }
} finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
'@
    [IO.File]::WriteAllText($launcherPath, $launcherText, $Utf8NoBom)

    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $vbsPath = Join-Path $Root 'Launch-Codex-Unified.vbs'
    $vbsText = @"
Option Explicit
Dim shell
Set shell = CreateObject("WScript.Shell")
shell.Run Chr(34) & "$pwshPath" & Chr(34) & " -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & "$launcherPath" & Chr(34), 0, False
"@
    [IO.File]::WriteAllText($vbsPath, $vbsText, [Text.Encoding]::ASCII)

    return [pscustomobject]@{
        PowerShell = $launcherPath
        Vbs = $vbsPath
    }
}

function Set-ShortcutAppUserModelId([string]$ShortcutPath, [string]$Identity) {
    if (-not ('CodexUnified.ShortcutIdentity' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace CodexUnified {
    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    internal class ShellLink { }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    internal struct PropertyKey {
        internal Guid FormatId;
        internal uint PropertyId;
        internal PropertyKey(Guid formatId, uint propertyId) {
            FormatId = formatId;
            PropertyId = propertyId;
        }
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct PropVariant : IDisposable {
        [FieldOffset(0)] internal ushort ValueType;
        [FieldOffset(8)] internal IntPtr PointerValue;

        internal static PropVariant FromString(string value) {
            return new PropVariant {
                ValueType = 31,
                PointerValue = Marshal.StringToCoTaskMemUni(value)
            };
        }

        public void Dispose() {
            PropVariantClear(ref this);
        }

        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PropVariant value);
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    public static class ShortcutIdentity {
        public static void SetAppUserModelId(string path, string identity) {
            object link = new ShellLink();
            try {
                ((IPersistFile)link).Load(path, 2);
                IPropertyStore store = (IPropertyStore)link;
                PropertyKey key = new PropertyKey(
                    new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);
                PropVariant value = PropVariant.FromString(identity);
                try {
                    Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref value));
                    Marshal.ThrowExceptionForHR(store.Commit());
                    ((IPersistFile)link).Save(path, true);
                } finally {
                    value.Dispose();
                }
            } finally {
                if (Marshal.IsComObject(link)) {
                    Marshal.FinalReleaseComObject(link);
                }
            }
        }
    }
}
'@
    }
    [CodexUnified.ShortcutIdentity]::SetAppUserModelId($ShortcutPath, $Identity)
}

function Write-DesktopShortcuts(
    [string]$Root,
    [string]$VbsPath,
    [string]$FallbackExe,
    [string]$AppUserModelId
) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $backupRoot = Join-Path $Root 'shortcut-backups'
    $desktopBackupRoot = Join-Path $backupRoot 'desktop'
    $startMenuBackupRoot = Join-Path $backupRoot 'start-menu'
    New-Item -ItemType Directory -Force -Path $desktopBackupRoot, $startMenuBackupRoot | Out-Null

    foreach ($name in @('ChatGPT.lnk', 'ChatGPT 中文菜单.lnk')) {
        $legacyBackup = Join-Path $backupRoot $name
        $backup = Join-Path $desktopBackupRoot $name
        if ((Test-Path -LiteralPath $legacyBackup -PathType Leaf) -and
            -not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            Copy-Item -LiteralPath $legacyBackup -Destination $backup -Force
        }
        $source = Join-Path $desktop $name
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and
            -not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            Copy-Item -LiteralPath $source -Destination $backup -Force
        }
    }

    $startMenuNames = @('ChatGPT.lnk', 'ChatGPT 联合版.lnk')
    foreach ($name in $startMenuNames) {
        $startMenuShortcut = Join-Path $startMenu $name
        $startMenuBackup = Join-Path $startMenuBackupRoot $name
        if ((Test-Path -LiteralPath $startMenuShortcut -PathType Leaf) -and
            -not (Test-Path -LiteralPath $startMenuBackup -PathType Leaf)) {
            Copy-Item -LiteralPath $startMenuShortcut -Destination $startMenuBackup -Force
        }
    }

    $wsh = New-Object -ComObject WScript.Shell
    $iconLocation = $null
    $officialBackup = Join-Path $desktopBackupRoot 'ChatGPT.lnk'
    if (Test-Path -LiteralPath $officialBackup -PathType Leaf) {
        $oldShortcut = $wsh.CreateShortcut($officialBackup)
        if ($oldShortcut.IconLocation) { $iconLocation = $oldShortcut.IconLocation }
    }
    if (-not $iconLocation) { $iconLocation = "$FallbackExe,0" }

    $shortcutPaths = @(
        (Join-Path $desktop 'ChatGPT.lnk'),
        (Join-Path $desktop 'ChatGPT 中文菜单.lnk'),
        (Join-Path $startMenu 'ChatGPT.lnk'),
        (Join-Path $startMenu 'ChatGPT 联合版.lnk')
    )
    foreach ($shortcutPath in $shortcutPaths) {
        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $shortcut.Arguments = '"' + $VbsPath + '"'
        $shortcut.WorkingDirectory = $Root
        $shortcut.Description = 'ChatGPT unified Chinese-menu and long-paste launcher'
        $shortcut.IconLocation = $iconLocation
        $shortcut.Save()
        Set-ShortcutAppUserModelId $shortcutPath $AppUserModelId
    }

    $refresh = Join-Path $env:WINDIR 'System32\ie4uinit.exe'
    if (Test-Path -LiteralPath $refresh -PathType Leaf) {
        & $refresh -show
    }
}

function Restore-DesktopShortcuts([string]$Root) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $backupRoot = Join-Path $Root 'shortcut-backups'
    $desktopBackupRoot = Join-Path $backupRoot 'desktop'
    $startMenuBackupRoot = Join-Path $backupRoot 'start-menu'

    foreach ($name in @('ChatGPT.lnk', 'ChatGPT 中文菜单.lnk')) {
        $shortcut = Join-Path $desktop $name
        $backup = Join-Path $desktopBackupRoot $name
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            $backup = Join-Path $backupRoot $name
        }
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            Copy-Item -LiteralPath $backup -Destination $shortcut -Force
        } elseif (Test-Path -LiteralPath $shortcut -PathType Leaf) {
            Remove-Item -LiteralPath $shortcut -Force
        }
    }

    foreach ($name in @('ChatGPT.lnk', 'ChatGPT 联合版.lnk')) {
        $startShortcut = Join-Path $startMenu $name
        $startBackup = Join-Path $startMenuBackupRoot $name
        if (Test-Path -LiteralPath $startBackup -PathType Leaf) {
            Copy-Item -LiteralPath $startBackup -Destination $startShortcut -Force
        } elseif (Test-Path -LiteralPath $startShortcut -PathType Leaf) {
            Remove-Item -LiteralPath $startShortcut -Force
        }
    }
}

$fullPatchRoot = Assert-PatchRoot $PatchRoot
$package = Get-CodexPackage
$officialAppUserModelId = "$($package.PackageFamilyName)!App"
$versionRoot = Join-Path $fullPatchRoot ([string]$package.Version)
$patchedAsar = Join-Path $versionRoot 'app\resources\app.asar'
$unifiedMarker = Join-Path $versionRoot 'unified-status.json'

if ($Action -eq 'Status') {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $wsh = New-Object -ComObject WScript.Shell
    $desktopShortcut = Join-Path $desktop 'ChatGPT.lnk'
    $arguments = $null
    if (Test-Path -LiteralPath $desktopShortcut -PathType Leaf) {
        $arguments = $wsh.CreateShortcut($desktopShortcut).Arguments
    }
    [pscustomobject]@{
        StoreVersion = [string]$package.Version
        UnifiedRuntimeExists = Test-Path -LiteralPath $patchedAsar -PathType Leaf
        UnifiedMarkerExists = Test-Path -LiteralPath $unifiedMarker -PathType Leaf
        StableLauncherExists = Test-Path -LiteralPath (Join-Path $fullPatchRoot 'Launch-Codex-Unified.vbs') -PathType Leaf
        DesktopShortcutArguments = $arguments
        PatchRoot = $fullPatchRoot
    } | Format-List
    return
}

if ($Action -eq 'Remove') {
    Restore-DesktopShortcuts $fullPatchRoot
    if (Test-Path -LiteralPath $fullPatchRoot -PathType Container) {
        Remove-Item -LiteralPath $fullPatchRoot -Recurse -Force
    }
    Write-Host 'Removed the unified runtime and restored the previous desktop shortcuts.'
    return
}

if ($Action -eq 'RefreshShortcuts') {
    if (-not (Test-Path -LiteralPath $unifiedMarker -PathType Leaf)) {
        throw "Unified marker is missing: $unifiedMarker"
    }
    New-Item -ItemType Directory -Force -Path $fullPatchRoot | Out-Null
    Copy-DurableScript $PSCommandPath (Join-Path $fullPatchRoot 'Install-Codex-Unified.ps1')
    $launchers = Write-StableLaunchers $fullPatchRoot
    $appExe = Join-Path $versionRoot 'app\ChatGPT.exe'
    Write-DesktopShortcuts $fullPatchRoot $launchers.Vbs $appExe $officialAppUserModelId
    Write-Host 'Refreshed desktop and Start menu shortcuts with the official AppUserModelID.'
    return
}

$targetProcesses = @(
    Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" | Where-Object {
        $_.ExecutablePath -and
        $_.ExecutablePath.StartsWith($fullPatchRoot + '\', [StringComparison]::OrdinalIgnoreCase)
    }
)
if ($targetProcesses.Count -gt 0) {
    throw 'The unified runtime is currently running. Close it completely before rebuilding this version.'
}

$chineseScriptPath = Resolve-RequiredScript $ChineseMenuScript 'Install-Codex-Chinese-Menu.ps1' $null
$longPasteFallback = $null
$longPasteScriptPath = Resolve-RequiredScript $LongPasteScript 'codex-long-paste-patch.ps1' $longPasteFallback

New-Item -ItemType Directory -Force -Path $fullPatchRoot | Out-Null
Write-Host "Building unified runtime for Store version $($package.Version)..."
Invoke-PowerShellScript $chineseScriptPath @(
    '-Action', 'Install',
    '-PatchRoot', $fullPatchRoot,
    '-SkipDesktopShortcut',
    '-AppUserModelId', $officialAppUserModelId
)

if (-not (Test-Path -LiteralPath $patchedAsar -PathType Leaf)) {
    throw "Chinese-menu build did not produce app.asar: $patchedAsar"
}

Invoke-PowerShellScript $longPasteScriptPath @(
    '-Action', 'Install',
    '-SourceAsar', $patchedAsar
)

$longPasteState = Get-LongPastePatchState $patchedAsar
if ($longPasteState.OriginalCount -ne 0 -or $longPasteState.PatchedCount -ne 1 -or
    $longPasteState.MatchingNames.Count -ne 1) {
    throw "Long-paste verification failed: original=$($longPasteState.OriginalCount), patched=$($longPasteState.PatchedCount), files=$($longPasteState.MatchingNames.Count)"
}

$chineseMarkerPath = Join-Path $versionRoot 'patch-status.json'
$chineseStatus = Get-Content -Raw -LiteralPath $chineseMarkerPath | ConvertFrom-Json
$longPasteBackup = "$patchedAsar.before-long-paste-patch"
if (-not (Test-Path -LiteralPath $longPasteBackup -PathType Leaf)) {
    throw 'The Chinese-only ASAR backup was not created.'
}

$status = [ordered]@{
    schemaVersion = 1
    packageVersion = [string]$package.Version
    sourcePackageFullName = $package.PackageFullName
    chineseMenuPatched = $true
    longPastePatched = $true
    longPasteBundle = $longPasteState.MatchingNames[0]
    appUserModelId = $officialAppUserModelId
    sourceAsarSha256 = [string]$chineseStatus.sourceAsarSha256
    chineseOnlyAsarSha256 = (Get-FileHash -LiteralPath $longPasteBackup -Algorithm SHA256).Hash.ToLowerInvariant()
    patchedAsarSha256 = (Get-FileHash -LiteralPath $patchedAsar -Algorithm SHA256).Hash.ToLowerInvariant()
    userData = [string]$chineseStatus.userData
    builtAt = [DateTimeOffset]::Now.ToString('o')
}
[IO.File]::WriteAllText($unifiedMarker, ($status | ConvertTo-Json -Depth 5), $Utf8NoBom)

Copy-DurableScript $PSCommandPath (Join-Path $fullPatchRoot 'Install-Codex-Unified.ps1')
Copy-DurableScript $chineseScriptPath (Join-Path $fullPatchRoot 'Install-Codex-Chinese-Menu.ps1')
Copy-DurableScript $longPasteScriptPath (Join-Path $fullPatchRoot 'codex-long-paste-patch.ps1')

$launchers = Write-StableLaunchers $fullPatchRoot
$appExe = Join-Path $versionRoot 'app\ChatGPT.exe'
Write-DesktopShortcuts $fullPatchRoot $launchers.Vbs $appExe $officialAppUserModelId

Write-Host ''
Write-Host "Unified runtime: $versionRoot"
Write-Host "Stable desktop entry: $(Join-Path ([Environment]::GetFolderPath('Desktop')) 'ChatGPT.lnk')"
Write-Host 'The Store package remains unchanged and continues to provide updates.'
