# claude-keeper

Auto-updater for Claude Code CLI. Keeps your Claude Code installation current without manual intervention.

Claude Code's **native installer** auto-updates, but **Homebrew**, **npm**, **WinGet**, and **Chocolatey** installations do **not**. claude-keeper fills that gap with a daily scheduled upgrade -- zero dependencies, user-space only, no sudo required.

## Quick Install

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/pritamneog/claude-keeper/main/install.sh | bash
```

With custom time:

```bash
curl -fsSL https://raw.githubusercontent.com/pritamneog/claude-keeper/main/install.sh | bash -s -- --time 14:00
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/pritamneog/claude-keeper/main/install.ps1 | iex
```

## How It Works

1. **Detects** how Claude Code was installed (Homebrew, npm, WinGet, Chocolatey, or native)
2. **Schedules** a daily upgrade check at your preferred time using OS-native schedulers
3. **Runs** the correct upgrade command for your installation method
4. **Logs** all upgrade attempts for troubleshooting

| Install Method | Upgrade Command | Auto-updates? |
|----------------|-----------------|---------------|
| Native | `claude update` | Yes (claude-keeper acts as safety net) |
| Homebrew | `brew upgrade claude-code` | No |
| npm | `npm install -g @anthropic-ai/claude-code` | No |
| WinGet | `winget upgrade Anthropic.ClaudeCode` | No |
| Chocolatey | `choco upgrade claude-code` | No |

## Commands

```bash
claude-keeper run              # Execute upgrade now
claude-keeper status           # Show install method, schedule, last run
claude-keeper test             # Dry run: show what would happen
claude-keeper config           # Show current config
claude-keeper config set K V   # Update a config value
claude-keeper logs             # Show recent log entries
claude-keeper logs --full      # Show all log entries
claude-keeper reconfigure      # Re-detect method, update scheduler
claude-keeper uninstall        # Remove completely
```

## Configuration

Config file location:
- **macOS/Linux**: `~/.config/claude-keeper/config`
- **Windows**: `%APPDATA%\claude-keeper\config`

```ini
# Enable or disable auto-updates (true/false)
enabled=true

# Time to run daily update (24h format, HH:MM)
update_time=09:00

# Installation method override (auto-detected if 'auto')
# Valid: auto, native, homebrew, npm, winget, chocolatey
install_method=auto

# Log retention in days (0 = keep forever)
log_retention_days=30

# Optional hooks (path to executable scripts)
pre_update_hook=
post_update_hook=
```

Change the schedule time:

```bash
claude-keeper config set update_time 14:00
claude-keeper reconfigure
```

## Scheduling

| Platform | Mechanism | No Admin Required |
|----------|-----------|-------------------|
| macOS | launchd (~/Library/LaunchAgents/) | Yes |
| Linux | systemd user timer (cron fallback) | Yes |
| Windows | Task Scheduler (user-level) | Yes |

Missed schedules (sleep/shutdown) are caught up automatically on macOS (launchd) and Linux (systemd `Persistent=true`).

## Uninstall

```bash
claude-keeper uninstall
```

Or manually:

```bash
# macOS/Linux
bash ~/.local/share/claude-keeper/uninstall.sh

# Windows PowerShell
& "$env:LOCALAPPDATA\claude-keeper\uninstall.ps1"
```

## Development

### Local Install (for testing)

```bash
git clone https://github.com/pritamneog/claude-keeper.git
cd claude-keeper
bash install.sh --local --time 09:00
```

### Run Tests

```bash
bash tests/test-config.sh
bash tests/test-detect.sh
bash tests/test-upgrade.sh
bash tests/test-scheduler.sh
```

## Project Structure

```
claude-keeper/
├── claude-keeper.sh            # CLI entry point (macOS/Linux)
├── claude-keeper.ps1           # CLI entry point (Windows)
├── install.sh / install.ps1    # One-command installers
├── uninstall.sh / uninstall.ps1
├── lib/
│   ├── detect.sh / detect.ps1      # Install method detection
│   ├── upgrade.sh / upgrade.ps1    # Upgrade dispatch
│   ├── config.sh / config.ps1      # Configuration management
│   ├── log.sh                      # Logging with rotation
│   ├── scheduler-macos.sh          # launchd plist management
│   └── scheduler-linux.sh          # systemd/cron management
├── tests/
│   ├── test-detect.sh
│   ├── test-upgrade.sh
│   ├── test-config.sh
│   └── test-scheduler.sh
└── README.md
```

## License

MIT
