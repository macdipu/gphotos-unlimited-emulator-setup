
#requires -Version 5.1

<#
.SYNOPSIS
    Continuously sync Windows photos to Android Emulator.

.SOURCE
    %USERPROFILE%\Documents\Gphotos

.DESTINATION
    /sdcard/DCIM/Camera

.FEATURES
    - One-way copy/update
    - Automatic media indexing
    - Recursive folder support
    - Persistent sync cache
    - Device auto-detection
    - Retry on transfer failure
    - No remote deletions
#>

$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURATION
# ============================================================

$Config = @{
    Source                  = Join-Path $env:USERPROFILE "Documents\Gphotos"
    RemoteRoot              = "/sdcard/DCIM/Camera"
    PollSeconds             = 3
    StableCheckMilliseconds = 700
    MaxRetries              = 3
    MediaScan               = $true
    StateFile               = Join-Path $PSScriptRoot ".gphotos-sync-state.json"
}

$ImageExtensions = @(
    ".jpg", ".jpeg", ".png", ".webp",
    ".gif", ".bmp", ".heic", ".heif",
    ".dng", ".tif", ".tiff"
)

$script:Adb = $null
$script:Serial = $null
$script:Cache = @{}
$script:LastStateSave = Get-Date

# ============================================================
# LOGGING
# ============================================================

function Write-Info($Message) {
    Write-Host "  [INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok($Message) {
    Write-Host "  [ OK ] $Message" -ForegroundColor Green
}

function Write-Warn($Message) {
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Err($Message) {
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Write-Header {
    Clear-Host

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor DarkCyan
    Write-Host "             GPHOTOS WINDOWS SYNC" -ForegroundColor White
    Write-Host "========================================================" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Windows : $($Config.Source)"
    Write-Host "  Android : $($Config.RemoteRoot)"
    Write-Host "  Device  : $script:Serial"
    Write-Host "  Interval: $($Config.PollSeconds) seconds"
    Write-Host ""
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Ctrl+C to stop | One-way sync | No remote deletions"
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

# ============================================================
# ADB
# ============================================================

function Initialize-Adb {
    $Command = Get-Command adb -ErrorAction SilentlyContinue

    if (-not $Command) {
        throw "ADB not found. Add Android SDK platform-tools to PATH."
    }

    $script:Adb = $Command.Source

    Write-Ok "ADB found: $script:Adb"
}

function Get-OnlineDevices {
    $Output = @(& $script:Adb devices 2>$null)

    $Devices = @(
        $Output |
        Where-Object {
            $_ -match '^\s*(\S+)\s+device\s*$'
        } |
        ForEach-Object {
            if ($_ -match '^\s*(\S+)\s+device\s*$') {
                $Matches[1]
            }
        }
    )

    return $Devices
}

function Select-Device {
    $Devices = @(Get-OnlineDevices)

    if ($Devices.Count -eq 0) {
        throw "No online Android emulator/device found. Start your emulator first."
    }

    if ($Devices.Count -eq 1) {
        $script:Serial = $Devices[0]
        Write-Ok "Connected device: $script:Serial"
        return
    }

    Write-Host ""
    Write-Host "Available devices:" -ForegroundColor White

    for ($i = 0; $i -lt $Devices.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $Devices[$i])
    }

    $Selection = Read-Host "Choose device number"
    $Number = 0

    if (
        -not [int]::TryParse($Selection, [ref]$Number) -or
        $Number -lt 1 -or
        $Number -gt $Devices.Count
    ) {
        throw "Invalid device selection."
    }

    $script:Serial = $Devices[$Number - 1]
}

function Test-DeviceConnection {
    if (-not $script:Serial) {
        return $false
    }

    $Output = @(& $script:Adb -s $script:Serial get-state 2>$null)
    return ($LASTEXITCODE -eq 0 -and ($Output -join "").Trim() -eq "device")
}

function Ensure-DeviceConnection {
    if (Test-DeviceConnection) {
        return $true
    }

    Write-Warn "Device disconnected. Waiting for connection..."

    while ($true) {
        $Devices = @(Get-OnlineDevices)

        if ($Devices -contains $script:Serial) {
            if (Test-DeviceConnection) {
                Write-Ok "Device reconnected: $script:Serial"
                return $true
            }
        }
        elseif ($Devices.Count -eq 1) {
            $script:Serial = $Devices[0]
            Write-Ok "Using device: $script:Serial"
            return $true
        }
        elseif ($Devices.Count -gt 1) {
            Write-Warn "Multiple devices found. Keeping the previous device selection."
        }

        Start-Sleep -Seconds $Config.PollSeconds
    }
}

function Initialize-RemoteDirectory {
    $QuotedPath = ConvertTo-ShellArgument $Config.RemoteRoot

    & $script:Adb -s $script:Serial shell "mkdir -p $QuotedPath" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create Android destination directory."
    }

    Write-Ok "Android destination ready"
}

# ============================================================
# SHELL QUOTING
# ============================================================

function ConvertTo-ShellArgument([string]$Value) {
    return "'" + $Value.Replace("'", "'\''") + "'"
}

# ============================================================
# STATE MANAGEMENT
# ============================================================

function Import-SyncState {
    if (-not (Test-Path -LiteralPath $Config.StateFile)) {
        Write-Info "No previous sync state. Starting fresh."
        return
    }

    try {
        $SavedState = Get-Content -LiteralPath $Config.StateFile -Raw |
            ConvertFrom-Json

        if ($SavedState) {
            foreach ($Property in $SavedState.PSObject.Properties) {
                $script:Cache[$Property.Name] = [string]$Property.Value
            }
        }

        Write-Ok "Loaded $($script:Cache.Count) cached files"
    }
    catch {
        Write-Warn "Could not load previous state. Starting fresh."
    }
}

function Export-SyncState {
    try {
        $Directory = Split-Path -Parent $Config.StateFile

        if (-not (Test-Path -LiteralPath $Directory)) {
            New-Item -ItemType Directory -Path $Directory -Force |
                Out-Null
        }

        $TemporaryFile = "$($Config.StateFile).tmp"

        $script:Cache |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $TemporaryFile -Encoding UTF8

        Move-Item -LiteralPath $TemporaryFile `
            -Destination $Config.StateFile -Force

        $script:LastStateSave = Get-Date
    }
    catch {
        Write-Warn "Unable to save sync state: $($_.Exception.Message)"
    }
}

# ============================================================
# FILE HANDLING
# ============================================================

function Get-FileSignature($File) {
    return "{0}|{1}" -f $File.Length, $File.LastWriteTimeUtc.Ticks
}

function Test-FileStable([string]$Path) {
    try {
        $Before = Get-Item -LiteralPath $Path -ErrorAction Stop

        Start-Sleep -Milliseconds $Config.StableCheckMilliseconds

        $After = Get-Item -LiteralPath $Path -ErrorAction Stop

        return (
            $Before.Length -eq $After.Length -and
            $Before.LastWriteTimeUtc.Ticks -eq $After.LastWriteTimeUtc.Ticks
        )
    }
    catch {
        return $false
    }
}

function Get-RemotePath([string]$RelativePath) {
    $AndroidPath = $RelativePath.Replace('\', '/')
    return "$($Config.RemoteRoot)/$AndroidPath"
}

function Get-RemoteDirectory([string]$RemoteFile) {
    return $RemoteFile.Substring(0, $RemoteFile.LastIndexOf('/'))
}

# ============================================================
# MEDIA INDEXING
# ============================================================

function Update-AndroidMediaIndex([string]$RemoteFile) {
    if (-not $Config.MediaScan) {
        return
    }

    $Extension = [System.IO.Path]::GetExtension($RemoteFile).ToLowerInvariant()

    if ($ImageExtensions -notcontains $Extension) {
        return
    }

    try {
        $FileUri = "file://$RemoteFile"
        $QuotedUri = ConvertTo-ShellArgument $FileUri

        & $script:Adb -s $script:Serial shell `
            "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d $QuotedUri" |
            Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Info "Media scan requested"
        }
        else {
            Write-Warn "Media scan request failed: $RemoteFile"
        }
    }
    catch {
        Write-Warn "Media indexing error: $($_.Exception.Message)"
    }
}

# ============================================================
# FILE SYNC
# ============================================================

function Sync-File($File) {
    if (-not (Test-FileStable $File.FullName)) {
        return
    }

    $CurrentFile = Get-Item -LiteralPath $File.FullName -ErrorAction SilentlyContinue

    if (-not $CurrentFile) {
        return
    }

    $RelativePath = $CurrentFile.FullName.Substring(
        $Config.Source.Length
    ).TrimStart('\')

    $RemoteFile = Get-RemotePath $RelativePath
    $RemoteDirectory = Get-RemoteDirectory $RemoteFile
    $Signature = Get-FileSignature $CurrentFile

    if (
        $script:Cache.ContainsKey($CurrentFile.FullName) -and
        $script:Cache[$CurrentFile.FullName] -eq $Signature
    ) {
        return
    }

    $QuotedDirectory = ConvertTo-ShellArgument $RemoteDirectory

    & $script:Adb -s $script:Serial shell `
        "mkdir -p $QuotedDirectory" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Cannot create remote directory: $RelativePath"
        return
    }

    for ($Attempt = 1; $Attempt -le $Config.MaxRetries; $Attempt++) {
        if (-not (Ensure-DeviceConnection)) {
            continue
        }

        Write-Info "Uploading: $RelativePath"

        & $script:Adb -s $script:Serial push `
            $CurrentFile.FullName $RemoteFile

        if ($LASTEXITCODE -eq 0) {
            $script:Cache[$CurrentFile.FullName] = $Signature

            Update-AndroidMediaIndex $RemoteFile

            Write-Ok "Synced: $RelativePath"
            return
        }

        Write-Warn "Upload attempt $Attempt/$($Config.MaxRetries) failed"

        Start-Sleep -Seconds 2
    }

    Write-Err "Failed after retries: $RelativePath"
}

# ============================================================
# SYNC ENGINE
# ============================================================

function Start-Sync {
    Write-Header

    Initialize-RemoteDirectory

    Write-Info "Watching Windows folder..."
    Write-Info "Media indexing: $($Config.MediaScan)"
    Write-Info "Press Ctrl+C to stop."
    Write-Host ""

    while ($true) {
        try {
            Ensure-DeviceConnection | Out-Null

            $Files = @(
                Get-ChildItem -LiteralPath $Config.Source `
                    -File -Recurse -Force -ErrorAction SilentlyContinue
            )

            foreach ($File in $Files) {
                try {
                    Sync-File $File
                }
                catch {
                    Write-Warn "$($File.Name): $($_.Exception.Message)"
                }
            }

            if (((Get-Date) - $script:LastStateSave).TotalSeconds -ge 5) {
                Export-SyncState
            }

            Start-Sleep -Seconds $Config.PollSeconds
        }
        catch {
            Write-Err "Sync loop error: $($_.Exception.Message)"
            Start-Sleep -Seconds $Config.PollSeconds
        }
    }
}

# ============================================================
# MAIN
# ============================================================

try {
    Write-Header

    Initialize-Adb

    if (-not (Test-Path -LiteralPath $Config.Source -PathType Container)) {
        New-Item -ItemType Directory -Path $Config.Source -Force |
            Out-Null

        Write-Warn "Created source folder: $($Config.Source)"
    }

    Import-SyncState
    Select-Device

    Start-Sync
}
catch {
    Write-Err $_.Exception.Message
    Read-Host "Press Enter to exit"
}
finally {
    Export-SyncState
}
