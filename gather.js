#!/usr/bin/env node
/**
 * gather.js — Morning Brief material collector
 * --------------------------------------------
 * Walks ~/.claude/projects/<encoded-cwd>/*.jsonl, finds everything you touched
 * SINCE the last brief, and prints compact raw material for the summarizer.
 *
 * Output: JSON to stdout with:
 *   { since, now, hasActivity, lastActivityISO, sessions: [...] }
 *
 * "Since last brief" is read from state/last-brief.txt (ISO timestamp).
 * On first run (no marker) it defaults to 3 days back so you get a real digest.
 *
 * Deterministic, no network, no model. This is the ground-truth layer.
 */
const fs = require("fs");
const path = require("path");
const os = require("os");

const PROJECTS_DIR = path.join(os.homedir(), ".claude", "projects");
const STATE_DIR = path.join(os.homedir(), ".claude", "morning-brief", "state");
const MARKER = path.join(STATE_DIR, "last-brief.txt");

// --- caps so the summarizer prompt stays sane ---
const MAX_USER_MSGS = 18;       // per session
const MAX_ASST_TAIL = 3;        // last N assistant texts per session
const USER_TRUNC = 320;
const ASST_TRUNC = 600;
const TOTAL_BUDGET = 45000;     // approx chars across all sessions

function readSince() {
  try {
    const raw = fs.readFileSync(MARKER, "utf8").trim();
    const t = Date.parse(raw);
    if (!Number.isNaN(t)) return t;
  } catch (_) {}
  // first run: 3 days back
  return Date.now() - 3 * 24 * 60 * 60 * 1000;
}

// content can be a string or an array of blocks; pull human-readable text only
function extractText(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .filter((c) => c && c.type === "text" && typeof c.text === "string")
      .map((c) => c.text)
      .join("\n");
  }
  return "";
}

// skip system-reminder / tool noise injected into "user" role
function isNoise(text) {
  if (!text) return true;
  const t = text.trimStart();
  if (t.startsWith("<")) return true;            // <system-reminder>, <command-...>
  if (t.startsWith("Caveat:")) return true;
  if (/^\[Request interrupted/.test(t)) return true;
  return false;
}

function cleanProjectName(dirName, cwd) {
  if (cwd) return cwd.replace(os.homedir(), "~");
  // fallback: best-effort decode of the encoded dir name
  return dirName.replace(/^-/, "/").replace(/-/g, "/");
}

function main() {
  const since = readSince();
  const now = Date.now();
  let dirs = [];
  try {
    dirs = fs.readdirSync(PROJECTS_DIR);
  } catch (_) {
    process.stdout.write(JSON.stringify({ since: new Date(since).toISOString(), now: new Date(now).toISOString(), hasActivity: false, lastActivityISO: null, sessions: [] }));
    return;
  }

  let globalLastActivity = 0;
  const sessions = [];

  for (const dir of dirs) {
    const dirPath = path.join(PROJECTS_DIR, dir);
    let files = [];
    try {
      if (!fs.statSync(dirPath).isDirectory()) continue;
      files = fs.readdirSync(dirPath).filter((f) => f.endsWith(".jsonl"));
    } catch (_) { continue; }

    for (const file of files) {
      const fp = path.join(dirPath, file);
      let stat;
      try { stat = fs.statSync(fp); } catch (_) { continue; }

      let raw;
      try { raw = fs.readFileSync(fp, "utf8"); } catch (_) { continue; }
      const lines = raw.split("\n");

      let cwd = null;
      let sessionLast = 0;
      let title = null;          // the session's Claude title (sidebar name)
      let isInteractive = false; // real interactive session? (vs. a headless `claude -p` call)
      let realUserTotal = 0;     // human prompts across the whole transcript (not just since)
      let rootUuid = null;       // uuid of the first user msg = the conversation root
      const userMsgs = [];
      const asstMsgs = [];

      for (const line of lines) {
        if (!line) continue;
        let o;
        try { o = JSON.parse(line); } catch (_) { continue; }
        if (o.cwd && !cwd) cwd = o.cwd;
        if (o.type === "custom-title" && o.customTitle) title = o.customTitle; // last wins
        // interactive sessions emit `system`/`mode` records; headless `claude -p`
        // calls (the tool's own summarizer/mailer invocations) do NOT.
        if (o.type === "system" || o.type === "mode") isInteractive = true;
        if (o.type === "user" && o.message) {
          if (!rootUuid && o.uuid) rootUuid = o.uuid; // shared across split/resumed transcripts
          const tt = extractText(o.message.content);
          if (!isNoise(tt)) realUserTotal++;
        }
        const ts = o.timestamp ? Date.parse(o.timestamp) : NaN;
        if (!Number.isNaN(ts)) {
          if (ts > sessionLast) sessionLast = ts;
          if (ts > globalLastActivity) globalLastActivity = ts;
        }
        // only collect content newer than "since"
        if (Number.isNaN(ts) || ts <= since) continue;
        const m = o.message;
        if (!m) continue;
        if (o.type === "user") {
          const t = extractText(m.content);
          if (!isNoise(t)) userMsgs.push(t.trim().slice(0, USER_TRUNC));
        } else if (o.type === "assistant") {
          const t = extractText(m.content);
          if (t && t.trim()) asstMsgs.push(t.trim().slice(0, ASST_TRUNC));
        }
      }

      if (userMsgs.length === 0 && asstMsgs.length === 0) continue; // nothing new in this session
      if (!isInteractive) continue;   // skip the tool's own headless `claude -p` calls
      if (realUserTotal < 2) continue; // skip trivial/abandoned fragments

      sessions.push({
        project: cleanProjectName(dir, cwd),
        cwd: cwd || null,
        sessionId: file.replace(/\.jsonl$/, ""),
        rootUuid: rootUuid,
        title: title,
        lastActivity: sessionLast,
        lastActivityISO: new Date(sessionLast).toISOString(),
        userMsgs: userMsgs.slice(0, MAX_USER_MSGS),
        userMsgCount: userMsgs.length,
        lastAssistant: asstMsgs.slice(-MAX_ASST_TAIL),
      });
    }
  }

  // --- merge transcripts that belong to the same conversation -----------------
  // A single Claude conversation can span several .jsonl files (e.g. after a
  // compaction/resume), so group by title. Untitled real sessions stay separate
  // (keyed by their own id). The resume target is the most-recent transcript.
  sessions.sort((a, b) => a.lastActivity - b.lastActivity);
  const groups = new Map();
  for (const s of sessions) {
    // same conversation across split/resumed transcripts shares the root uuid;
    // fall back to title, then to the session id.
    const key = s.rootUuid ? "r:" + s.rootUuid
      : (s.title && s.title.trim()) ? "t:" + s.title.trim()
      : "s:" + s.sessionId;
    if (!groups.has(key)) {
      groups.set(key, {
        project: s.project, cwd: s.cwd, sessionId: s.sessionId, title: s.title,
        lastActivity: s.lastActivity, userMsgs: [], lastAssistant: [],
      });
    }
    const g = groups.get(key);
    if (s.title && s.title.trim()) g.title = s.title; // prefer a real Claude title over none
    if (s.lastActivity >= g.lastActivity) { // newest transcript wins for resume + project
      g.lastActivity = s.lastActivity; g.sessionId = s.sessionId; g.cwd = s.cwd || g.cwd; g.project = s.project;
    }
    g.userMsgs.push(...s.userMsgs);
    g.lastAssistant.push(...s.lastAssistant);
  }

  let units = Array.from(groups.values())
    .sort((a, b) => b.lastActivity - a.lastActivity)   // newest first (closest to send time)
    .map((g) => ({
      project: g.project,
      cwd: g.cwd,
      sessionId: g.sessionId,
      title: g.title,
      resumeCmd: g.cwd
        ? `cd "${g.cwd}" && claude --resume ${g.sessionId}`
        : `claude --resume ${g.sessionId}`,
      lastActivityISO: new Date(g.lastActivity).toISOString(),
      userMsgs: g.userMsgs.slice(0, MAX_USER_MSGS),
      lastAssistant: g.lastAssistant.slice(-MAX_ASST_TAIL),
      _sort: g.lastActivity,
    }));

  // enforce a rough total budget — units are newest-first, so iterate forward
  // and drop the oldest if we run over.
  let used = 0;
  const kept = [];
  for (let i = 0; i < units.length; i++) {
    const size = JSON.stringify(units[i]).length;
    if (used + size > TOTAL_BUDGET && kept.length > 0) break;
    used += size;
    kept.push(units[i]);
  }
  kept.forEach((u) => delete u._sort);

  process.stdout.write(JSON.stringify({
    since: new Date(since).toISOString(),
    now: new Date(now).toISOString(),
    hasActivity: kept.length > 0,
    lastActivityISO: globalLastActivity ? new Date(globalLastActivity).toISOString() : null,
    sessions: kept,
  }, null, 2));
}

main();
