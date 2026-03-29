# claude-keeper: Auto-updater for Claude Code CLI (Windows)
# Main CLI entry point.

$ErrorActionPreference = 'Stop'
$ClaudeKeeperVersion = '0.1.0'

# Resolve script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = if (Test-Path (Join-Path $ScriptDir 'lib')) {
    Join-Path $ScriptDir 'lib'
} elseif (Test-Path (Join-Path (Split-Path -Parent $ScriptDir) 'lib')) {
    Join-Path (Split-Path -Parent $ScriptDir) 'lib'
} else {
    Write-Error "Cannot find lib/ directory"
    exit 1
}

# Source library modules
. (Join-Path $LibDir 'config.ps1')
. (Join-Path $LibDir 'detect.ps1')
. (Join-Path $LibDir 'upgrade.ps1')

# -- Logging --

function Write-Log {
    param([string]$Level, [string]$Message)

    $logDir = Get-LogDir
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    $logFile = Join-Path $logDir "upgrade-$(Get-Date -Format 'yyyy-MM-dd').log"
    "$timestamp [$Level] $Message" | Add-Content $logFile
}

# -- Subcommands --

function Invoke-Run {
    $enabled = Read-ConfigOrDefault 'enabled' 'true'
    if ($enabled -ne 'true') {
        Write-Log 'INFO' 'Auto-update disabled in config. Skipping.'
        Write-Host 'Auto-update is disabled. Enable with: claude-keeper config set enabled true'
        return
    }

    $method = Read-ConfigOrDefault 'install_method' 'auto'
    if ($method -eq 'auto') {
        $method = Get-ClaudeInstallMethod
    }

    if ($method -eq 'not_installed') {
        Write-Log 'ERROR' 'Claude Code is not installed.'
        Write-Host 'Error: Claude Code is not installed on this system.'
        exit 1
    }

    $oldVersion = Get-ClaudeVersion

    # Pre-hook
    $preHook = Read-Config 'pre_update_hook'
    if ($preHook) {
        Write-Log 'INFO' "Running pre-update hook: $preHook"
        $hookResult = Invoke-Hook $preHook
        if ($hookResult -ne 0) {
            Write-Log 'ERROR' "Pre-update hook failed"
            Write-Host 'Pre-update hook failed. Aborting.'
            exit 1
        }
    }

    Write-Log 'INFO' "Upgrade started (method=$method)"
    Write-Host "Upgrading Claude Code (method: $method)..."

    $result = Invoke-ClaudeUpgrade -Method $method

    $newVersion = Get-ClaudeVersion

    if ($result.ExitCode -eq 0) {
        if ($oldVersion -eq $newVersion) {
            Write-Log 'INFO' "Upgrade check complete (method=$method): already up to date at $oldVersion"
        } else {
            Write-Log 'INFO' "Upgrade complete (method=$method): $oldVersion -> $newVersion"
        }
        Write-Host 'Done.'
    } else {
        Write-Log 'ERROR' "Upgrade failed (method=$method): exit_code=$($result.ExitCode)"
        Write-Host "Upgrade encountered an issue. Check logs."
        $script:UpgradeFailed = $true
    }

    # Post-hook
    $postHook = Read-Config 'post_update_hook'
    if ($postHook) {
        Write-Log 'INFO' "Running post-update hook: $postHook"
        $postResult = Invoke-Hook $postHook
        if ($postResult -ne 0) {
            Write-Log 'WARN' "Post-update hook failed (exit=$postResult)"
        }
    }

    if ($script:UpgradeFailed) {
        exit 1
    }
}

function Show-Status {
    Write-Host "claude-keeper v$ClaudeKeeperVersion"
    Write-Host ""

    $configPath = Get-ConfigPath
    if (Test-Path $configPath) {
        Write-Host "Config: $configPath"
    } else {
        Write-Host "Config: not found (run 'claude-keeper reconfigure' to create)"
    }

    Write-Host "Enabled: $(Read-ConfigOrDefault 'enabled' 'true')"
    Write-Host "Update time: $(Read-ConfigOrDefault 'update_time' '09:00')"

    $configMethod = Read-ConfigOrDefault 'install_method' 'auto'
    $detected = Get-ClaudeInstallMethod
    if ($configMethod -eq 'auto') {
        Write-Host "Install method: auto -> $(Get-MethodDescription $detected)"
    } else {
        Write-Host "Install method: $configMethod (override) [detected: $detected]"
    }

    $version = Get-ClaudeVersion
    Write-Host "Claude version: $(if ($version) { $version } else { 'not available' })"

    Write-Host ""
    # Scheduler status
    try {
        $task = schtasks /query /tn 'ClaudeKeeper' 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Scheduler: Task Scheduler (installed)"
        } else {
            Write-Host "Scheduler: not installed"
        }
    } catch {
        Write-Host "Scheduler: not installed"
    }
}

function Invoke-Test {
    Write-Host "claude-keeper dry run"
    Write-Host "====================="
    Write-Host ""

    $method = Get-ClaudeInstallMethod
    Write-Host "Detected install method: $(Get-MethodDescription $method)"
    Write-Host ""

    Write-Host "What would happen on 'claude-keeper run':"
    switch ($method) {
        'winget'          { Write-Host '  -> winget upgrade Anthropic.ClaudeCode' }
        'npm'             { Write-Host '  -> npm install -g @anthropic-ai/claude-code' }
        'chocolatey'      { Write-Host '  -> choco upgrade claude-code' }
        'native'          { Write-Host "  -> claude update (safety net; native auto-updates)" }
        'unknown_in_path' { Write-Host '  -> ERROR: Cannot determine upgrade command' }
        'not_installed'   { Write-Host '  -> ERROR: Claude Code not found' }
    }
    Write-Host ""

    $version = Get-ClaudeVersion
    Write-Host "Current version: $(if ($version) { $version } else { 'not available' })"
}

function Set-ConfigValue {
    param([string]$Key, [string]$Value)

    $validKeys = @('enabled', 'update_time', 'install_method', 'log_retention_days', 'pre_update_hook', 'post_update_hook')
    if ($Key -notin $validKeys) {
        Write-Host "Unknown config key: $Key"
        Write-Host "Valid keys: $($validKeys -join ', ')"
        exit 1
    }

    Write-Config $Key $Value
    Write-Host "Set $Key=$Value"
}

function Invoke-Reconfigure {
    Write-Host "Reconfiguring claude-keeper..."

    New-DefaultConfig

    $method = Get-ClaudeInstallMethod
    Write-Host "Detected install method: $(Get-MethodDescription $method)"

    $updateTime = Read-ConfigOrDefault 'update_time' '09:00'
    Write-Host "Update time: $updateTime"

    # Set up Task Scheduler
    $scriptPath = Join-Path $ScriptDir 'claude-keeper.ps1'
    if (Test-Path (Join-Path (Split-Path -Parent $ScriptDir) 'bin' 'claude-keeper.ps1')) {
        $scriptPath = Join-Path (Split-Path -Parent $ScriptDir) 'bin' 'claude-keeper.ps1'
    }

    try {
        schtasks /delete /tn 'ClaudeKeeper' /f 2>$null | Out-Null
    } catch {}

    schtasks /create /tn 'ClaudeKeeper' `
        /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" run" `
        /sc daily /st $updateTime /f | Out-Null

    Write-Host "Scheduler: Task Scheduler configured (daily at $updateTime)"
    Write-Host ""
    Write-Host "Done. Run 'claude-keeper status' to verify."
}

function Show-Help {
    @"
claude-keeper - Auto-updater for Claude Code CLI

USAGE:
    claude-keeper.ps1 <command> [options]

COMMANDS:
    run              Execute upgrade now (called by scheduler)
    status           Show install method, schedule status, last run
    test             Dry run: detect method, show what would happen
    config           Show current config
    config set K V   Update a config value
    logs             Show recent log entries
    reconfigure      Re-detect method, update scheduler
    uninstall        Remove claude-keeper completely
    version          Print version
    help             Show this help
"@
}

# -- Main --

$command = if ($args.Count -gt 0) { $args[0] } else { 'help' }

switch ($command) {
    'run'          { Invoke-Run }
    'status'       { Show-Status }
    'test'         { Invoke-Test }
    'config'       {
        if ($args.Count -gt 1 -and $args[1] -eq 'set') {
            if ($args.Count -lt 4) {
                Write-Host "Usage: claude-keeper config set KEY VALUE"
                exit 1
            }
            Set-ConfigValue $args[2] $args[3]
        } else {
            $configPath = Get-ConfigPath
            if (Test-Path $configPath) {
                Write-Host "Config: $configPath"
                Write-Host '---'
                Get-Content $configPath
            } else {
                Write-Host "No config file found. Run 'claude-keeper reconfigure' to create one."
            }
        }
    }
    'logs'         {
        $logDir = Get-LogDir
        if (Test-Path $logDir) {
            Get-ChildItem $logDir -Filter 'upgrade-*.log' | Sort-Object LastWriteTime -Descending |
                Select-Object -First 1 | ForEach-Object { Get-Content $_.FullName | Select-Object -Last 50 }
        } else {
            Write-Host 'No logs found.'
        }
    }
    'reconfigure'  { Invoke-Reconfigure }
    'uninstall'    {
        $uninstallScript = Join-Path $ScriptDir 'uninstall.ps1'
        if (-not (Test-Path $uninstallScript)) {
            $uninstallScript = Join-Path (Split-Path -Parent $ScriptDir) 'uninstall.ps1'
        }
        if (Test-Path $uninstallScript) {
            & $uninstallScript
        } else {
            Write-Host "Uninstall script not found."
            Write-Host "Manual removal:"
            Write-Host "  1. schtasks /delete /tn ClaudeKeeper /f"
            Write-Host "  2. Remove $env:LOCALAPPDATA\claude-keeper"
            Write-Host "  3. Remove $env:APPDATA\claude-keeper"
        }
    }
    { $_ -in 'version', '--version', '-v' } { Write-Host "claude-keeper v$ClaudeKeeperVersion" }
    { $_ -in 'help', '--help', '-h' }       { Show-Help }
    default {
        Write-Host "Unknown command: $command"
        Write-Host "Run 'claude-keeper help' for usage."
        exit 1
    }
}
