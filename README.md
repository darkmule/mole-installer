# Mole Scheduler

A simple macOS scheduler for [Mole](https://github.com/davydden/mole). Configure and automate Mole's clean, optimize, and update tasks using launchd.

## What it does

Single self-contained script that:
- Installs Mole via Homebrew (if not already installed)
- Sets up 3 launchd jobs with configurable schedules:
  - **Clean** (`mo clean`) — removes cache files, logs, etc.
  - **Optimize** (`mo optimize`) — system optimization
  - **Update** (`brew upgrade mole`) — keeps Mole up to date
- Sends macOS notifications on completion
- Jobs run even if Mac was asleep (catches up on wake)

## Installation

```bash
bash install.sh
```

Default schedules: Clean on Sunday 2 AM, Optimize on Wednesday 3 AM, Update on Saturday noon.

## Configure Schedules

Choose schedules interactively before installing:

```bash
bash install.sh --configure
```

Presents a numbered menu for each job (Weekly / Daily / Monthly / Skip) with sensible defaults. Press Enter to accept defaults.

## Check Status

Show currently installed schedules and log info without modifying anything:

```bash
bash install.sh --status
```

## Test Mode

Run all jobs every 2 minutes for soak testing:

```bash
bash install.sh --test-mode
```

## Stop All Jobs

Unload jobs without removing plists:

```bash
bash install.sh --stop
```

## Uninstall

Remove all jobs and plists:

```bash
bash install.sh --uninstall
```

## Debug Mode

Print verbose output including plist XML and env info:

```bash
bash install.sh --debug
bash install.sh --configure --debug
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

## Requirements

- macOS
- Homebrew installed
- Run as regular user (not root)

## License

MIT — see [LICENSE](LICENSE)
