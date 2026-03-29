# claude-keeper uninstaller for Windows

$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:LOCALAPPDATA 'claude-keeper'
$ConfigDir = Join-Path $env:APPDATA 'claude-keeper'

function Write-Info { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Green }

$KeepConfig = $false
foreach ($arg in $args) {
    if ($arg -eq '--keep-config') { $KeepConfig = $true }
}

Write-Info 'Uninstalling claude-keeper...'

# Remove Task Scheduler entry
try {
    schtasks /delete /tn 'ClaudeKeeper' /f 2>$null | Out-Null
    Write-Info 'Removed Task Scheduler entry'
} catch {
    # Task may not exist
}

# Remove install directory
if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
    Write-Info "Removed install directory: $InstallDir"
}

# Remove config
if (-not $KeepConfig) {
    if (Test-Path $ConfigDir) {
        Remove-Item $ConfigDir -Recurse -Force
        Write-Info "Removed config directory: $ConfigDir"
    }
} else {
    if (Test-Path $ConfigDir) {
        Write-Host "Config preserved at: $ConfigDir" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Ok 'claude-keeper has been uninstalled.'
