[CmdletBinding()]
param(
    [ValidateSet('Install', 'Status', 'Remove')]
    [string]$Action = 'Install',

    [string]$PatchRoot = (Join-Path $env:LOCALAPPDATA 'CodexLongPastePatch'),

    [string]$SourceAsar,

    [switch]$AsarOnly
)

$ErrorActionPreference = 'Stop'
$OriginalPattern = '(?<gate>[A-Za-z_$][A-Za-z0-9_$]*)&&(?<editor>[A-Za-z_$][A-Za-z0-9_$]*)\.addPastedTextHandler\((?<handler>[A-Za-z_$][A-Za-z0-9_$]*)\)'
$PatchedPattern = '!1\s*&&[A-Za-z_$][A-Za-z0-9_$]*\.addPastedTextHandler\([A-Za-z_$][A-Za-z0-9_$]*\)'

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

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-ByteSlice([byte[]]$Bytes, [long]$Offset, [int]$Count) {
    $slice = New-Object byte[] $Count
    [Array]::Copy($Bytes, $Offset, $slice, 0, $Count)
    return $slice
}

function Patch-Asar([string]$AsarPath) {
    if (-not (Test-Path -LiteralPath $AsarPath -PathType Leaf)) {
        throw "app.asar not found: $AsarPath"
    }

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

    $matches = @()
    foreach ($property in $assetFiles.PSObject.Properties) {
        # The bundle was named composer-*.js in older releases and moved to
        # codex-composer-adapter-*.js in 26.715. Scan every top-level JS asset
        # and let the unique code pattern, rather than the filename, identify it.
        if ($property.Name -notlike '*.js') { continue }
        $entry = $property.Value
        if ($null -eq $entry.offset -or $null -eq $entry.size) { continue }

        # ASAR data begins after the 8-byte size pickle plus the header pickle.
        $fileOffset = 8L + [long]$headerSize + [long]$entry.offset
        $fileSize = [int]$entry.size
        $fileBytes = Get-ByteSlice $bytes $fileOffset $fileSize
        $fileText = [Text.Encoding]::UTF8.GetString($fileBytes)
        $found = [regex]::Matches($fileText, $OriginalPattern)
        foreach ($item in $found) {
            $matches += [pscustomobject]@{
                Name = $property.Name
                Entry = $entry
                FileOffset = $fileOffset
                FileSize = $fileSize
                FileBytes = $fileBytes
                Text = $fileText
                Match = $item
            }
        }
    }

    if ($matches.Count -eq 0) {
        $alreadyPatched = $false
        foreach ($property in $assetFiles.PSObject.Properties) {
            if ($property.Name -notlike '*.js') { continue }
            $entry = $property.Value
            if ($null -eq $entry.offset -or $null -eq $entry.size) { continue }
            $fileBytes = Get-ByteSlice $bytes (8L + [long]$headerSize + [long]$entry.offset) ([int]$entry.size)
            if ([Text.Encoding]::UTF8.GetString($fileBytes) -match $PatchedPattern) {
                $alreadyPatched = $true
                break
            }
        }
        if ($alreadyPatched) {
            Write-Host "Already patched: $AsarPath"
            return
        }
        throw 'Patch target was not found. The Codex build changed; no file was modified.'
    }
    if ($matches.Count -ne 1) {
        throw "Expected exactly one patch target, found $($matches.Count); no file was modified."
    }

    $target = $matches[0]
    $gate = $target.Match.Groups['gate'].Value
    if ($gate.Length -lt 2) {
        throw 'The minified feature gate is too short for a safe equal-length replacement.'
    }

    $replacementGate = '!1' + (' ' * ($gate.Length - 2))
    $replacement = $replacementGate + $target.Match.Value.Substring($gate.Length)
    if ($replacement.Length -ne $target.Match.Value.Length) {
        throw 'Internal error: replacement is not length preserving.'
    }

    $patchedText = $target.Text.Substring(0, $target.Match.Index) + $replacement +
        $target.Text.Substring($target.Match.Index + $target.Match.Length)
    $patchedFileBytes = [Text.Encoding]::UTF8.GetBytes($patchedText)
    if ($patchedFileBytes.Length -ne $target.FileSize) {
        throw 'UTF-8 byte length changed; no file was modified.'
    }

    [Array]::Copy($patchedFileBytes, 0, $bytes, $target.FileOffset, $target.FileSize)

    $integrity = $target.Entry.integrity
    if ($null -eq $integrity -or $integrity.algorithm -ne 'SHA256') {
        throw 'Target webview asset has no supported SHA256 integrity metadata.'
    }

    $hashReplacements = @{}
    $hashReplacements[[string]$integrity.hash] = Get-Sha256Hex $patchedFileBytes
    $blockSize = [int]$integrity.blockSize
    for ($i = 0; $i -lt $integrity.blocks.Count; $i++) {
        $start = $i * $blockSize
        $count = [Math]::Min($blockSize, $patchedFileBytes.Length - $start)
        $block = Get-ByteSlice $patchedFileBytes $start $count
        $hashReplacements[[string]$integrity.blocks[$i]] = Get-Sha256Hex $block
    }

    $patchedHeaderJson = $headerJson
    foreach ($oldHash in $hashReplacements.Keys) {
        $patchedHeaderJson = $patchedHeaderJson.Replace($oldHash, $hashReplacements[$oldHash])
    }
    $patchedHeaderBytes = [Text.Encoding]::UTF8.GetBytes($patchedHeaderJson)
    if ($patchedHeaderBytes.Length -ne $jsonLength) {
        throw 'ASAR header byte length changed; no file was modified.'
    }
    [Array]::Copy($patchedHeaderBytes, 0, $bytes, 16, $jsonLength)

    $backup = "$AsarPath.before-long-paste-patch"
    if (-not (Test-Path -LiteralPath $backup)) {
        [IO.File]::Copy($AsarPath, $backup, $false)
    }
    [IO.File]::WriteAllBytes($AsarPath, $bytes)
    Write-Host "Patched $($target.Name) in $AsarPath"
    Write-Host "Backup: $backup"
}

if ($Action -eq 'Remove') {
    if (Test-Path -LiteralPath $PatchRoot) {
        $fullRoot = Get-FullPath $PatchRoot
        $allowedBase = (Get-FullPath $env:LOCALAPPDATA).TrimEnd('\') + '\'
        if (-not $fullRoot.StartsWith($allowedBase, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove patch root outside LOCALAPPDATA: $fullRoot"
        }
        Remove-Item -LiteralPath $fullRoot -Recurse -Force
        Write-Host "Removed patched runtime: $fullRoot"
    }
    return
}

if ($SourceAsar) {
    if ($Action -eq 'Status') {
        Write-Host "ASAR: $SourceAsar"
        return
    }
    Patch-Asar $SourceAsar
    return
}

$package = @(
    Get-AppxPackage | Where-Object {
        $appRoot = Join-Path $_.InstallLocation 'app'
        (Test-Path -LiteralPath (Join-Path $appRoot 'resources\app.asar') -PathType Leaf) -and
        ((Test-Path -LiteralPath (Join-Path $appRoot 'ChatGPT.exe') -PathType Leaf) -or
         (Test-Path -LiteralPath (Join-Path $appRoot 'Codex.exe') -PathType Leaf))
    }
) | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $package) { throw 'No installed Codex/ChatGPT package with a Codex app payload was found.' }
$sourceApp = Join-Path $package.InstallLocation 'app'
if (-not (Test-Path -LiteralPath $sourceApp -PathType Container)) {
    throw "Codex app directory not found: $sourceApp"
}

$versionRoot = Join-Path $PatchRoot ([string]$package.Version)
$patchedApp = Join-Path $versionRoot 'app'
$patchedAsar = Join-Path $patchedApp 'resources\app.asar'
$launcher = Join-Path $PatchRoot 'Run-Codex-No-Long-Paste-Attachments.cmd'
$sharedConfigLauncher = Join-Path $PatchRoot 'Run-Codex-Shared-Config.cmd'

if ($Action -eq 'Status') {
    Write-Host "Installed package: $($package.Version)"
    Write-Host "Patched app exists: $(Test-Path -LiteralPath $patchedAsar)"
    Write-Host "Launcher: $launcher"
    return
}

New-Item -ItemType Directory -Force -Path $versionRoot | Out-Null
if (-not (Test-Path -LiteralPath $patchedAsar)) {
    if (Test-Path -LiteralPath $patchedApp) {
        Assert-PathUnderRoot $patchedApp $PatchRoot
        Remove-Item -LiteralPath $patchedApp -Recurse -Force
    }
    Write-Host "Copying Codex $($package.Version) to $patchedApp ..."
    Copy-Item -LiteralPath $sourceApp -Destination $patchedApp -Recurse -Force
}

Patch-Asar $patchedAsar

$appExe = Join-Path $patchedApp 'ChatGPT.exe'
if (-not (Test-Path -LiteralPath $appExe -PathType Leaf)) {
    $appExe = Join-Path $patchedApp 'Codex.exe'
}
if (-not (Test-Path -LiteralPath $appExe -PathType Leaf)) {
    throw "Neither ChatGPT.exe nor Codex.exe was found in $patchedApp"
}
$cliExe = Join-Path $patchedApp 'resources\codex.exe'
$userData = Join-Path $PatchRoot 'electron-user-data'
$launcherText = @"
@echo off
set "CODEX_HOME=%USERPROFILE%\.codex"
set "CODEX_ELECTRON_USER_DATA_PATH=$userData"
set "CODEX_CLI_PATH=$cliExe"
start "" "$appExe"
"@
[IO.File]::WriteAllText($launcher, $launcherText, [Text.Encoding]::ASCII)

$sharedConfigLauncherText = @"
@echo off
set "CODEX_HOME=%USERPROFILE%\.codex"
set "CODEX_ELECTRON_USER_DATA_PATH=$userData"
set "CODEX_CLI_PATH=$cliExe"
start "" "$appExe"
"@
[IO.File]::WriteAllText($sharedConfigLauncher, $sharedConfigLauncherText, [Text.Encoding]::ASCII)

Write-Host ''
Write-Host 'Patch ready. Close the official Codex app completely, then run:'
Write-Host $launcher
Write-Host 'Do not run the official and patched apps simultaneously.'
