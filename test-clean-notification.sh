#!/usr/bin/env bash
# Test script to debug notification logic

export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

echo "=== Testing notification logic ==="
echo ""

# Detect logged-in user
LOGUSER=$(stat -f%Su /dev/console 2>/dev/null || echo "root")
echo "1. Logged-in user: $LOGUSER"

# Export HOME
export HOME=$(eval echo ~$LOGUSER)
echo "2. HOME set to: $HOME"

# Timestamp
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
echo "3. Timestamp: $TIMESTAMP"

# Run mo clean and capture output
echo "4. Running mo clean..."
OUTPUT=$(mo clean 2>&1)
EXITCODE=$?

echo "5. Exit code: $EXITCODE"
echo ""
echo "6. Full output (first 500 chars):"
echo "$OUTPUT" | head -c 500
echo ""
echo "..."
echo ""

# Extract the saved amount
echo "7. Extracting saved amount..."
SAVED=$(echo "$OUTPUT" | grep -oE "[0-9]+(\.[0-9]+)?\s*(GB|MB|KB|B)" | head -1)
echo "   SAVED variable: '$SAVED'"
echo ""

# Test notification
if [ $EXITCODE -eq 0 ]; then
    echo "8. Exit code is 0, checking notification conditions..."
    if [ "$LOGUSER" != "root" ] && [ -n "$SAVED" ]; then
        echo "   Conditions met! Sending notification..."
        sudo -u "$LOGUSER" osascript -e "display notification \"Freed: $SAVED\" with title \"Mole Clean Complete\"" 2>&1
        echo "   Notification command executed"
    else
        echo "   Conditions NOT met:"
        echo "     - LOGUSER != root: $([ "$LOGUSER" != "root" ] && echo "YES" || echo "NO")"
        echo "     - SAVED not empty: $([ -n "$SAVED" ] && echo "YES" || echo "NO")"
    fi
else
    echo "8. Exit code is $EXITCODE (non-zero), skipping notification"
fi

echo ""
echo "=== Test complete ==="
