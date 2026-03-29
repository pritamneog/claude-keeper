# claude-keeper: Configuration management (Windows)

$ErrorActionPreference = 'Stop'

$script:ConfigDirName = 'claude-keeper'
$script:ConfigFileName = 'config'

function Get-ConfigDir {
    $base = $env:APPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Roaming' }
    return Join-Path $base $script:ConfigDirName
}

function Get-ConfigPath {
    return Join-Path (Get-ConfigDir) $script:ConfigFileName
}

function Get-LogDir {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    return Join-Path $base "$script:ConfigDirName\logs"
}

function Read-Config {
    param([string]$Key)

    $configPath = Get-ConfigPath
    if (-not (Test-Path $configPath)) { return '' }

    $content = Get-Content $configPath -ErrorAction SilentlyContinue
    foreach ($line in $content) {
        if ($line -match "^$([regex]::Escape($Key))=(.*)$") {
            $value = $Matches[1] -replace '#.*$', ''
            return $value.Trim()
        }
    }
    return ''
}

function Write-Config {
    param([string]$Key, [string]$Value)

    $configDir = Get-ConfigDir
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $configPath = Get-ConfigPath
    if (-not (Test-Path $configPath)) {
        "$Key=$Value" | Set-Content $configPath
        return
    }

    $lines = Get-Content $configPath
    $found = $false
    $newLines = @()
    foreach ($line in $lines) {
        if ($line -match "^$Key=") {
            $newLines += "$Key=$Value"
            $found = $true
        } else {
            $newLines += $line
        }
    }
    if (-not $found) { $newLines += "$Key=$Value" }
    $newLines | Set-Content $configPath
}

function New-DefaultConfig {
    $configDir = Get-ConfigDir
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $configPath = Get-ConfigPath
    if (Test-Path $configPath) { return }

    @"
# claude-keeper configuration
# Run 'claude-keeper reconfigure' after changing update_time

# Enable or disable auto-updates (true/false)
enabled=true

# Time to run daily update (24h format, HH:MM)
update_time=09:00

# Installation method override (auto-detected if 'auto')
# Valid: auto, native, winget, npm, chocolatey
install_method=auto

# Log retention in days (0 = keep forever)
log_retention_days=30

# Pre-update hook (optional path to script run before upgrade)
pre_update_hook=

# Post-update hook (optional path to script run after upgrade)
post_update_hook=
"@ | Set-Content $configPath
}

function Read-ConfigOrDefault {
    param([string]$Key, [string]$Default)

    $value = Read-Config $Key
    if (-not $value) { return $Default }
    return $value
}
