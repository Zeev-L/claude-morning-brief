#!/bin/zsh
# Morning Brief — installer / restore script
# Run after cloning this repo to ~/.claude/morning-brief on a Mac.
set -eu

BASE="$HOME/.claude/morning-brief"
PLIST_DST="$HOME/Library/LaunchAgents/com.zeev.morning-brief.plist"

echo "→ creating local dirs (state, logs, Desktop output)…"
mkdir -p "$BASE/state" "$BASE/logs" "$HOME/Desktop/Morning Briefs"

echo "→ chmod scripts…"
chmod +x "$BASE/run.sh" "$BASE/gather.js" "$BASE/render.js" "$BASE/install.sh" 2>/dev/null || true

echo "→ preflight: the summarizer needs the 'claude' CLI, installed AND logged in…"
# These two are the most common reasons a morning brief comes out empty:
#   1) the standalone CLI isn't installed (the desktop app alone is NOT enough), or
#   2) it's installed but not signed in, so `claude -p` returns "Not logged in".
CLAUDE_PREFLIGHT_OK=1
if ! command -v claude >/dev/null 2>&1; then
  CLAUDE_PREFLIGHT_OK=0
  echo "  ! 'claude' CLI not found. Install it (needs Node):"
  echo "      npm install -g @anthropic-ai/claude-code"
elif ! claude auth status 2>/dev/null | grep -q '"loggedIn": true'; then
  CLAUDE_PREFLIGHT_OK=0
  echo "  ! 'claude' CLI is installed but NOT logged in. Sign in once (uses your subscription):"
  echo "      claude auth login"
else
  echo "  ✓ claude CLI present and logged in"
fi

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
# Generate the plist with THIS machine's paths (portable across usernames).
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_DST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.zeev.morning-brief</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$BASE/run.sh</string></array>
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>33</integer></dict>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>33</integer></dict>
    <dict><key>Weekday</key><integer>2</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>33</integer></dict>
    <dict><key>Weekday</key><integer>3</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>33</integer></dict>
    <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>7</integer><key>Minute</key><integer>33</integer></dict>
  </array>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$BASE/logs/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$BASE/logs/launchd.err.log</string>
</dict>
</plist>
PLIST
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"
launchctl list | grep morning-brief && echo "  ✓ job loaded" || echo "  ! job not found"

echo ""
echo "=================== MANUAL STEPS (one-time) ==================="
if [ "$CLAUDE_PREFLIGHT_OK" -ne 1 ]; then
  echo "0. CLAUDE CLI (required — the brief is empty without it): see the preflight"
  echo "   warning above (install it and/or 'claude auth login')."
fi
echo "1. EMAIL: deploy apps-script-mailer.gs as a Web App"
echo "   (script.google.com → New project → paste → Deploy → Web app,"
echo "    Execute as: Me, Who has access: Anyone → authorize → copy /exec URL):"
echo "      echo 'YOUR_EXEC_URL'      > $BASE/state/email-webhook.txt"
echo "      echo 'you@example.com'    > $BASE/state/email-to.txt"
echo "2. JUMP LINKS: grant Accessibility to the handler (so it can click sessions):"
echo "      System Settings → Privacy & Security → Accessibility → +"
echo "      → ~/Applications/ClaudeJump.app  (toggle ON)"
echo "3. Run once to verify:   $BASE/run.sh"
echo "==============================================================="
