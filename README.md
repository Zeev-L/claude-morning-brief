# Morning Brief ☀️

A daily "where did I leave off?" briefing for people who run **many parallel Claude Code
sessions**. Every weekday morning it reads your recent session transcripts, summarizes what
you did, where you stopped, and the likely next step — then emails you a clean newsletter
(and drops the same HTML on your Desktop).

Built to solve a specific pain: after a long day — or an Israeli Thu-evening→Sun-morning
weekend — it takes ages to remember what each of your half-finished sessions was even about.

## What you get

A modern **HTML newsletter**, one card per session, **ordered oldest → newest**. Each card:

- **Title = the session's real Claude name** (the sidebar title); falls back to a short
  inferred topic when a session was never named.
- **מה נעשה** (what got done) · **נקודת עצירה** (where it stopped) · **הצעד הבא** (next step).
- A **▶ פתח את הסשן באפליקציה** button that reopens that exact session in the **Claude
  desktop app** via its native `claude://resume?session=<id>` deep link — i.e. it lands you
  back on the platform you actually work in. (Gmail strips custom-scheme links, so click
  from the Desktop `.html`; the link is also shown as text.)

If you didn't work since the last brief, you still get one — it notes the **last working
date** and re-shows the previous cards, so you always have your bearings.

## How it works

```
launchd (Sun–Thu 07:33)
   └─ run.sh
        ├─ gather.js        scan ~/.claude/projects/**/*.jsonl since the last brief  (ground truth,
        │                   incl. each session's Claude title from its custom-title records)
        ├─ claude -p        summarize each session → strict JSON (did / stopped / next)
        ├─ render.js        join + render a modern HTML newsletter (+ plain-text fallback)
        ├─ write .html      → ~/Desktop/Morning Briefs/brief-YYYY-MM-DD.html   ← guaranteed
        ├─ notify + open
        └─ POST to webhook  → HTML email via Apps Script  (best-effort)
```

- **Scheduler is `launchd`, not Claude's `CronCreate`** — CronCreate only fires while a Claude
  session is open and idle. launchd runs even with nothing open (and on wake if the Mac slept).
- **State**: `state/last-brief.txt` is the "since" marker; `state/last-material.json` +
  `state/last-summary.json` are kept so idle days can re-render your last real brief.
- **Resume links**: the HTML uses the Claude desktop app's native
  `claude://resume?session=<id>` deep link (discovered in the app — it routes `resume` to the
  CLI session by `session`). One click from the Desktop `.html` reopens that session in the app.
  Gmail strips custom-scheme links, so they're clickable from the Desktop file, not inside Gmail.

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
| `gather.js` | deterministic transcript scanner — pulls activity + session titles (no model, no network) |
| `render.js` | renders the HTML newsletter + plain-text fallback from (material + summary) |
| `run.sh` | orchestrator: gather → summarize (JSON) → render → write → notify → email |
| `com.zeev.morning-brief.plist` | launchd schedule (Sun–Thu 07:33) |
| `apps-script-mailer.gs` | Gmail web-app mailer, sends `htmlBody` (deploy separately) |
| `install.sh` | one-shot setup / restore (dirs, launchd job) |
