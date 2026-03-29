# claude-keeper: Installation method detection (Windows)
# Detects how Claude Code was installed on this Windows system.

$ErrorActionPreference = 'Stop'

function Get-ClaudeInstallMethod {
    # 1. WinGet
    try {
        $wingetResult = winget list Anthropic.ClaudeCode 2>$null
        if ($LASTEXITCODE -eq 0 -and $wingetResult -match 'ClaudeCode') {
            return 'winget'
        }
    } catch {}

    # 2. npm
    try {
        $npmResult = npm list -g @anthropic-ai/claude-code 2>$null
        if ($LASTEXITCODE -eq 0 -and $npmResult -notmatch 'empty') {
            return 'npm'
        }
    } catch {}

    # 3. Chocolatey
    try {
        $chocoResult = choco list claude-code --local-only 2>$null
        if ($LASTEXITCODE -eq 0 -and $chocoResult -match 'claude') {
            return 'chocolatey'
        }
    } catch {}

    # 4. Native installer (well-known path)
    $nativePath = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
    if (Test-Path $nativePath) {
        return 'native'
    }

    # 5. Claude somewhere in PATH
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        return 'unknown_in_path'
    }

    return 'not_installed'
}

function Get-ClaudeVersion {
    try {
        $version = claude --version 2>$null
        return $version
    } catch {
        return ''
    }
}

function Get-MethodDescription {
    param([string]$Method)

    switch ($Method) {
        'winget'          { 'WinGet (winget upgrade Anthropic.ClaudeCode)' }
        'npm'             { 'npm (npm install -g @anthropic-ai/claude-code)' }
        'chocolatey'      { 'Chocolatey (choco upgrade claude-code)' }
        'native'          { 'Native installer (claude update)' }
        'unknown_in_path' { 'Unknown (claude found in PATH but install method unclear)' }
        'not_installed'   { 'Not installed (claude not found)' }
        default           { "Unknown method: $Method" }
    }
}
