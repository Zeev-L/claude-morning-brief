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

echo "→ building + registering the claudejump:// 'open session' handler…"
# A thin app that the brief's per-session links invoke; it runs jump.applescript,
# which forces Electron's a11y tree and clicks the matching session in Recents
# (works across all running Claude instances). Lives in ~/Applications so it's
# easy to grant Accessibility to.
APP="$HOME/Applications/ClaudeJump.app"; PL="$APP/Contents/Info.plist"
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
mkdir -p "$HOME/Applications"
"$LS" -u "$APP" 2>/dev/null || true; rm -rf "$APP"
if osacompile -l AppleScript -o "$APP" "$BASE/claude-jump-shim.applescript" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.zeev.claudejump" "$PL" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.zeev.claudejump" "$PL"
  for c in "Add :CFBundleURLTypes array" "Add :CFBundleURLTypes:0 dict" \
    "Add :CFBundleURLTypes:0:CFBundleURLName string com.zeev.claudejump" \
    "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
    "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string claudejump"; do
    /usr/libexec/PlistBuddy -c "$c" "$PL" 2>/dev/null || true
  done
  codesign --force -s - "$APP" 2>/dev/null
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
  "$LS" -f "$APP"
  echo "  ✓ ClaudeJump.app built. GRANT IT ACCESSIBILITY ONCE:"
  echo "    System Settings → Privacy & Security → Accessibility → + → ~/Applications/ClaudeJump.app"
else
  echo "  ! could not build ClaudeJump.app (per-session jump links will be inert)"
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
