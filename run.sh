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
BRIEF_FILE="$OUT_DIR/brief-$TODAY.md"

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

# --- 2/3. build the brief -----------------------------------------------------
if [ "$HAS_ACTIVITY" = "true" ]; then
  INSTRUCTION='אתה כותב "בריף בוקר" קצר וענייני לזאב, שמזכיר לו מה הוא עשה ואיפה עצר בסשנים של Claude Code.
קיבלת בסוף ההודעה JSON עם השדה sessions — מערך סשנים שכבר ממוין מהישן לחדש. כל סשן כולל: userMsgs (מה זאב ביקש), lastAssistant (איך זה הסתיים), ו-resumeCmd (פקודה לחזרה לאותו סשן).

כתוב בעברית, Markdown נקי. הפק סעיף אחד לכל סשן, **בדיוק באותו סדר שהם מופיעים במערך** (מהישן לחדש). תן לכל סעיף כותרת לפי הנושא האמיתי של הסשן (לא שם התיקייה). מבנה כל סעיף:
### <כותרת הנושא של הסשן>
- **מה נעשה:** 1–3 נקודות תמציתיות.
- **נקודת עצירה:** איפה זה נעצר, לפי ההודעות האחרונות.
- **הצעד הבא:** הסק מההקשר מה ההמשך הטבעי. אם באמת לא ברור — כתוב "לא ברור, החלט כשתחזור".
- **▶ להמשך:** `<העתק לכאן בדיוק את הערך של resumeCmd של אותו סשן, ללא שינוי>`

כללים: היה תמציתי מאוד. בלי הקדמות, בלי "הנה הבריף". התחל ישר בתוכן. אל תמציא — הסתמך אך ורק על ה-JSON. את resumeCmd העתק מילה במילה (אל תשנה path או id). שמור על סדר הסשנים. אם סשן ממש שולי (הודעה אחת חסרת משמעות) — דלג עליו.

להלן ה-JSON:'

  PROMPT="$INSTRUCTION
$(cat "$MATERIAL")"

  log "calling claude -p (summarize)..."
  BODY="$("$CLAUDE_BIN" -p "$PROMPT" --model "$MODEL" 2>>"$RUN_LOG")"
  if [ -z "$BODY" ]; then
    log "ERROR: empty summary from claude; falling back to idle brief"
    HAS_ACTIVITY="false"
  fi
fi

if [ "$HAS_ACTIVITY" = "true" ]; then
  # real brief
  {
    echo "# בריף בוקר — $TODAY_HUMAN"
    echo ""
    echo "_סיכום הפעילות בסשנים שלך מאז הבריף הקודם._"
    echo ""
    echo "$BODY"
  } > "$BRIEF_FILE"
  # save as the last real brief for future idle days
  cp "$BRIEF_FILE" "$LAST_REAL"
  echo "$TODAY_HUMAN" > "$LAST_REAL_DATE"
  log "wrote real brief -> $BRIEF_FILE"
else
  # idle brief: no new activity. Note last working date + re-show last stop-point.
  LAST_WORK_DATE="לא ידוע"
  if [ -n "$LAST_ACTIVITY_ISO" ]; then
    LAST_WORK_DATE="$(echo "$LAST_ACTIVITY_ISO" | cut -dT -f1)"
  fi
  {
    echo "# בריף בוקר — $TODAY_HUMAN"
    echo ""
    echo "**אין פעילות חדשה מאז הבריף הקודם.**"
    echo "תאריך העבודה האחרון שנרשם: **$LAST_WORK_DATE**."
    echo ""
    if [ -f "$LAST_REAL" ]; then
      echo "להלן נקודת העצירה והצעד הבא מהבריף האחרון:"
      echo ""
      echo "---"
      echo ""
      # strip the old H1 title line from the saved brief, keep the body
      tail -n +2 "$LAST_REAL"
    else
      echo "_אין בריף קודם שמור עדיין._"
    fi
  } > "$BRIEF_FILE"
  log "wrote idle brief -> $BRIEF_FILE"
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
      const body=fs.readFileSync(process.argv[1],"utf8");
      const payload={subject:"Morning Brief — "+process.argv[2], body};
      if(process.argv[3]) payload.to=process.argv[3];
      process.stdout.write(JSON.stringify(payload));
    ' "$BRIEF_FILE" "$TODAY" "$EMAIL_TO")" 2>>"$RUN_LOG")" || true
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

rm -f "$MATERIAL"
log "=== run done ==="
