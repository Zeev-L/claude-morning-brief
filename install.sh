#!/bin/zsh
# Morning Brief — installer / restore script
# Run after cloning this repo to ~/.claude/morning-brief on a Mac.
set -eu

BASE="$HOME/.claude/morning-brief"
PLIST_SRC="$BASE/com.zeev.morning-brief.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.zeev.morning-brief.plist"

echo "→ creating local dirs (state, logs, Desktop output)…"
mkdir -p "$BASE/state" "$BASE/logs" "$HOME/Desktop/Morning Briefs"

echo "→ chmod scripts…"
chmod +x "$BASE/run.sh" "$BASE/gather.js" "$BASE/install.sh" 2>/dev/null || true

echo "→ installing launchd job (Sun–Thu 07:33)…"
# NOTE: the plist has hardcoded /Users paths; if your username differs, edit it first.
cp "$PLIST_SRC" "$PLIST_DST"
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"
launchctl list | grep morning-brief && echo "  ✓ job loaded" || echo "  ! job not found"

echo ""
echo "Done. To enable email delivery:"
echo "  1. Deploy apps-script-mailer.gs as a Web App (see file header for steps)."
echo "  2. echo 'YOUR_EXEC_URL' > $BASE/state/email-webhook.txt"
echo ""
echo "Test now:  $BASE/run.sh"
