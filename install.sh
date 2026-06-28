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
chmod +x "$BASE/run.sh" "$BASE/gather.js" "$BASE/render.js" "$BASE/install.sh" 2>/dev/null || true

echo "→ building + registering the claudemb:// resume handler…"
# A tiny AppleScript app that handles claudemb://resume?id=..&cwd=.. links from
# the HTML brief and opens that Claude Code session in Terminal.
APP="$BASE/ClaudeResume.app"; PL="$APP/Contents/Info.plist"
rm -rf "$APP"
if osacompile -l AppleScript -o "$APP" "$BASE/claude-resume-handler.applescript" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.zeev.clauderesume" "$PL" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.zeev.clauderesume" "$PL"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PL" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PL" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string com.zeev.clauderesume" "$PL" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PL" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string claudemb" "$PL" 2>/dev/null || true
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" \
    && echo "  ✓ claudemb:// handler registered (first click will ask to allow Terminal automation)"
else
  echo "  ! could not build the resume handler (resume links will still show as copyable commands)"
fi

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
