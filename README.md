# Morning Brief ☀️

A daily "where did I leave off?" briefing for people who run **many parallel Claude Code
sessions**. Every weekday morning it reads your recent session transcripts, summarizes what
you did, where you stopped, and the likely next step — then drops a short brief on your
Desktop (and optionally emails it to you).

Built to solve a specific pain: after a long day — or an Israeli Thu-evening→Sun-morning
weekend — it takes ages to remember what each of your half-finished sessions was even about.

## What you get

A Markdown brief, one section per session, **ordered oldest → newest**:

```
### <topic of the session>
- מה נעשה:      what got done
- נקודת עצירה:   where it stopped
- הצעד הבא:      the natural next step
- ▶ להמשך:       cd "<project>" && claude --resume <session-id>
```

That last line is a one-paste command to **resume that exact session** where you left off.

If you didn't work since the last brief, you still get one — it notes the **last working
date** and re-shows the previous stop-point / next-step, so you always have your bearings.

## How it works

```
launchd (Sun–Thu 07:33)
   └─ run.sh
        ├─ gather.js        scan ~/.claude/projects/**/*.jsonl since the last brief  (ground truth)
        ├─ claude -p        summarize into the brief (Sonnet)
        ├─ write .md        → ~/Desktop/Morning Briefs/brief-YYYY-MM-DD.md   ← guaranteed
        ├─ notify + open
        └─ POST to webhook  → email via Apps Script  (best-effort)
```

- **Scheduler is `launchd`, not Claude's `CronCreate`** — CronCreate only fires while a Claude
  session is open and idle. launchd runs even with nothing open (and on wake if the Mac slept).
- **State**: `state/last-brief.txt` is the "since" marker; `state/last-real-brief.md` is kept so
  idle days can re-show your last real stop-point.

## Email delivery — why Apps Script, not the Gmail connector

The claude.ai **Gmail connector cannot be used headless** — it hard-requires an interactive
permission grant, so `--dangerously-skip-permissions`, `--permission-mode bypassPermissions`,
`--allowedTools`, and `settings.json` allow-lists all still get denied in a scheduled run.

So email goes through a tiny **Apps Script web app** (`apps-script-mailer.gs`) that sends the
mail server-side from your own Google account. The deployment `/exec` URL **is** the secret
(long, unguessable — same pattern as a Slack webhook). `run.sh` POSTs the brief to it.

To enable: deploy the script (steps in its header), then:
```sh
echo 'YOUR_EXEC_URL' > state/email-webhook.txt
```
Until that file exists, email is simply skipped — the Desktop file is the source of truth.

## Install / restore

```sh
git clone https://github.com/Zeev-L/morning-brief ~/.claude/morning-brief
cd ~/.claude/morning-brief && ./install.sh
```

`install.sh` creates the local dirs, installs + loads the launchd job, and prints the email
setup steps. `state/` and `logs/` are gitignored (they hold the webhook secret and your brief
content).

## Files

| file | role |
|------|------|
| `gather.js` | deterministic transcript scanner (no model, no network) |
| `run.sh` | orchestrator: gather → summarize → write → notify → email |
| `com.zeev.morning-brief.plist` | launchd schedule (Sun–Thu 07:33) |
| `apps-script-mailer.gs` | Gmail web-app mailer (deploy separately) |
| `install.sh` | one-shot setup / restore |
