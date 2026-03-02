# Mole Installer & Scheduler

Automated installer for [Mole](https://github.com/davydden/mole) with scheduled background maintenance tasks for macOS.

## What it does

Single self-contained script that:
- Installs Mole via Homebrew (if not already installed)
- Sets up 3 launchd jobs:
  - **Clean** (Sunday 2 AM) - Removes cache files, logs, etc.
  - **Optimize** (Wednesday 3 AM) - System optimization
  - **Update** (Saturday 12 PM) - Keeps Mole up to date
- Sends macOS notifications on completion
- All jobs run even if Mac was asleep (catches up on wake)

## Installation

```bash
bash install.sh
```

## Test Mode

Run jobs every 2 minutes for soak testing:

```bash
bash install.sh --test-mode
```

## Stop All Jobs

```bash
bash install.sh --stop
```

## Verification

Check running jobs:
```bash
sudo launchctl list | grep mole
launchctl list | grep mole
```

View logs:
```bash
tail -f /var/log/mole/clean.log
tail -f /var/log/mole/optimize.log
tail -f /tmp/mole-update.log
```

Test manually:
```bash
sudo launchctl kickstart system/com.mole.clean
sudo launchctl kickstart system/com.mole.optimize
```

## Uninstall

```bash
sudo launchctl bootout system/com.mole.clean
sudo launchctl bootout system/com.mole.optimize
launchctl bootout gui/$(id -u)/com.mole.update
sudo rm -f /Library/LaunchDaemons/com.mole.{clean,optimize}.plist
rm -f ~/Library/LaunchAgents/com.mole.update.plist
sudo rm -rf /var/log/mole
```

## Requirements

- macOS
- Homebrew installed
- Run as regular user (not root)

## Family Deployment

Drop `install.sh` on any family Mac and run it. Jobs will automatically:
- Run in background with low priority
- Send notifications showing what was done
- Keep Mole updated weekly
