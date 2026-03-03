#!/usr/bin/env bash
set -euo pipefail

# ─── Mole Scheduler ──────────────────────────────────────────────────────────
# Sets up launchd jobs for Mole: clean, optimize, update.
# Safe to re-run — always (re)configures schedules.
# Usage: bash install.sh [--configure] [--debug] [--status] [--stop]
#                        [--uninstall] [--test-mode] [--help]
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Mole Scheduler — launchd job installer for Mole (https://github.com/davydden/mole)

Usage:
  bash install.sh [flags]

Flags:
  (none)         Install with default schedules (clean Sun 2AM, optimize Wed 3AM, update Sat noon)
  --configure    Choose schedules interactively before installing
  --status       Show installed schedules and log info (read-only)
  --stop         Unload all jobs without removing plists
  --uninstall    Unload all jobs and remove all plists
  --test-mode    Install with 2-minute intervals for soak testing
  --debug        Print verbose output including plist XML and env info
  --help         Show this help

Flags can be combined: bash install.sh --configure --debug
EOF
}

# ─── Argument parsing ─────────────────────────────────────────────────────────

TEST_MODE=false
STOP_MODE=false
CONFIGURE_MODE=false
DEBUG_MODE=false
STATUS_MODE=false
UNINSTALL_MODE=false

for arg in "$@"; do
    case "$arg" in
        --test-mode)  TEST_MODE=true ;;
        --stop)       STOP_MODE=true ;;
        --configure)  CONFIGURE_MODE=true ;;
        --debug)      DEBUG_MODE=true ;;
        --status)     STATUS_MODE=true ;;
        --uninstall)  UNINSTALL_MODE=true ;;
        --help)       usage; exit 0 ;;
        *)
            echo "Unknown flag: $arg"
            echo "Run 'bash install.sh --help' for usage."
            exit 1
            ;;
    esac
done

# ─── Debug mode ───────────────────────────────────────────────────────────────

if [ "$DEBUG_MODE" = true ]; then
    echo "==> Debug mode enabled"
    echo "  User: $(whoami)  UID: $(id -u)"
    echo "  Shell: $SHELL"
    set -x
fi

# ─── Stop mode ────────────────────────────────────────────────────────────────

if [ "$STOP_MODE" = true ]; then
    echo "Stopping all Mole scheduled jobs..."
    echo ""
    sudo launchctl bootout system/com.mole.clean 2>/dev/null && echo "  ✓ Stopped com.mole.clean" || echo "  • com.mole.clean not running"
    sudo launchctl bootout system/com.mole.optimize 2>/dev/null && echo "  ✓ Stopped com.mole.optimize" || echo "  • com.mole.optimize not running"
    launchctl bootout "gui/$(id -u)/com.mole.update" 2>/dev/null && echo "  ✓ Stopped com.mole.update" || echo "  • com.mole.update not running"
    echo ""
    echo "All jobs stopped. To restart:"
    echo "  bash install.sh          (production mode)"
    echo "  bash install.sh --test-mode   (test mode)"
    exit 0
fi

# ─── Uninstall mode ───────────────────────────────────────────────────────────

if [ "$UNINSTALL_MODE" = true ]; then
    echo "Uninstalling all Mole scheduled jobs..."
    echo ""
    sudo launchctl bootout system/com.mole.clean 2>/dev/null && echo "  ✓ Unloaded com.mole.clean" || echo "  • com.mole.clean not loaded"
    sudo launchctl bootout system/com.mole.optimize 2>/dev/null && echo "  ✓ Unloaded com.mole.optimize" || echo "  • com.mole.optimize not loaded"
    launchctl bootout "gui/$(id -u)/com.mole.update" 2>/dev/null && echo "  ✓ Unloaded com.mole.update" || echo "  • com.mole.update not loaded"
    echo ""
    sudo rm -f /Library/LaunchDaemons/com.mole.clean.plist && echo "  ✓ Removed com.mole.clean.plist" || true
    sudo rm -f /Library/LaunchDaemons/com.mole.optimize.plist && echo "  ✓ Removed com.mole.optimize.plist" || true
    rm -f ~/Library/LaunchAgents/com.mole.update.plist && echo "  ✓ Removed com.mole.update.plist" || true
    echo ""
    echo "  Logs remain at /var/log/mole/ and /tmp/mole-update.log"
    echo "  To remove logs: sudo rm -rf /var/log/mole && rm -f /tmp/mole-update.log"
    exit 0
fi

# ─── Status mode ──────────────────────────────────────────────────────────────

if [ "$STATUS_MODE" = true ]; then
    echo "Mole Scheduler — Status"
    echo ""

    # Helper: extract StartCalendarInterval from a plist and return human label
    describe_schedule() {
        local plist="$1"
        if [ ! -f "$plist" ]; then
            echo "not installed"
            return
        fi
        # Check for StartInterval (test/daily interval mode)
        local interval
        interval=$(plutil -p "$plist" 2>/dev/null | grep -A1 '"StartInterval"' | grep 'integer' | grep -oE '[0-9]+' || true)
        if [ -n "$interval" ]; then
            echo "Every ${interval}s (test/interval mode)"
            return
        fi
        # Parse StartCalendarInterval
        local weekday hour day
        weekday=$(plutil -p "$plist" 2>/dev/null | grep -A5 'StartCalendarInterval' | grep '"Weekday"' | grep -oE '[0-9]+' || true)
        day=$(plutil -p "$plist" 2>/dev/null | grep -A5 'StartCalendarInterval' | grep '"Day"' | grep -oE '[0-9]+' || true)
        hour=$(plutil -p "$plist" 2>/dev/null | grep -A5 'StartCalendarInterval' | grep '"Hour"' | grep -oE '[0-9]+' || true)

        local hour_fmt=""
        if [ -n "$hour" ]; then
            if [ "$hour" -eq 0 ]; then
                hour_fmt="12:00 AM"
            elif [ "$hour" -lt 12 ]; then
                hour_fmt="${hour}:00 AM"
            elif [ "$hour" -eq 12 ]; then
                hour_fmt="12:00 PM"
            else
                hour_fmt="$((hour - 12)):00 PM"
            fi
        fi

        if [ -n "$weekday" ]; then
            local day_names=(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
            echo "Weekly ${day_names[$weekday]} ${hour_fmt}"
        elif [ -n "$day" ]; then
            echo "Monthly day-${day} ${hour_fmt}"
        elif [ -n "$hour" ]; then
            echo "Daily ${hour_fmt}"
        else
            echo "unknown schedule"
        fi
    }

    # Check launchctl load status
    check_loaded() {
        local label="$1"
        local domain="$2"
        if launchctl print "${domain}/${label}" &>/dev/null 2>&1; then
            echo "LOADED"
        elif sudo launchctl print "${domain}/${label}" &>/dev/null 2>&1; then
            echo "LOADED"
        else
            echo "NOT LOADED"
        fi
    }

    CLEAN_PLIST="/Library/LaunchDaemons/com.mole.clean.plist"
    OPT_PLIST="/Library/LaunchDaemons/com.mole.optimize.plist"
    UPD_PLIST="$HOME/Library/LaunchAgents/com.mole.update.plist"

    CLEAN_STATUS=$(check_loaded com.mole.clean system 2>/dev/null || echo "NOT LOADED")
    OPT_STATUS=$(check_loaded com.mole.optimize system 2>/dev/null || echo "NOT LOADED")
    UPD_STATUS=$(check_loaded com.mole.update "gui/$(id -u)" 2>/dev/null || echo "NOT LOADED")

    CLEAN_SCHED=$(describe_schedule "$CLEAN_PLIST")
    OPT_SCHED=$(describe_schedule "$OPT_PLIST")
    UPD_SCHED=$(describe_schedule "$UPD_PLIST")

    printf "  %-22s %-12s %s\n" "com.mole.clean" "$CLEAN_STATUS" "$CLEAN_SCHED"
    printf "  %-22s %-12s %s\n" "com.mole.optimize" "$OPT_STATUS" "$OPT_SCHED"
    printf "  %-22s %-12s %s\n" "com.mole.update" "$UPD_STATUS" "$UPD_SCHED"
    echo ""
    echo "Logs:"

    for logfile in /var/log/mole/clean.log /var/log/mole/optimize.log /tmp/mole-update.log; do
        if [ -f "$logfile" ]; then
            # macOS stat: last modified time
            mod=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$logfile" 2>/dev/null || echo "unknown")
            printf "  %-40s (last modified: %s)\n" "$logfile" "$mod"
        else
            printf "  %-40s (not found)\n" "$logfile"
        fi
    done

    exit 0
fi

# ─── Refuse to run as root ────────────────────────────────────────────────────

if [[ $EUID -eq 0 ]]; then
    echo "Error: Do not run this script as root (Homebrew won't work)."
    echo "Run as your normal user: bash install.sh"
    exit 1
fi

# ─── Check for Homebrew ───────────────────────────────────────────────────────

if ! command -v brew &>/dev/null; then
    echo "Error: Homebrew is not installed."
    echo "Install it first:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi

# ─── Detect arch ──────────────────────────────────────────────────────────────

BREW_PREFIX="$(brew --prefix)"
COMBINED_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [ "$DEBUG_MODE" = true ]; then
    echo "  Brew prefix: $BREW_PREFIX"
    echo "  Combined PATH: $COMBINED_PATH"
fi

# ─── Schedule defaults ────────────────────────────────────────────────────────
# clean:    weekly, Sunday (0), 2 AM
# optimize: weekly, Wednesday (3), 3 AM
# update:   weekly, Saturday (6), noon (12)
#
# SCHED_TYPE: weekly | daily | monthly | skip
# For weekly: WEEKDAY (0=Sun..6=Sat), HOUR
# For daily:  HOUR
# For monthly: HOUR

CLEAN_TYPE="weekly"; CLEAN_WEEKDAY=0; CLEAN_HOUR=2
OPT_TYPE="weekly";   OPT_WEEKDAY=3;   OPT_HOUR=3
UPD_TYPE="weekly";   UPD_WEEKDAY=6;   UPD_HOUR=12

# ─── Load saved schedule preferences ─────────────────────────────────────────
CONFIG_DIR="$HOME/.config/mole"
CONFIG_FILE="$CONFIG_DIR/schedule"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

type_to_choice() {
    case "$1" in
        weekly)  echo 1 ;;
        daily)   echo 2 ;;
        monthly) echo 3 ;;
        skip)    echo 4 ;;
        *)       echo 1 ;;
    esac
}

# ─── Configure mode ───────────────────────────────────────────────────────────

if [ "$CONFIGURE_MODE" = true ]; then
    echo "Mole Scheduler — Configure Schedules"
    echo ""

    prompt_schedule() {
        local job_label="$1"   # e.g. "mo clean"
        local default_choice="$2"  # 1-4
        local w1_label="$3"    # weekly label e.g. "Sunday 2 AM"
        local d_label="$4"     # daily label  e.g. "2 AM"
        local m_label="$5"     # monthly label e.g. "1st of month 2 AM"

        echo "  ${job_label}:" >&2
        echo "    1) Weekly  — ${w1_label}  (default)" >&2
        echo "    2) Daily   — ${d_label}" >&2
        echo "    3) Monthly — ${m_label}" >&2
        echo "    4) Skip    — don't schedule" >&2

        local choice=""
        while true; do
            printf "  Choice [%s]: " "$default_choice" >&2
            read -r choice </dev/tty
            choice="${choice:-$default_choice}"
            case "$choice" in
                1|2|3|4) break ;;
                *) echo "    Please enter 1, 2, 3, or 4." >&2 ;;
            esac
        done
        echo "" >&2
        echo "$choice"
    }

    # Clean
    CLEAN_CHOICE=$(prompt_schedule "mo clean" "$(type_to_choice "$CLEAN_TYPE")" "Sunday 2 AM" "2 AM" "1st of month 2 AM")
    case "$CLEAN_CHOICE" in
        1) CLEAN_TYPE="weekly";  CLEAN_WEEKDAY=0; CLEAN_HOUR=2 ;;
        2) CLEAN_TYPE="daily";   CLEAN_HOUR=2 ;;
        3) CLEAN_TYPE="monthly"; CLEAN_HOUR=2 ;;
        4) CLEAN_TYPE="skip" ;;
    esac

    # Optimize
    OPT_CHOICE=$(prompt_schedule "mo optimize" "$(type_to_choice "$OPT_TYPE")" "Wednesday 3 AM" "3 AM" "1st of month 3 AM")
    case "$OPT_CHOICE" in
        1) OPT_TYPE="weekly";  OPT_WEEKDAY=3; OPT_HOUR=3 ;;
        2) OPT_TYPE="daily";   OPT_HOUR=3 ;;
        3) OPT_TYPE="monthly"; OPT_HOUR=3 ;;
        4) OPT_TYPE="skip" ;;
    esac

    # Update
    UPD_CHOICE=$(prompt_schedule "brew upgrade mole" "$(type_to_choice "$UPD_TYPE")" "Saturday noon" "noon" "1st of month noon")
    case "$UPD_CHOICE" in
        1) UPD_TYPE="weekly";  UPD_WEEKDAY=6; UPD_HOUR=12 ;;
        2) UPD_TYPE="daily";   UPD_HOUR=12 ;;
        3) UPD_TYPE="monthly"; UPD_HOUR=12 ;;
        4) UPD_TYPE="skip" ;;
    esac

    # Summary
    echo "  Schedule summary:"
    fmt_schedule() {
        local type="$1" weekday="${2:-}" hour="${3:-}"
        local day_names=(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
        local hour_fmt=""
        if [ -n "$hour" ]; then
            if [ "$hour" -eq 0 ]; then hour_fmt="12:00 AM"
            elif [ "$hour" -lt 12 ]; then hour_fmt="${hour}:00 AM"
            elif [ "$hour" -eq 12 ]; then hour_fmt="12:00 PM"
            else hour_fmt="$((hour-12)):00 PM"; fi
        fi
        case "$type" in
            weekly)  echo "Weekly  ${day_names[$weekday]} ${hour_fmt}" ;;
            daily)   echo "Daily   ${hour_fmt}" ;;
            monthly) echo "Monthly 1st-of-month ${hour_fmt}" ;;
            skip)    echo "Skipped" ;;
        esac
    }
    printf "    %-14s %s\n" "mo clean"     "$(fmt_schedule "$CLEAN_TYPE" "${CLEAN_WEEKDAY:-}" "${CLEAN_HOUR:-}")"
    printf "    %-14s %s\n" "mo optimize"  "$(fmt_schedule "$OPT_TYPE"   "${OPT_WEEKDAY:-}"   "${OPT_HOUR:-}")"
    printf "    %-14s %s\n" "brew upgrade" "$(fmt_schedule "$UPD_TYPE"   "${UPD_WEEKDAY:-}"   "${UPD_HOUR:-}")"
    echo ""

    printf "  Proceed? [Y/n]: "
    read -r confirm </dev/tty
    confirm="${confirm:-Y}"
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo "Aborted."
        exit 0
    fi

    # Save schedule preferences for next run
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
# Mole schedule preferences — saved $(date "+%Y-%m-%d %H:%M")
CLEAN_TYPE="$CLEAN_TYPE"
CLEAN_WEEKDAY=${CLEAN_WEEKDAY:-0}
CLEAN_HOUR=${CLEAN_HOUR:-2}
OPT_TYPE="$OPT_TYPE"
OPT_WEEKDAY=${OPT_WEEKDAY:-3}
OPT_HOUR=${OPT_HOUR:-3}
UPD_TYPE="$UPD_TYPE"
UPD_WEEKDAY=${UPD_WEEKDAY:-6}
UPD_HOUR=${UPD_HOUR:-12}
EOF
    echo "  Preferences saved to $CONFIG_FILE"
    echo ""
fi

if [ "$TEST_MODE" = true ]; then
    echo "Warning: TEST MODE ENABLED - Jobs will run every 2 minutes"
    echo ""
fi

# ─── Install Mole + dependencies ─────────────────────────────────────────────

echo "==> Checking Mole and dependencies..."
for pkg in mole jq bc; do
    if brew list "$pkg" &>/dev/null; then
        echo "  $pkg: already installed"
    else
        echo "  $pkg: installing..."
        brew install "$pkg"
    fi
done

MO_PATH="$(command -v mo)"
echo ""
echo "Homebrew prefix: $BREW_PREFIX"
echo "Mole binary: $MO_PATH"

# ─── Create log dir ───────────────────────────────────────────────────────────

echo ""
echo "==> Creating /var/log/mole (requires sudo)..."
sudo mkdir -p /var/log/mole

# ─── Plist helpers ────────────────────────────────────────────────────────────

# Build the StartCalendarInterval or StartInterval XML block
build_schedule_xml() {
    local type="$1"
    local weekday="${2:-0}"
    local hour="${3:-0}"

    if [ "$TEST_MODE" = true ]; then
        printf '    <key>StartInterval</key>\n    <integer>120</integer>\n'
        return
    fi

    case "$type" in
        weekly)
            printf '    <key>StartCalendarInterval</key>\n    <dict>\n'
            printf '        <key>Weekday</key>\n        <integer>%d</integer>\n' "$weekday"
            printf '        <key>Hour</key>\n        <integer>%d</integer>\n' "$hour"
            printf '        <key>Minute</key>\n        <integer>0</integer>\n'
            printf '    </dict>\n'
            ;;
        daily)
            printf '    <key>StartCalendarInterval</key>\n    <dict>\n'
            printf '        <key>Hour</key>\n        <integer>%d</integer>\n' "$hour"
            printf '        <key>Minute</key>\n        <integer>0</integer>\n'
            printf '    </dict>\n'
            ;;
        monthly)
            printf '    <key>StartCalendarInterval</key>\n    <dict>\n'
            printf '        <key>Day</key>\n        <integer>1</integer>\n'
            printf '        <key>Hour</key>\n        <integer>%d</integer>\n' "$hour"
            printf '        <key>Minute</key>\n        <integer>0</integer>\n'
            printf '    </dict>\n'
            ;;
    esac
}

write_daemon_plist() {
    local label="$1"
    local dest="$2"
    local cmd_string="$3"
    local log_path="$4"
    local schedule_xml="$5"

    local plist_content
    plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>${cmd_string}</string>
    </array>
${schedule_xml}    <key>StandardOutPath</key>
    <string>${log_path}</string>
    <key>StandardErrorPath</key>
    <string>${log_path}</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>
</dict>
</plist>"

    if [ "$DEBUG_MODE" = true ]; then
        echo "--- Plist: $dest ---"
        echo "$plist_content"
        echo "---"
        echo "$plist_content" | sudo tee "$dest"
    else
        echo "$plist_content" | sudo tee "$dest" > /dev/null
    fi
}

write_agent_plist() {
    local label="$1"
    local dest="$2"
    local cmd_string="$3"
    local log_path="$4"
    local schedule_xml="$5"

    local plist_content
    plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>${cmd_string}</string>
    </array>
${schedule_xml}    <key>StandardOutPath</key>
    <string>${log_path}</string>
    <key>StandardErrorPath</key>
    <string>${log_path}</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>
</dict>
</plist>"

    if [ "$DEBUG_MODE" = true ]; then
        echo "--- Plist: $dest ---"
        echo "$plist_content"
        echo "---"
        echo "$plist_content" | tee "$dest"
    else
        echo "$plist_content" > "$dest"
    fi
}

# ─── Install LaunchDaemons (clean + optimize) ─────────────────────────────────

echo ""
echo "==> Installing LaunchDaemons..."

# Shared inline command strings (XML-escaped for plist)
CLEAN_CMD='export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; LOGUSER=$(stat -f%Su /dev/console 2>/dev/null || echo "root"); [[ "$LOGUSER" =~ ^[a-zA-Z0-9._-]+$ ]] || LOGUSER=root; LOGHOME=$(dscl . -read /Users/"$LOGUSER" NFSHomeDirectory 2>/dev/null | cut -d" " -f2); export HOME=${LOGHOME:-/var/root}; TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S"); echo "[$TIMESTAMP] Starting mo clean" >> /var/log/mole/clean.log; OUTPUT=$(mo clean 2>&1); EXITCODE=$?; echo "$OUTPUT" >> /var/log/mole/clean.log; echo "[$TIMESTAMP] Finished (exit code: $EXITCODE)" >> /var/log/mole/clean.log; if [ $EXITCODE -eq 0 ]; then SAVED=$(echo "$OUTPUT" | grep "Space freed:" | grep -oE "[0-9]+(\.[0-9]+)?\s*(GB|MB|KB|B)" | head -1); if [ "$LOGUSER" != "root" ] && [ -n "$SAVED" ]; then LOGUID=$(id -u "$LOGUSER"); launchctl asuser "$LOGUID" sudo -u "$LOGUSER" osascript -e "display notification \"Freed: $SAVED\" with title \"Mole Clean Complete\"" 2>> /var/log/mole/clean.log || true; fi; fi'

OPT_CMD='export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; LOGUSER=$(stat -f%Su /dev/console 2>/dev/null || echo "root"); [[ "$LOGUSER" =~ ^[a-zA-Z0-9._-]+$ ]] || LOGUSER=root; LOGHOME=$(dscl . -read /Users/"$LOGUSER" NFSHomeDirectory 2>/dev/null | cut -d" " -f2); export HOME=${LOGHOME:-/var/root}; TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S"); echo "[$TIMESTAMP] Starting mo optimize" >> /var/log/mole/optimize.log; OUTPUT=$(mo optimize 2>&1); EXITCODE=$?; echo "$OUTPUT" >> /var/log/mole/optimize.log; echo "[$TIMESTAMP] Finished (exit code: $EXITCODE)" >> /var/log/mole/optimize.log; if [ $EXITCODE -eq 0 ] && [ "$LOGUSER" != "root" ]; then LOGUID=$(id -u "$LOGUSER"); launchctl asuser "$LOGUID" sudo -u "$LOGUSER" osascript -e "display notification \"Optimize completed\" with title \"Mole Optimize Complete\"" 2>> /var/log/mole/optimize.log || true; fi'

UPD_CMD='export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S"); echo "[$TIMESTAMP] Starting brew upgrade mole" >> /tmp/mole-update.log; export HOMEBREW_NO_AUTO_UPDATE=1; OUTPUT=$(brew upgrade mole 2>&1); EXITCODE=$?; echo "$OUTPUT" >> /tmp/mole-update.log; echo "[$TIMESTAMP] Finished (exit code: $EXITCODE)" >> /tmp/mole-update.log; if [ $EXITCODE -eq 0 ]; then if echo "$OUTPUT" | grep -qi "already"; then MSG="Already up to date"; else MSG="Updated successfully"; fi; osascript -e "display notification \"$MSG\" with title \"Mole Update\"" 2>/dev/null || true; else MSG="Update failed (check log)"; osascript -e "display notification \"$MSG\" with title \"Mole Update\"" 2>/dev/null || true; fi'

# XML-escape the command strings for embedding in plist
xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    echo "$s"
}

CLEAN_CMD_XML=$(xml_escape "$CLEAN_CMD")
OPT_CMD_XML=$(xml_escape "$OPT_CMD")
UPD_CMD_XML=$(xml_escape "$UPD_CMD")

# --- com.mole.clean ---
if [ "$CLEAN_TYPE" != "skip" ]; then
    CLEAN_SCHED_XML=$(build_schedule_xml "$CLEAN_TYPE" "${CLEAN_WEEKDAY:-0}" "${CLEAN_HOUR:-2}")
    write_daemon_plist "com.mole.clean" "/Library/LaunchDaemons/com.mole.clean.plist" \
        "$CLEAN_CMD_XML" "/var/log/mole/clean.log" "$CLEAN_SCHED_XML"
    sudo chown root:wheel /Library/LaunchDaemons/com.mole.clean.plist
    sudo chmod 644 /Library/LaunchDaemons/com.mole.clean.plist
    echo "  com.mole.clean.plist installed"
else
    echo "  com.mole.clean: skipped"
fi

# --- com.mole.optimize ---
if [ "$OPT_TYPE" != "skip" ]; then
    OPT_SCHED_XML=$(build_schedule_xml "$OPT_TYPE" "${OPT_WEEKDAY:-3}" "${OPT_HOUR:-3}")
    write_daemon_plist "com.mole.optimize" "/Library/LaunchDaemons/com.mole.optimize.plist" \
        "$OPT_CMD_XML" "/var/log/mole/optimize.log" "$OPT_SCHED_XML"
    sudo chown root:wheel /Library/LaunchDaemons/com.mole.optimize.plist
    sudo chmod 644 /Library/LaunchDaemons/com.mole.optimize.plist
    echo "  com.mole.optimize.plist installed"
else
    echo "  com.mole.optimize: skipped"
fi

# ─── Install LaunchAgent (update — runs as user) ──────────────────────────────

echo ""
echo "==> Installing LaunchAgent..."
mkdir -p ~/Library/LaunchAgents

if [ "$UPD_TYPE" != "skip" ]; then
    UPD_SCHED_XML=$(build_schedule_xml "$UPD_TYPE" "${UPD_WEEKDAY:-6}" "${UPD_HOUR:-12}")
    write_agent_plist "com.mole.update" "$HOME/Library/LaunchAgents/com.mole.update.plist" \
        "$UPD_CMD_XML" "/tmp/mole-update.log" "$UPD_SCHED_XML"
    echo "  com.mole.update.plist installed"
else
    echo "  com.mole.update: skipped"
fi

# ─── Load jobs ────────────────────────────────────────────────────────────────

echo ""
echo "==> Loading launchd jobs..."

# Unload existing (idempotent)
sudo launchctl bootout system/com.mole.clean 2>/dev/null || true
sudo launchctl bootout system/com.mole.optimize 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.mole.update" 2>/dev/null || true

# Load new (only if not skipped)
[ "$CLEAN_TYPE" != "skip" ] && sudo launchctl bootstrap system /Library/LaunchDaemons/com.mole.clean.plist
[ "$OPT_TYPE"   != "skip" ] && sudo launchctl bootstrap system /Library/LaunchDaemons/com.mole.optimize.plist
[ "$UPD_TYPE"   != "skip" ] && launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.mole.update.plist

echo "  All jobs loaded"

# ─── Summary ─────────────────────────────────────────────────────────────────

fmt_sched_summary() {
    local type="$1" weekday="${2:-}" hour="${3:-}"
    local day_names=(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
    local hour_fmt=""
    if [ -n "$hour" ]; then
        if [ "$hour" -eq 0 ]; then hour_fmt="12:00 AM"
        elif [ "$hour" -lt 12 ]; then hour_fmt="${hour}:00 AM"
        elif [ "$hour" -eq 12 ]; then hour_fmt="12:00 PM"
        else hour_fmt="$((hour-12)):00 PM"; fi
    fi
    case "$type" in
        weekly)  printf "Weekly  %-12s %s" "${day_names[$weekday]}" "$hour_fmt" ;;
        daily)   printf "Daily   %s" "$hour_fmt" ;;
        monthly) printf "Monthly 1st-of-month %s" "$hour_fmt" ;;
        skip)    printf "Skipped" ;;
    esac
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ "$TEST_MODE" = true ]; then
    echo "  Mole Scheduler — Complete (TEST MODE)"
else
    echo "  Mole Scheduler — Complete"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""
if [ "$TEST_MODE" = true ]; then
    echo "  Schedule (every 2 minutes — test mode):"
    [ "$CLEAN_TYPE" != "skip" ] && echo "    mo clean      Every 2 min  (root, LaunchDaemon)"
    [ "$OPT_TYPE"   != "skip" ] && echo "    mo optimize   Every 2 min  (root, LaunchDaemon)"
    [ "$UPD_TYPE"   != "skip" ] && echo "    brew upgrade  Every 2 min  (user, LaunchAgent)"
else
    echo "  Schedule:"
    [ "$CLEAN_TYPE" != "skip" ] && printf "    %-14s %s\n" "mo clean"     "$(fmt_sched_summary "$CLEAN_TYPE" "${CLEAN_WEEKDAY:-}" "${CLEAN_HOUR:-}")"
    [ "$OPT_TYPE"   != "skip" ] && printf "    %-14s %s\n" "mo optimize"  "$(fmt_sched_summary "$OPT_TYPE"   "${OPT_WEEKDAY:-}"   "${OPT_HOUR:-}")"
    [ "$UPD_TYPE"   != "skip" ] && printf "    %-14s %s\n" "brew upgrade" "$(fmt_sched_summary "$UPD_TYPE"   "${UPD_WEEKDAY:-}"   "${UPD_HOUR:-}")"
fi
echo ""
echo "  Logs (timestamped):"
echo "    /var/log/mole/clean.log"
echo "    /var/log/mole/optimize.log"
echo "    /tmp/mole-update.log"
echo ""
echo "  Verify:"
echo "    sudo launchctl list | grep mole"
echo "    launchctl list | grep mole"
echo ""
echo "  Test (will send notifications):"
echo "    sudo launchctl kickstart system/com.mole.clean"
echo "    sudo launchctl kickstart system/com.mole.optimize"
echo ""
echo "  Uninstall:"
echo "    bash install.sh --uninstall"
echo ""
