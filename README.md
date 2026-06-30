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
- A **▶ פתח את הסשן** button that reopens that exact (titled) session in the **Claude
  desktop app**, right where you left off. From the **Desktop `.html`** it's one click
  (direct `claudejump://`); in **email** it goes via a tiny https redirect because Gmail
  strips custom-scheme links (link → page → one click — unavoidable for email).

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
- **"Open session" jump** (the hard part): there is **no** native deep link that opens an
  existing *local* Claude Code session (`claude://resume` IMPORTS it → duplicate empty
  sessions; `claude://code/<id>` needs a cloud id local sessions lack + is feature-gated).
  So the jump is **UI automation**:
  - `ClaudeJump.app` — a thin `claudejump://` URL-scheme handler (built by `install.sh`)
    that runs `jump.applescript`.
  - `jump.applescript` — sets `AXManualAccessibility` to force Electron to expose its a11y
    tree, then finds the sidebar button whose name contains the session title and presses it.
    Fast (~1s), works across all running Claude instances. Needs a one-time **Accessibility**
    grant to `ClaudeJump.app`.
  - **Email** links can't use `claudejump://` (Gmail strips it), so they point at a generic
    static redirect page (`https://zeev-l.github.io/claude-jump/?t=<title>`, repo:
    [Zeev-L/claude-jump](https://github.com/Zeev-L/claude-jump)) that bounces to the handler.

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

`install.sh` creates the local dirs, builds + registers `ClaudeJump.app`, generates +
loads the launchd job (with this machine's paths), and prints the remaining one-time
manual steps:

1. **Email** — deploy `apps-script-mailer.gs` as a Web App (Execute as: Me, Who has access:
   Anyone), then `echo '<exec-url>' > state/email-webhook.txt` and `echo '<you@x.com>' > state/email-to.txt`.
2. **Jump links** — grant Accessibility to `~/Applications/ClaudeJump.app`.
3. `./run.sh` to verify.

`state/` and `logs/` are gitignored (they hold the webhook secret, recipient, and brief content).

## Files

| file | role |
|------|------|
| `gather.js` | deterministic transcript scanner — activity + session titles, de-noises the tool's own `claude -p` calls, merges split conversations (no model, no network) |
| `render.js` | renders the HTML newsletter (local + email variants) + plain-text fallback |
| `run.sh` | orchestrator: gather → summarize (JSON) → render → write → notify → email |
| `apps-script-mailer.gs` | Gmail web-app mailer (sends `htmlBody`; `?jump=`/`?open=` bounces) — deploy separately |
| `claude-jump-shim.applescript` | source for `ClaudeJump.app` (thin `claudejump://` handler) |
| `jump.applescript` | the AX automation that opens a session by title (editable without re-signing the app) |
| `install.sh` | one-shot setup / restore (dirs, ClaudeJump.app, launchd job) |

The email redirect page lives in a separate public repo: [Zeev-L/claude-jump](https://github.com/Zeev-L/claude-jump).
