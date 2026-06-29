#!/bin/zsh
# =============================================================================
# Morning Brief — run.sh
# -----------------------------------------------------------------------------
# Runs each weekday morning via launchd. Pipeline:
#   1. gather.js  -> collect what you touched since the last brief (ground truth)
#   2. claude -p  -> summarize into a short brief (per project: did / stopped / next)
#   3. write .md  -> ~/Desktop/Morning Briefs/  (GUARANTEED channel)
#   4. notify + open  (best-effort)
#   5. Gmail draft to self  (best-effort; never blocks the file)
#
# If nothing changed since the last brief, it STILL produces a brief that notes
# the last working date and re-shows the last real stop-point / next-step.
# =============================================================================

set -u

# --- config -------------------------------------------------------------------
# Recipient is decided server-side by the Apps Script mailer (Session.getActiveUser),
# so no email address is stored here.
MODEL="claude-sonnet-4-6"                  # summary model (quality/cost sweet spot)
HOME_DIR="$HOME"
BASE="$HOME_DIR/.claude/morning-brief"
STATE="$BASE/state"
LOGS="$BASE/logs"
OUT_DIR="$HOME_DIR/Desktop/Morning Briefs"
CLAUDE_BIN="$HOME_DIR/.local/bin/claude"
NODE_BIN="/opt/homebrew/bin/node"

# launchd gives a minimal PATH; set one that finds node/claude/system tools
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME_DIR/.local/bin"

MARKER="$STATE/last-brief.txt"
LAST_REAL="$STATE/last-real-brief.md"
LAST_REAL_DATE="$STATE/last-real-brief-date.txt"
RUN_LOG="$LOGS/run.log"

mkdir -p "$STATE" "$LOGS" "$OUT_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$RUN_LOG"; }

TODAY="$(date '+%Y-%m-%d')"
TODAY_HUMAN="$(date '+%A, %d %b %Y')"
BRIEF_FILE="$OUT_DIR/brief-$TODAY.html"
TEXT_FILE="$(mktemp /tmp/mb-text.XXXXXX.txt)"
SUMMARY="$(mktemp /tmp/mb-summary.XXXXXX.json)"
RENDER_JSON="$(mktemp /tmp/mb-render.XXXXXX.json)"
LAST_MATERIAL="$STATE/last-material.json"
LAST_SUMMARY="$STATE/last-summary.json"
# webhook /exec URL — also used for the "open Claude app" bounce link in the brief
MB_EXEC=""; [ -f "$STATE/email-webhook.txt" ] && MB_EXEC="$(tr -d '[:space:]' < "$STATE/email-webhook.txt")"

log "=== run start ($TODAY_HUMAN) ==="

# --- 1. gather ----------------------------------------------------------------
MATERIAL="$(mktemp /tmp/mb-material.XXXXXX.json)"
if ! "$NODE_BIN" "$BASE/gather.js" > "$MATERIAL" 2>>"$RUN_LOG"; then
  log "ERROR: gather.js failed"
  exit 1
fi

HAS_ACTIVITY="$("$NODE_BIN" -e 'console.log(require(process.argv[1]).hasActivity)' "$MATERIAL")"
LAST_ACTIVITY_ISO="$("$NODE_BIN" -e 'console.log(require(process.argv[1]).lastActivityISO||"")' "$MATERIAL")"
log "hasActivity=$HAS_ACTIVITY lastActivity=$LAST_ACTIVITY_ISO"

# --- 2. summarize (structured JSON, one object per session) -------------------
if [ "$HAS_ACTIVITY" = "true" ]; then
  INSTRUCTION='אתה מסכם לזאב את הסשנים שלו ב-Claude Code לצורך "בריף בוקר".
בסוף ההודעה יש JSON עם השדה sessions — מערך סשנים ממוין מהישן לחדש. לכל סשן יש sessionId, title (שם הסשן בקלוד), userMsgs (מה זאב ביקש) ו-lastAssistant (איך הסתיים).

החזר אך ורק JSON תקין — בלי טקסט נוסף ובלי גדרות ```. מערך אובייקטים, אחד לכל סשן, באותו סדר בדיוק. כל אובייקט:
{"sessionId":"<מתוך הקלט>","title":"<כותרת נושא קצרה (2-5 מילים) שתשמש רק אם לסשן אין שם>","did":["1-3 נקודות קצרות בעברית של מה נעשה"],"stopped":"משפט אחד: נקודת העצירה","next":"משפט אחד: הצעד הבא (הסק מההקשר; אם לא ברור כתוב: לא ברור, החלט כשתחזור)"}

כללים: עברית, תמציתי מאוד, ענייני. הסתמך אך ורק על userMsgs ו-lastAssistant של אותו סשן. אל תמציא. החזר רק את ה-JSON.

להלן ה-JSON:'
  PROMPT="$INSTRUCTION
$(cat "$MATERIAL")"
  log "calling claude -p (summarize -> JSON)..."
  "$CLAUDE_BIN" -p "$PROMPT" --model "$MODEL" > "$SUMMARY" 2>>"$RUN_LOG"
  if [ ! -s "$SUMMARY" ]; then
    log "ERROR: empty summary from claude; falling back to idle brief"
    HAS_ACTIVITY="false"
  fi
fi

# --- 3. render the HTML newsletter (+ plain-text fallback) --------------------
if [ "$HAS_ACTIVITY" = "true" ]; then
  if "$NODE_BIN" "$BASE/render.js" "$MATERIAL" "$SUMMARY" "$TODAY_HUMAN" "" "$MB_EXEC" > "$RENDER_JSON" 2>>"$RUN_LOG" && [ -s "$RENDER_JSON" ]; then
    "$NODE_BIN" -e 'const o=require(process.argv[1]);const fs=require("fs");fs.writeFileSync(process.argv[2],o.html);fs.writeFileSync(process.argv[3],o.text)' "$RENDER_JSON" "$BRIEF_FILE" "$TEXT_FILE"
    # remember this brief so idle days can re-show it
    cp "$MATERIAL" "$LAST_MATERIAL"; cp "$SUMMARY" "$LAST_SUMMARY"; echo "$TODAY_HUMAN" > "$LAST_REAL_DATE"
    log "wrote HTML brief -> $BRIEF_FILE"
  else
    log "ERROR: render failed; falling back to idle"
    HAS_ACTIVITY="false"
  fi
fi

if [ "$HAS_ACTIVITY" != "true" ]; then
  # idle: no new activity — re-show the last real brief with a banner.
  LAST_WORK_DATE="לא ידוע"; [ -n "$LAST_ACTIVITY_ISO" ] && LAST_WORK_DATE="$(echo "$LAST_ACTIVITY_ISO" | cut -dT -f1)"
  BANNER="אין פעילות חדשה מאז הבריף הקודם. תאריך העבודה האחרון שנרשם: $LAST_WORK_DATE."
  if [ -f "$LAST_MATERIAL" ] && [ -f "$LAST_SUMMARY" ]; then
    "$NODE_BIN" "$BASE/render.js" "$LAST_MATERIAL" "$LAST_SUMMARY" "$TODAY_HUMAN" "$BANNER" "$MB_EXEC" > "$RENDER_JSON" 2>>"$RUN_LOG"
  else
    echo '{"sessions":[]}' > /tmp/mb-empty.json
    "$NODE_BIN" "$BASE/render.js" /tmp/mb-empty.json /tmp/mb-empty.json "$TODAY_HUMAN" "$BANNER" "$MB_EXEC" > "$RENDER_JSON" 2>>"$RUN_LOG"
  fi
  "$NODE_BIN" -e 'const o=require(process.argv[1]);const fs=require("fs");fs.writeFileSync(process.argv[2],o.html);fs.writeFileSync(process.argv[3],o.text)' "$RENDER_JSON" "$BRIEF_FILE" "$TEXT_FILE"
  log "wrote idle HTML brief -> $BRIEF_FILE"
fi

# --- 4. notify + open ---------------------------------------------------------
osascript -e 'display notification "הבריף מוכן על הדסקטופ" with title "Morning Brief" sound name "Glass"' >/dev/null 2>&1 || true
open "$BRIEF_FILE" >/dev/null 2>&1 || true

# --- 5. Email delivery via Apps Script webhook (best-effort) ------------------
# The claude.ai Gmail connector CANNOT be used headless (it hard-requires an
# interactive permission grant). Instead we POST the brief to a tiny Apps Script
# web app that sends/drafts the mail server-side from your own Google account.
# Configure it by writing the deployment /exec URL to:  state/email-webhook.txt
# Until that file exists, email is skipped and the .md file is the channel.
WEBHOOK_FILE="$STATE/email-webhook.txt"
if [ -f "$WEBHOOK_FILE" ] && [ -s "$WEBHOOK_FILE" ]; then
  WEBHOOK_URL="$(tr -d '[:space:]' < "$WEBHOOK_FILE")"
  log "posting brief to email webhook..."
  # optional explicit recipient (gitignored); falls back to script owner if absent
  EMAIL_TO=""
  [ -f "$STATE/email-to.txt" ] && EMAIL_TO="$(tr -d '[:space:]' < "$STATE/email-to.txt")"
  # NOTE: do NOT follow redirects (-L). Apps Script runs doPost on the initial
  # /exec POST and returns 302 to a sandbox URL; following it converts to GET and
  # yields a misleading 405. The email is already sent by the time we get the 302.
  HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' \
    -X POST "$WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    --data "$("$NODE_BIN" -e '
      const fs=require("fs");
      const html=fs.readFileSync(process.argv[1],"utf8");
      const text=fs.readFileSync(process.argv[2],"utf8");
      const payload={subject:"Morning Brief — "+process.argv[3], htmlBody:html, body:text};
      if(process.argv[4]) payload.to=process.argv[4];
      process.stdout.write(JSON.stringify(payload));
    ' "$BRIEF_FILE" "$TEXT_FILE" "$TODAY" "$EMAIL_TO")" 2>>"$RUN_LOG")" || true
  case "$HTTP_CODE" in
    302|200) log "email sent via webhook (http $HTTP_CODE)" ;;
    *)       log "WARN: webhook returned http ${HTTP_CODE:-<none>} (email may not have sent; .md is on Desktop)" ;;
  esac
else
  log "no email webhook configured (state/email-webhook.txt) — skipping email"
fi

# --- 6. advance the marker ----------------------------------------------------
# Always move forward so we don't re-summarize the same window next run.
"$NODE_BIN" -e 'console.log(require(process.argv[1]).now)' "$MATERIAL" > "$MARKER"
log "marker advanced -> $(cat "$MARKER")"

rm -f "$MATERIAL" "$TEXT_FILE" "$SUMMARY" "$RENDER_JSON"
log "=== run done ==="
