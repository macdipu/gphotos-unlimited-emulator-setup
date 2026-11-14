# GPhotos Windows -> Android Emulator Sync
# Windows PowerShell 5.1
# Source:      %USERPROFILE%\Documents\Gphotos
# Destination: /sdcard/DCIM/Camera
# One-way copy/update. Windows deletions do NOT delete Android files.

$ErrorActionPreference = "Stop"

$Source = Join-Path $env:USERPROFILE "Documents\Gphotos"
$RemoteRoot = "/sdcard/DCIM/Camera"
$PollSeconds = 3
$StableCheckMilliseconds = 700
$StateFile = Join-Path $PSScriptRoot ".gphotos-sync-state.json"

function Write-Info($Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Ok($Message)   { Write-Host $Message -ForegroundColor Green }
function Write-Warn($Message){ Write-Host $Message -ForegroundColor Yellow }
function Write-Err($Message) { Write-Host $Message -ForegroundColor Red }

function ConvertTo-ShellArgument([string]$Value) {
    # Safely quote a value for Android's shell.
    return "'" + $Value.Replace("'", "'\''") + "'"
}

# Locate ADB
$AdbCommand = Get-Command adb -ErrorAction SilentlyContinue
if (-not $AdbCommand) {
    Write-Err "ADB was not found. Add Android SDK platform-tools to PATH, then reopen PowerShell."
    Read-Host "Press Enter to exit"
    exit 1
}
$Adb = $AdbCommand.Source

# Create source folder if it does not exist
if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    New-Item -ItemType Directory -Path $Source -Force | Out-Null
    Write-Warn "Created source folder: $Source"
    Write-Warn "Put your photos/files there, then this script will sync them."
}

# Load persistent sync state
$Cache = @{}
if (Test-Path -LiteralPath $StateFile) {
    try {
        $SavedState = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        if ($SavedState) {
            foreach ($Property in $SavedState.PSObject.Properties) {
                $Cache[$Property.Name] = [string]$Property.Value
            }
        }
    } catch {
        Write-Warn "Could not read old sync state; starting with an empty cache."
    }
}

# Find online emulator/device
$DeviceRows = @(& $Adb devices 2>$null | Select-String '^\S+\s+device$')
$Devices = @($DeviceRows | ForEach-Object { ($_ -split '\s+')[0] })

if ($Devices.Count -eq 0) {
    Write-Err "No online Android device found. Start the emulator and run this script again."
    & $Adb devices
    Read-Host "Press Enter to exit"
    exit 1
}

if ($Devices.Count -eq 1) {
    $Serial = $Devices[0]
} else {
    Write-Host "`nAvailable Android devices:" -ForegroundColor White
    for ($i = 0; $i -lt $Devices.Count; $i++) {
        Write-Host ("{0}. {1}" -f ($i + 1), $Devices[$i])
    }
    $Selection = Read-Host "Choose device number"
    $Number = 0
    if (-not [int]::TryParse($Selection, [ref]$Number) -or
        $Number -lt 1 -or $Number -gt $Devices.Count) {
        Write-Err "Invalid device selection."
        exit 1
    }
    $Serial = $Devices[$Number - 1]
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor White
Write-Host "          GPHOTOS CONTINUOUS SYNC" -ForegroundColor White
Write-Host "==============================================" -ForegroundColor White
Write-Host "Windows : $Source"
Write-Host "Android : $RemoteRoot"
Write-Host "Device  : $Serial"
Write-Host "Check   : every $PollSeconds seconds"
Write-Host "Stop    : Ctrl+C"
Write-Host "Mode    : one-way copy/update (no remote deletions)"
Write-Host ""

# Create destination folder
& $Adb -s $Serial shell "mkdir -p $(ConvertTo-ShellArgument $RemoteRoot)"
if ($LASTEXITCODE -ne 0) {
    Write-Err "Could not create Android destination folder."
    Read-Host "Press Enter to exit"
    exit 1
}

$LastStateSave = Get-Date

while ($true) {
    try {
        $DeviceState = (& $Adb -s $Serial get-state 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $DeviceState -ne "device") {
            Write-Warn "Device offline; waiting for it to reconnect..."
            Start-Sleep -Seconds $PollSeconds
            continue
        }

        $Files = @(Get-ChildItem -LiteralPath $Source -File -Recurse -Force -ErrorAction SilentlyContinue)

        foreach ($File in $Files) {
            try {
                # Confirm the file is not still being written.
                $Before = Get-Item -LiteralPath $File.FullName -ErrorAction Stop
                Start-Sleep -Milliseconds $StableCheckMilliseconds
                $After = Get-Item -LiteralPath $File.FullName -ErrorAction Stop

                if ($Before.Length -ne $After.Length -or
                    $Before.LastWriteTimeUtc.Ticks -ne $After.LastWriteTimeUtc.Ticks) {
                    continue
                }

                $RelativePath = $After.FullName.Substring($Source.Length).TrimStart('\')
                $RelativeAndroidPath = $RelativePath.Replace('\', '/')
                $RemoteFile = "$RemoteRoot/$RelativeAndroidPath"
                $RemoteDirectory = $RemoteFile.Substring(0, $RemoteFile.LastIndexOf('/'))

                $Signature = "{0}|{1}" -f $After.Length, $After.LastWriteTimeUtc.Ticks

                if ($Cache.ContainsKey($After.FullName) -and
                    $Cache[$After.FullName] -eq $Signature) {
                    continue
                }

                & $Adb -s $Serial shell "mkdir -p $(ConvertTo-ShellArgument $RemoteDirectory)" | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "Could not create destination directory for: $RelativePath"
                    continue
                }

                Write-Info "Copying: $RelativePath"
                & $Adb -s $Serial push $After.FullName $RemoteFile

                if ($LASTEXITCODE -eq 0) {
                    $Cache[$After.FullName] = $Signature
                    Write-Ok "Synced: $RelativePath"
                } else {
                    Write-Warn "Transfer failed; will retry: $RelativePath"
                }
            } catch {
                Write-Warn ("Skipped/retrying {0}: {1}" -f $File.FullName, $_.Exception.Message)
            }
        }

        # Persist cache so already-synced files are not needlessly pushed after restart.
        if (((Get-Date) - $LastStateSave).TotalSeconds -ge 5) {
            $Cache | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateFile -Encoding UTF8
            $LastStateSave = Get-Date
        }

        Start-Sleep -Seconds $PollSeconds
    } catch {
        Write-Err ("Sync loop error: " + $_.Exception.Message)
        Start-Sleep -Seconds $PollSeconds
    }
}
