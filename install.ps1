# claude-keeper installer for Windows
# Usage: irm https://raw.githubusercontent.com/pritamneog/claude-keeper/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:LOCALAPPDATA 'claude-keeper'
$RepoBase = 'https://raw.githubusercontent.com/pritamneog/claude-keeper/main'

$Files = @(
    'claude-keeper.ps1',
    'lib/config.ps1',
    'lib/detect.ps1',
    'lib/upgrade.ps1',
    'uninstall.ps1'
)

function Write-Info  { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "==> $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "WARN: $Msg" -ForegroundColor Yellow }

# -- Argument Parsing --

$UpdateTime = '09:00'
$LocalInstall = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '--time' {
            $i++
            $UpdateTime = $args[$i]
            if ($UpdateTime -notmatch '^\d{2}:\d{2}$') {
                Write-Error "Invalid time format: $UpdateTime. Use HH:MM (24h)."
                exit 1
            }
            $timeParts = $UpdateTime -split ':'
            if ([int]$timeParts[0] -gt 23 -or [int]$timeParts[1] -gt 59) {
                Write-Error "Invalid time range: $UpdateTime. Hour must be 0-23, minute 0-59."
                exit 1
            }
        }
        '--local' { $LocalInstall = $true }
        '--help'  {
            Write-Host "claude-keeper installer (Windows)"
            Write-Host ""
            Write-Host "Usage: .\install.ps1 [--time HH:MM] [--local]"
            exit 0
        }
    }
}

# -- Preflight --

Write-Info 'claude-keeper installer (Windows)'
Write-Host ''

# Check for claude
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Warn 'Claude Code not found in PATH.'
    Write-Warn 'Install Claude Code first, then re-run this installer.'
    Write-Warn 'Continuing anyway...'
}

# -- Installation --

if (Test-Path $InstallDir) {
    Write-Info 'Existing installation found. Reconfiguring...'
}

Write-Info "Installing to $InstallDir"

# Create directories
$binDir = Join-Path $InstallDir 'bin'
$libDir = Join-Path $InstallDir 'lib'
$logDir = Join-Path $InstallDir 'logs'
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
New-Item -ItemType Directory -Path $libDir -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

if ($LocalInstall) {
    $sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Write-Info "Installing from local: $sourceDir"

    Copy-Item (Join-Path $sourceDir 'claude-keeper.ps1') (Join-Path $binDir 'claude-keeper.ps1') -Force
    Copy-Item (Join-Path $sourceDir 'lib\*.ps1') $libDir -Force
    $uninstallSrc = Join-Path $sourceDir 'uninstall.ps1'
    if (Test-Path $uninstallSrc) {
        Copy-Item $uninstallSrc (Join-Path $InstallDir 'uninstall.ps1') -Force
    }
} else {
    Write-Info 'Downloading from GitHub...'
    foreach ($file in $Files) {
        $url = "$RepoBase/$file"
        switch -Wildcard ($file) {
            'claude-keeper.ps1' { $dest = Join-Path $binDir 'claude-keeper.ps1' }
            'lib/*'             { $dest = Join-Path $libDir (Split-Path -Leaf $file) }
            'uninstall.ps1'     { $dest = Join-Path $InstallDir 'uninstall.ps1' }
        }
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        } catch {
            Write-Warn "Failed to download $file. Skipping."
        }
    }
}

# -- Configuration --

. (Join-Path $libDir 'config.ps1')
. (Join-Path $libDir 'detect.ps1')

New-DefaultConfig
Write-Config 'update_time' $UpdateTime
Write-Info "Update time set to: $UpdateTime"

$Method = Get-ClaudeInstallMethod
Write-Info "Detected install method: $(Get-MethodDescription $Method)"

if ($Method -eq 'native') {
    Write-Warn 'Native installs auto-update already.'
    Write-Warn "claude-keeper will run 'claude update' as a safety net."
}

# -- Task Scheduler --

$scriptPath = Join-Path $binDir 'claude-keeper.ps1'

try { schtasks /delete /tn 'ClaudeKeeper' /f 2>$null | Out-Null } catch {}

schtasks /create /tn 'ClaudeKeeper' `
    /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" run" `
    /sc daily /st $UpdateTime /f | Out-Null

Write-Info "Scheduler: Task Scheduler configured (daily at $UpdateTime)"

# -- Summary --

Write-Host ''
Write-Ok 'claude-keeper installed successfully!'
Write-Host ''
Write-Host "  Install dir:  $InstallDir"
Write-Host "  Config:       $(Get-ConfigPath)"
Write-Host "  Logs:         $(Get-LogDir)\"
Write-Host "  Schedule:     Daily at $UpdateTime"
Write-Host "  Method:       $(Get-MethodDescription $Method)"
Write-Host ''
Write-Host '  Commands (run from PowerShell):'
Write-Host "    & '$scriptPath' status"
Write-Host "    & '$scriptPath' run"
Write-Host "    & '$scriptPath' test"
Write-Host "    & '$scriptPath' uninstall"
Write-Host ''

# Check if the bin dir is in PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$binDir*") {
    Write-Warn "Add $binDir to your PATH for easier access:"
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `"`$env:Path;$binDir`", 'User')"
}
