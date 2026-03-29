# claude-keeper: Core upgrade logic (Windows)

$ErrorActionPreference = 'Stop'

function Invoke-ClaudeUpgrade {
    param([string]$Method)

    $output = ''
    $exitCode = 0

    switch ($Method) {
        'native' {
            try {
                $output = claude update 2>&1 | Out-String
            } catch {
                $output = $_.Exception.Message
                $exitCode = 1
            }
        }
        'winget' {
            try {
                $output = winget upgrade Anthropic.ClaudeCode --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
            } catch {
                $output = $_.Exception.Message
                $exitCode = 1
            }
        }
        'npm' {
            try {
                $output = npm install -g @anthropic-ai/claude-code 2>&1 | Out-String
            } catch {
                $output = $_.Exception.Message
                $exitCode = 1
            }
        }
        'chocolatey' {
            try {
                $output = choco upgrade claude-code -y 2>&1 | Out-String
            } catch {
                $output = $_.Exception.Message
                $exitCode = 1
            }
        }
        'unknown_in_path' {
            $output = "Claude found in PATH but install method unknown. Set 'install_method' in config."
            $exitCode = 1
        }
        'not_installed' {
            $output = 'Claude Code is not installed.'
            $exitCode = 1
        }
        default {
            $output = "Unknown install method: $Method"
            $exitCode = 1
        }
    }

    return @{
        Output   = $output
        ExitCode = $exitCode
    }
}

function Invoke-Hook {
    param([string]$HookPath)

    if (-not $HookPath -or -not (Test-Path $HookPath)) {
        if ($HookPath -and -not (Test-Path $HookPath)) {
            Write-Warning "Hook not found: $HookPath"
            return 1
        }
        return 0
    }

    try {
        & $HookPath
        return $LASTEXITCODE
    } catch {
        Write-Warning "Hook failed: $($_.Exception.Message)"
        return 1
    }
}
