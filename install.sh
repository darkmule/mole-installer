#!/usr/bin/env bash
set -euo pipefail

# ─── Mole Installer & Scheduler ─────────────────────────────────────────────
# Installs Mole (via Homebrew) and sets up launchd jobs for clean, optimize,
# and update. Safe to re-run — always (re)configures schedules.
# ─────────────────────────────────────────────────────────────────────────────

# Parse arguments
TEST_MODE=false
STOP_MODE=false

if [[ "${1:-}" == "--stop" ]]; then
    STOP_MODE=true
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

if [[ "${1:-}" == "--test-mode" ]]; then
    TEST_MODE=true
    echo "⚠️  TEST MODE ENABLED - Jobs will run every 2 minutes"
    echo ""
fi

# 1. Refuse to run as root
if [[ $EUID -eq 0 ]]; then
    echo "Error: Do not run this script as root (Homebrew won't work)."
    echo "Run as your normal user: bash install.sh"
    exit 1
fi

# 2. Check for Homebrew
if ! command -v brew &>/dev/null; then
    echo "Error: Homebrew is not installed."
    echo "Install it first:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi

# 3. Detect arch — both paths included in plists so they work on any Mac
BREW_PREFIX="$(brew --prefix)"
COMBINED_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
echo "Homebrew prefix: $BREW_PREFIX"

# 4. Install Mole + dependencies if not already installed
echo ""
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
echo "Mole binary: $MO_PATH"

# 5. Create log dir
echo ""
echo "==> Creating /var/log/mole (requires sudo)..."
sudo mkdir -p /var/log/mole

# 6. Install LaunchDaemons (run as root) for clean + optimize

echo ""
echo "==> Installing LaunchDaemons..."

# --- com.mole.clean.plist ---
if [ "$TEST_MODE" = true ]; then
    # Test mode: run every 2 minutes
    sudo tee /Library/LaunchDaemons/com.mole.clean.plist > /dev/null << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mole.clean</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; LOGUSER=$(stat -f%Su /dev/console 2&gt;/dev/null || echo &quot;root&quot;); export HOME=$(eval echo ~$LOGUSER); TIMESTAMP=$(date &quot;+%Y-%m-%d %H:%M:%S&quot;); echo &quot;[$TIMESTAMP] Starting mo clean&quot; &gt;&gt; /var/log/mole/clean.log; OUTPUT=$(mo clean 2&gt;&amp;1); EXITCODE=$?; echo &quot;$OUTPUT&quot; &gt;&gt; /var/log/mole/clean.log; echo &quot;[$TIMESTAMP] Finished (exit code: $EXITCODE)&quot; &gt;&gt; /var/log/mole/clean.log; if [ $EXITCODE -eq 0 ]; then SAVED=$(echo &quot;$OUTPUT&quot; | grep &quot;Space freed:&quot; | grep -oE &quot;[0-9]+(\.[0-9]+)?\s*(GB|MB|KB|B)&quot; | head -1); if [ &quot;$LOGUSER&quot; != &quot;root&quot; ] &amp;&amp; [ -n &quot;$SAVED&quot; ]; then LOGUID=$(id -u &quot;$LOGUSER&quot;); launchctl asuser &quot;$LOGUID&quot; sudo -u &quot;$LOGUSER&quot; osascript -e &quot;display notification \&quot;Freed: $SAVED\&quot; with title \&quot;Mole Clean Complete\&quot;&quot; 2&gt;&gt; /var/log/mole/clean.log || true; fi; fi</string>
    </array>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>StandardOutPath</key>
    <string>/var/log/mole/clean.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/mole/clean.log</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>
</dict>
</plist>
PLIST
else
    # Production mode: run weekly on Sunday at 2 AM
    sudo tee /Library/LaunchDaemons/com.mole.clean.plist > /dev/null << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mole.clean</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; LOGUSER=$(stat -f%Su /dev/console 2&gt;/dev/null || echo &quot;root&quot;); export HOME=$(eval echo ~$LOGUSER); TIMESTAMP=$(date &quot;+%Y-%m-%d %H:%M:%S&quot;); echo &quot;[$TIMESTAMP] Starting mo clean&quot; &gt;&gt; /var/log/mole/clean.log; OUTPUT=$(mo clean 2&gt;&amp;1); EXITCODE=$?; echo &quot;$OUTPUT&quot; &gt;&gt; /var/log/mole/clean.log; echo &quot;[$TIMESTAMP] Finished (exit code: $EXITCODE)&quot; &gt;&gt; /var/log/mole/clean.log; if [ $EXITCODE -eq 0 ]; then SAVED=$(echo &quot;$OUTPUT&quot; | grep &quot;Space freed:&quot; | grep -oE &quot;[0-9]+(\.[0-9]+)?\s*(GB|MB|KB|B)&quot; | head -1); if [ &quot;$LOGUSER&quot; != &quot;root&quot; ] &amp;&amp; [ -n &quot;$SAVED&quot; ]; then LOGUID=$(id -u &quot;$LOGUSER&quot;); launchctl asuser &quot;$LOGUID&quot; sudo -u &quot;$LOGUSER&quot; osascript -e &quot;display notification \&quot;Freed: $SAVED\&quot; with title \&quot;Mole Clean Complete\&quot;&quot; 2&gt;&gt; /var/log/mole/clean.log || true; fi; fi</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>0</integer>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/var/log/mole/clean.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/mole/clean.log</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>
</dict>
</plist>
PLIST
fi

sudo chown root:wheel /Library/LaunchDaemons/com.mole.clean.plist
sudo chmod 644 /Library/LaunchDaemons/com.mole.clean.plist
echo "  com.mole.clean.plist installed"

# --- com.mole.optimize.plist ---
if [ "$TEST_MODE" = true ]; then
    # Test mode: run every 2 minutes
    sudo tee /Library/LaunchDaemons/com.mole.optimize.plist > /dev/null << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mole.optimize</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; LOGUSER=$(stat -f%Su /dev/console 2&gt;/dev/null || echo &quot;root&quot;); export HOME=$(eval echo ~$LOGUSER); TIMESTAMP=$(date &quot;+%Y-%m-%d %H:%M:%S&quot;); echo &quot;[$TIMESTAMP] Starting mo optimize&quot; &gt;&gt; /var/log/mole/optimize.log; OUTPUT=$(mo optimize 2&gt;&amp;1); EXITCODE=$?; echo &quot;$OUTPUT&quot; &gt;&gt; /var/log/mole/optimize.log; echo &quot;[$TIMESTAMP] Finished (exit code: $EXITCODE)&quot; &gt;&gt; /var/log/mole/optimize.log; if [ $EXITCODE -eq 0 ] &amp;&amp; [ &quot;$LOGUSER&quot; != &quot;root&quot; ]; then LOGUID=$(id -u &quot;$LOGUSER&quot;); launchctl asuser &quot;$LOGUID&quot; sudo -u &quot;$LOGUSER&quot; osascript -e &quot;display notification \&quot;Optimize completed\&quot; with title \&quot;Mole Optimize Complete\&quot;&quot; 2&gt;&gt; /var/log/mole/optimize.log || true; fi</string>
    </array>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>StandardOutPath</key>
    <string>/var/log/mole/optimize.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/mole/optimize.log</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>
</dict>
</plist>
PLIST
else
    # Production mode: run weekly on Wednesday at 3 AM
    sudo tee /Library/LaunchDaemons/com.mole.optimize.plist > /dev/null << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mole.optimize</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; LOGUSER=$(stat -f%Su /dev/console 2&gt;/dev/null || echo &quot;root&quot;); export HOME=$(eval echo ~$LOGUSER); TIMESTAMP=$(date &quot;+%Y-%m-%d %H:%M:%S&quot;); echo &quot;[$TIMESTAMP] Starting mo optimize&quot; &gt;&gt; /var/log/mole/optimize.log; OUTPUT=$(mo optimize 2&gt;&amp;1); EXITCODE=$?; echo &quot;$OUTPUT&quot; &gt;&gt; /var/log/mole/optimize.log; echo &quot;[$TIMESTAMP] Finished (exit code: $EXITCODE)&quot; &gt;&gt; /var/log/mole/optimize.log; if [ $EXITCODE -eq 0 ] &amp;&amp; [ &quot;$LOGUSER&quot; != &quot;root&quot; ]; then LOGUID=$(id -u &quot;$LOGUSER&quot;); launchctl asuser &quot;$LOGUID&quot; sudo -u &quot;$LOGUSER&quot; osascript -e &quot;display notification \&quot;Optimize completed\&quot; with title \&quot;Mole Optimize Complete\&quot;&quot; 2&gt;&gt; /var/log/mole/optimize.log || true; fi</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>3</integer>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/var/log/mole/optimize.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/mole/optimize.log</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>
</dict>
</plist>
PLIST
fi

sudo chown root:wheel /Library/LaunchDaemons/com.mole.optimize.plist
sudo chmod 644 /Library/LaunchDaemons/com.mole.optimize.plist
echo "  com.mole.optimize.plist installed"

# 7. Install LaunchAgent (run as user) for update

echo ""
echo "==> Installing LaunchAgent..."

mkdir -p ~/Library/LaunchAgents

if [ "$TEST_MODE" = true ]; then
    # Test mode: run every 2 minutes
    cat > ~/Library/LaunchAgents/com.mole.update.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mole.update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; TIMESTAMP=$(date &quot;+%Y-%m-%d %H:%M:%S&quot;); echo &quot;[$TIMESTAMP] Starting brew upgrade mole&quot; &gt;&gt; /tmp/mole-update.log; export HOMEBREW_NO_AUTO_UPDATE=1; OUTPUT=$(brew upgrade mole 2&gt;&amp;1); EXITCODE=$?; echo &quot;$OUTPUT&quot; &gt;&gt; /tmp/mole-update.log; echo &quot;[$TIMESTAMP] Finished (exit code: $EXITCODE)&quot; &gt;&gt; /tmp/mole-update.log; if [ $EXITCODE -eq 0 ]; then if echo &quot;$OUTPUT&quot; | grep -qi &quot;already&quot;; then MSG=&quot;Already up to date&quot;; else MSG=&quot;Updated successfully&quot;; fi; osascript -e &quot;display notification \&quot;$MSG\&quot; with title \&quot;Mole Update\&quot;&quot; 2&gt;/dev/null || true; else MSG=&quot;Update failed (check log)&quot;; osascript -e &quot;display notification \&quot;$MSG\&quot; with title \&quot;Mole Update\&quot;&quot; 2&gt;/dev/null || true; fi</string>
    </array>
    <key>StartInterval</key>
    <integer>120</integer>
    <key>StandardOutPath</key>
    <string>/tmp/mole-update.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/mole-update.log</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>
</dict>
</plist>
PLIST
else
    # Production mode: run weekly on Saturday at 12 PM
    cat > ~/Library/LaunchAgents/com.mole.update.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mole.update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; TIMESTAMP=$(date &quot;+%Y-%m-%d %H:%M:%S&quot;); echo &quot;[$TIMESTAMP] Starting brew upgrade mole&quot; &gt;&gt; /tmp/mole-update.log; export HOMEBREW_NO_AUTO_UPDATE=1; OUTPUT=$(brew upgrade mole 2&gt;&amp;1); EXITCODE=$?; echo &quot;$OUTPUT&quot; &gt;&gt; /tmp/mole-update.log; echo &quot;[$TIMESTAMP] Finished (exit code: $EXITCODE)&quot; &gt;&gt; /tmp/mole-update.log; if [ $EXITCODE -eq 0 ]; then if echo &quot;$OUTPUT&quot; | grep -qi &quot;already&quot;; then MSG=&quot;Already up to date&quot;; else MSG=&quot;Updated successfully&quot;; fi; osascript -e &quot;display notification \&quot;$MSG\&quot; with title \&quot;Mole Update\&quot;&quot; 2&gt;/dev/null || true; else MSG=&quot;Update failed (check log)&quot;; osascript -e &quot;display notification \&quot;$MSG\&quot; with title \&quot;Mole Update\&quot;&quot; 2&gt;/dev/null || true; fi</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>6</integer>
        <key>Hour</key>
        <integer>12</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/mole-update.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/mole-update.log</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>
</dict>
</plist>
PLIST
fi

echo "  com.mole.update.plist installed"

# 8. Unload old + load new (idempotent)

echo ""
echo "==> Loading launchd jobs..."

# Unload existing (ignore errors if not loaded)
sudo launchctl bootout system/com.mole.clean 2>/dev/null || true
sudo launchctl bootout system/com.mole.optimize 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.mole.update" 2>/dev/null || true

# Load new
sudo launchctl bootstrap system /Library/LaunchDaemons/com.mole.clean.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.mole.optimize.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.mole.update.plist

echo "  All jobs loaded"

# 9. Summary + verification

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ "$TEST_MODE" = true ]; then
    echo "  Mole Installer — Complete (TEST MODE)"
else
    echo "  Mole Installer — Complete"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""
if [ "$TEST_MODE" = true ]; then
    echo "  ⚠️  TEST MODE Schedule (every 2 minutes):"
    echo "    mo clean      Every 2 min  (root, LaunchDaemon)"
    echo "    mo optimize   Every 2 min  (root, LaunchDaemon)"
    echo "    brew upgrade  Every 2 min  (user, LaunchAgent)"
    echo ""
    echo "  To stop all jobs:"
    echo "    bash install.sh --stop"
    echo ""
    echo "  To switch to production schedule:"
    echo "    bash install.sh"
else
    echo "  Schedule:"
    echo "    mo clean      Sunday    2:00 AM   (root, LaunchDaemon)"
    echo "    mo optimize   Wednesday 3:00 AM   (root, LaunchDaemon)"
    echo "    brew upgrade  Saturday  12:00 PM  (user, LaunchAgent)"
fi
echo ""
echo "  Notifications:"
echo "    ✓ Success notifications enabled for all jobs"
echo "    ✓ Clean: shows amount freed"
echo "    ✓ Optimize: simple completion message"
echo "    ✓ Update: shows if updated or already current"
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
echo "    sudo launchctl bootout system/com.mole.clean 2>/dev/null"
echo "    sudo launchctl bootout system/com.mole.optimize 2>/dev/null"
echo "    launchctl bootout gui/\$(id -u)/com.mole.update 2>/dev/null"
echo "    sudo rm -f /Library/LaunchDaemons/com.mole.{clean,optimize}.plist"
echo "    rm -f ~/Library/LaunchAgents/com.mole.update.plist"
echo "    sudo rm -rf /var/log/mole"
echo ""
