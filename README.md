# Claude Morning Brief ☀️

A daily "where did I leave off?" briefing for people who run **many parallel Claude Code
sessions**. Every weekday morning it reads your recent session transcripts, summarizes what
you did, where you stopped, and the likely next step — then emails you a clean newsletter
(and drops the same HTML on your Desktop).

Built to solve a specific pain: after a long day — or an Israeli Thu-evening→Sun-morning
weekend — it takes ages to remember what each of your half-finished sessions was even about.

## What you get

A modern **HTML newsletter**, one card per session, **ordered oldest → newest**. Each card:

- **Title = the session's real Claude name** (the sidebar title — manual *or* auto-generated).
  Only **named** sessions appear; untitled/archived ones are filtered out.
- A one-line **תיאור** (what the session is about) · **מה נעשה** (what got done) ·
  **הפעולה האחרונה** (last action / where it stopped) · **הצעד הבא** (next step).
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
        ├─ write .html      → ~/Desktop/Claude Morning Brief/brief-YYYY-MM-DD.html  ← guaranteed
        │                     (+ copy to …/latest.html — a STABLE path to bookmark;
        │                      always the newest brief, header shows date + update time)
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

## Setup (works on any Mac, for anyone)

```sh
git clone https://github.com/Zeev-L/claude-morning-brief ~/.claude/morning-brief
cd ~/.claude/morning-brief && ./install.sh
```

> The clone target stays `~/.claude/morning-brief` (the scripts, launchd job and
> `ClaudeJump.app` reference that path) even though the repo is `claude-morning-brief`.

`install.sh` creates the local dirs, builds + registers `ClaudeJump.app`, and generates +
loads the launchd job **with this machine's own paths** (no hardcoded username; `run.sh`
auto-detects `node`/`claude`). It also runs a **preflight** that checks the one hard
prerequisite below. Then do the one-time manual steps it prints:

**Prerequisite — the `claude` CLI, installed *and* logged in.** The summarizer shells out
to `claude -p`, so:
- The **standalone CLI must be installed** — the Claude *desktop app* alone is NOT enough:
  `npm install -g @anthropic-ai/claude-code` (needs Node).
- It must be **signed in** (uses your Claude subscription, no API cost): `claude auth login`.

If either is missing, `claude -p` returns "Not logged in" instead of JSON and every card
comes out with a title but no content. `install.sh`'s preflight flags both.

1. **Email (your own Google account).** Open [script.google.com](https://script.google.com)
   → New project → paste `apps-script-mailer.gs` → **Deploy ▸ New deployment ▸ Web app**,
   **Execute as: Me**, **Who has access: Anyone** → authorize. Copy the `…/exec` URL, then:
   ```sh
   echo 'PASTE_YOUR_EXEC_URL'   > state/email-webhook.txt
   echo 'you@example.com'       > state/email-to.txt
   ```
2. **Jump links.** Grant Accessibility to the handler so it can click sessions:
   **System Settings ▸ Privacy & Security ▸ Accessibility ▸ +** → `~/Applications/ClaudeJump.app` → **ON**.
3. **Verify:** `./run.sh` — an HTML brief should appear on your Desktop, an email should
   arrive, and the "▶ open session" button in the Desktop `.html` should jump to that session.

`state/` and `logs/` are gitignored (webhook URL, recipient, brief content stay local).

**Requirements / scope:**
- The **`claude` CLI** must be installed and logged in (see Prerequisite above) — this is
  what generates the per-session summaries.
- The **jump-to-session** feature needs the **Claude desktop app**. It works two ways,
  auto-detected: if the app opens **each session in its own window** (window title = session
  title, e.g. Israeli-RTL / multi-window builds) it **raises that window**; otherwise it
  clicks the matching **Recents** sidebar row by title. If the session's window is closed and
  no Recents row matches, it just brings the app to the front so you can pick it (the card
  title = the session name). Terminal-only Claude Code gets email + brief, just no jump.
- Schedule is **Sun–Thu 07:33** (Israeli work week) — edit the `StartCalendarInterval` in
  `install.sh` for a different week/time, then re-run it.
- The brief UI is in **Hebrew**; change the labels/`dir="rtl"` in `render.js` for English.
- The email redirect page (`zeev-l.github.io/claude-jump`) is generic and shared — nothing
  to deploy. To self-host, fork [Zeev-L/claude-jump](https://github.com/Zeev-L/claude-jump),
  enable Pages, and point `JUMP_REDIRECT` in `render.js` at your URL.

## Files

| file | role |
|------|------|
| `gather.js` | deterministic transcript scanner — activity + session titles, de-noises the tool's own `claude -p` calls, merges split conversations (no model, no network). **Titled sessions only**: resolves each session's real name (incl. Claude's *auto*-generated titles) from the desktop app's session index at `~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json` (keyed by `cliSessionId` = the `.jsonl` file stem); untitled/archived sessions are skipped |
| `render.js` | renders the HTML newsletter (local + email variants) + plain-text fallback |
| `run.sh` | orchestrator: gather → summarize (JSON) → render → write → notify → email |
| `apps-script-mailer.gs` | Gmail web-app mailer (sends `htmlBody`; `?jump=`/`?open=` bounces) — deploy separately |
| `claude-jump-shim.applescript` | source for `ClaudeJump.app` (thin `claudejump://` handler) |
| `jump.applescript` | the AX automation that opens a session by title (editable without re-signing the app) |
| `install.sh` | one-shot setup / restore (dirs, ClaudeJump.app, launchd job) |

The email redirect page lives in a separate public repo: [Zeev-L/claude-jump](https://github.com/Zeev-L/claude-jump).

## Troubleshooting - what can break & how to fix it

Real failure modes hit while building this - mostly macOS/Electron/Gmail quirks, not bugs.

### Cards have a title but no content (empty מה נעשה / הפעולה האחרונה / הצעד הבא)
The summarizer (`claude -p`) isn't returning JSON — almost always **auth**. Check
`claude auth status`; if it's not `"loggedIn": true`, run `claude auth login`. If `claude`
isn't found at all, `npm install -g @anthropic-ai/claude-code` first. (The raw output is
logged to `logs/run.log`; "Not logged in · Please run /login" there is the tell.)

### Sessions are missing from the brief
Only **named** sessions are shown. A session counts as named if it has a title in the
desktop app — including Claude's **auto**-generated ones (`gather.js` reads the app's session
index for this, not just the transcript's `custom-title` record). A session still won't show
if it's **archived**, had fewer than 2 real user messages, or falls outside the "since last
brief" window. Untitled sessions are intentionally dropped.

### Email never arrives
- **The claude.ai Gmail connector won't send headless** - it requires an interactive grant,
  always denied in a scheduled run. That's why we use Apps Script; don't try to enable it.
- **Sent but empty / wrong recipient:** in an *Anyone* web app `Session.getActiveUser().getEmail()`
  is empty (caller is anonymous) so `sendEmail("")` fails silently. Fix: recipient comes from
  the POST `to` (`state/email-to.txt`), with a `getEffectiveUser()` fallback. Just set `email-to.txt`.
- **`http 405` or a "file not found" page in the log:** that's only the post-redirect response;
  `doPost` already ran and sent. `run.sh` does not follow the redirect and treats **302** as
  success. To see what the web app received, open `<exec>?diag=1`.
- **Org blocks public web apps:** open `<exec>` in a private browser window - a GET should
  return JSON, not a login page.

### "Open session" does nothing / opens an empty "General coding session"
- **Empty "General coding session" duplicates** = `claude://resume` was used (it *imports* the
  transcript as a new session). We deliberately do NOT use it. The jump uses `claudejump://`
  then `ClaudeJump.app` then UI automation that opens the *existing* session.
- **Clicking the link launches nothing** = almost always a stale LaunchServices registration
  (the original bug here): the scheme was claimed by a deleted/duplicate app. Fix by
  unregistering then re-registering the app:
  ```sh
  LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LS" -u ~/Applications/ClaudeJump.app; "$LS" -f ~/Applications/ClaudeJump.app
  ```
  then test: `open "claudejump://open?title=Some%20Session"`.
- **The app runs but the AX tree is empty** (only window-chrome buttons): Electron doesn't
  expose its accessibility tree until asked - `jump.applescript` sets `AXManualAccessibility`
  on each Claude process to force it. If you edit the script and it stops finding sessions,
  make sure that line survives.
- **Permission "doesn't stick" after granting Accessibility:** re-signing the app changes its
  code identity and RESETS the grant. After any rebuild of `ClaudeJump.app`, remove the old
  Accessibility entry and re-add it (also `xattr -dr com.apple.quarantine` it and launch once).
- **A session won't open:** the jump matches the Recents row whose name contains the session
  title, so it only works for titled sessions visible in the desktop app's Recents. Untitled
  sessions show an "open from Recents" hint instead.

### Email link shows a page instead of opening instantly
Expected and unavoidable from email: Gmail strips custom-scheme links (needs https) and
browsers won't auto-launch a custom scheme without a user gesture. So email is always
link -> page -> one click. The **Desktop `.html`** (auto-opened each morning) uses a *direct*
`claudejump://` link = genuinely one click. First time ever, approve "Open ClaudeJump?"
(tick "Always allow" to skip it afterward).

### The morning job didn't run
- Confirm it's loaded: `launchctl list | grep morning-brief`; if missing, re-run `install.sh`.
- If the Mac was asleep at 07:33 it runs on wake. Logs: `logs/run.log`, `logs/launchd.*.log`.
- `node`/`claude` not found under launchd's minimal PATH -> `run.sh` sets a PATH and
  auto-detects both; if your install dirs are unusual, add them to its `export PATH=` line.
