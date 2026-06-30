#!/usr/bin/env node
/**
 * render.js — turn (gather material + LLM summary) into a modern HTML newsletter.
 *
 *   node render.js <material.json> <summary.json> "<date-human>"
 *
 * Prints JSON to stdout: { html, text }
 *  - html: a clean, RTL, inline-styled newsletter (used as the email htmlBody
 *          AND saved as a .html on the Desktop)
 *  - text: a plain-text fallback for the email
 *
 * Section title = the session's real Claude name (material.title). Each card has
 * a one-click "open the session" link via the claudemb:// scheme handler, plus
 * the resume command as copyable text (for email clients that strip custom links).
 */
const fs = require("fs");

const material = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
let summary = [];
try {
  let raw = fs.readFileSync(process.argv[3], "utf8");
  // tolerate code fences / stray prose: extract the outermost [ ... ] array
  const a = raw.indexOf("["), b = raw.lastIndexOf("]");
  if (a !== -1 && b > a) raw = raw.slice(a, b + 1);
  summary = JSON.parse(raw);
  if (!Array.isArray(summary)) summary = [];
} catch (_) { summary = []; }
const dateHuman = process.argv[4] || "";
const bannerText = process.argv[5] || ""; // shown on idle days
// "Open Claude app" button target. From email this is the https bounce
// (clickable in Gmail) that redirects to claude://; falls back to claude://
// directly (works from the Desktop .html) when no webhook is configured.
const execBase = process.argv[6] || "";   // Apps Script /exec URL for the open-app bounce
// Two link modes:
//   "local" → direct custom-scheme links (one click, no page) — for the Desktop .html
//   "email" → https links (Gmail strips custom schemes) — bounce/redirect pages
function openAppHref(mode) {
  if (mode === "local") return "claude://";
  return execBase ? (execBase + "?open=1") : "claude://";
}

const esc = (s) => String(s == null ? "" : s)
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const byId = {};
summary.forEach((x) => { if (x && x.sessionId) byId[x.sessionId] = x; });

// palette
const C = {
  bg: "#f4f5f7", card: "#ffffff", ink: "#1f2329", sub: "#6b7280",
  line: "#e5e7eb", accent: "#4f46e5", code: "#f3f4f6", codeInk: "#374151",
};

// NOTE: there is no reliable deep link to open an existing *local* Claude Code
// session in the desktop app — `claude://resume` IMPORTS (creating duplicate
// "General coding session" entries) and `claude://code/<id>` needs a cloud
// `cse_/session_` id these local sessions don't have (and is feature-gated).
// So the card title IS the exact sidebar name; you reopen it from Recents.

// Static https redirect page (clickable in Gmail) that bounces to the
// claudejump:// handler instantly — no visible interstitial. Generic/no data,
// so one public page serves everyone.
const JUMP_REDIRECT = "https://zeev-l.github.io/claude-jump/?t=";

// "▶ open session" — jumps to the real session in the desktop app via the
// claudejump:// handler. Only when the session has a real Claude title (the
// Recents row is matched by that title); otherwise show a Recents hint.
function jumpRow(s, mode) {
  const realTitle = (s.title && s.title.trim()) ? s.title.trim() : "";
  const foot = `margin-top:14px;border-top:1px solid ${C.line};padding-top:12px;`;
  if (!realTitle) {
    return `<div style="${foot}font-size:12px;color:${C.sub};">↩︎ לחזרה: פתח את הסשן מ-Recents באפליקציה</div>`;
  }
  const href = (mode === "local")
    ? "claudejump://open?title=" + encodeURIComponent(realTitle)
    : JUMP_REDIRECT + encodeURIComponent(realTitle);
  return `<div style="${foot}">
    <a href="${esc(href)}" style="display:inline-block;background:${C.accent};color:#fff;text-decoration:none;font-size:13px;font-weight:600;padding:8px 14px;border-radius:8px;">▶ פתח את הסשן</a>
  </div>`;
}

function card(s, i, mode) {
  // join by sessionId; fall back to position (summary is returned in input order)
  const sum = byId[s.sessionId] || summary[i] || {};
  const title = (s.title && s.title.trim()) || sum.title || "סשן ללא שם";
  const did = Array.isArray(sum.did) ? sum.did : (sum.did ? [sum.did] : []);
  const stopped = sum.stopped || "";
  const next = sum.next || "";
  const when = s.lastActivityISO ? s.lastActivityISO.slice(0, 16).replace("T", " ") : "";
  const proj = s.project || "";

  const didHtml = did.length
    ? `<ul style="margin:6px 0 0;padding-inline-start:18px;color:${C.ink};font-size:14px;line-height:1.6;">`
      + did.map((d) => `<li>${esc(d)}</li>`).join("") + `</ul>`
    : "";

  const row = (label, val) => val
    ? `<div style="margin-top:10px;font-size:14px;line-height:1.6;">
         <span style="color:${C.sub};font-weight:600;">${label}</span>
         <span style="color:${C.ink};"> ${esc(val)}</span>
       </div>` : "";

  return `
  <tr><td style="padding:0 0 16px;">
    <table dir="rtl" role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.card};border:1px solid ${C.line};border-radius:14px;">
      <tr><td dir="rtl" style="padding:18px 20px;text-align:right;">
        <div style="font-size:12px;color:${C.sub};margin-bottom:2px;">${esc(proj)}${when ? " · " + esc(when) : ""}</div>
        <div style="font-size:18px;font-weight:700;color:${C.ink};line-height:1.3;">${esc(title)}</div>
        ${did.length ? `<div style="margin-top:12px;"><span style="color:${C.sub};font-weight:600;font-size:14px;">מה נעשה</span>${didHtml}</div>` : ""}
        ${row("נקודת עצירה:", stopped)}
        ${row("הצעד הבא:", next)}
        ${jumpRow(s, mode)}
      </td></tr>
    </table>
  </td></tr>`;
}

function shell(inner, intro, mode) {
  return `<!DOCTYPE html><html lang="he" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body dir="rtl" style="margin:0;padding:0;background:${C.bg};">
<table dir="rtl" role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.bg};padding:24px 12px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;">
  <tr><td align="center">
    <table dir="rtl" role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;">
      <tr><td dir="rtl" style="padding:0 4px 18px;text-align:right;">
        <div style="font-size:13px;color:${C.accent};font-weight:700;letter-spacing:.4px;">☀️ MORNING BRIEF</div>
        <div style="font-size:22px;font-weight:800;color:${C.ink};margin-top:2px;">${esc(dateHuman)}</div>
        <div style="font-size:13px;color:${C.sub};margin-top:4px;">${intro}</div>
        <div style="margin-top:12px;">
          <a href="${openAppHref(mode)}" style="display:inline-block;background:${C.ink};color:#fff;text-decoration:none;font-size:13px;font-weight:600;padding:8px 14px;border-radius:8px;">↗ פתח את אפליקציית Claude</a>
        </div>
      </td></tr>
      ${bannerText ? `<tr><td style="padding:0 4px 16px;"><div style="background:#fff7ed;border:1px solid #fed7aa;color:#9a3412;border-radius:10px;padding:11px 14px;font-size:14px;line-height:1.5;">${esc(bannerText)}</div></td></tr>` : ""}
      ${inner || `<tr><td style="padding:0 4px;"><div style="color:${C.sub};font-size:14px;">אין מה להציג עדיין.</div></td></tr>`}
      <tr><td style="padding:8px 4px 0;">
        <div style="font-size:11px;color:${C.sub};border-top:1px solid ${C.line};padding-top:12px;">
          נוצר אוטומטית מהסשנים שלך ב-Claude Code · שמות הכרטיסים תואמים ל-Recents באפליקציה.
        </div>
      </td></tr>
    </table>
  </td></tr>
</table></body></html>`;
}

function textVersion(sessions) {
  let out = `בריף בוקר — ${dateHuman}\n\n`;
  sessions.forEach((s, i) => {
    const sum = byId[s.sessionId] || summary[i] || {};
    const title = (s.title && s.title.trim()) || sum.title || "סשן ללא שם";
    out += `■ ${title}  [${s.project || ""}]\n`;
    const did = Array.isArray(sum.did) ? sum.did : [];
    did.forEach((d) => { out += `   • ${d}\n`; });
    if (sum.stopped) out += `   נקודת עצירה: ${sum.stopped}\n`;
    if (sum.next) out += `   הצעד הבא: ${sum.next}\n`;
    out += `   לחזרה: פתח "${title}" מ-Recents באפליקציה\n\n`;
  });
  return out;
}

const sessions = material.sessions || [];
const intro = bannerText ? "תזכורת מהבריף האחרון." : "סיכום הפעילות שלך מאז הבריף הקודם.";
const innerLocal = sessions.map((s, i) => card(s, i, "local")).join("");
const innerEmail = sessions.map((s, i) => card(s, i, "email")).join("");
process.stdout.write(JSON.stringify({
  html: shell(innerLocal, intro, "local"),   // Desktop .html — direct claudejump:// (one click)
  emailHtml: shell(innerEmail, intro, "email"), // email body — https redirect (Gmail-clickable)
  text: textVersion(sessions),
}));
