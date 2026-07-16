#!/usr/bin/env node
/**
 * check-summary.js — is the summarizer's output actually usable?
 *
 *   node check-summary.js <summary-file>   → exit 0 = usable, 1 = not
 *
 * The summarize step is the fragile link in the pipeline. Over time it has failed
 * as: an empty file, "Not logged in · Please run /login", "API Error: Connection
 * closed mid-response", a ```-fenced blob, and valid-looking JSON with an invalid
 * escape (\' inside Hebrew). Every one of those is NON-EMPTY, so a plain -s test
 * called it success and the brief went out with titles but no content.
 *
 * This asserts the real contract: a JSON array with at least one entry that
 * carries actual summary content. Mirrors render.js's parsing (incl. the
 * invalid-escape repair) so "valid here" means "render will show content".
 */
const fs = require("fs");

function fail() { process.exit(1); }

let raw = "";
try { raw = fs.readFileSync(process.argv[2], "utf8"); } catch (_) { fail(); }
if (!raw.trim()) fail();

const a = raw.indexOf("["), b = raw.lastIndexOf("]");
if (a === -1 || b <= a) fail();             // no array at all (error text, prose, …)

let arr = null;
const slice = raw.slice(a, b + 1);
try {
  arr = JSON.parse(slice);
} catch (_) {
  try { arr = JSON.parse(slice.replace(/\\([^"\\/bfnrtu])/g, "$1")); } catch (_) { fail(); }
}

if (!Array.isArray(arr) || arr.length === 0) fail();

// a title alone is worthless — require real content on at least one card
const hasContent = arr.some((o) =>
  o && (o.about || o.stopped || o.next || (Array.isArray(o.did) && o.did.length))
);
process.exit(hasContent ? 0 : 1);
