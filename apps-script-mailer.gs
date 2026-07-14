/**
 * Claude Morning Brief — Mailer (Apps Script Web App)
 * --------------------------------------------
 * A tiny endpoint that emails your morning brief to yourself, server-side,
 * from your own Google account. No local credentials, runs fully headless.
 *
 * The deployment /exec URL IS the secret (long, unguessable — Slack-style),
 * exactly like the MiK webhook pattern.
 *
 * Deploy as: Web app, Execute as = Me, Who has access = Anyone.
 * run.sh POSTs JSON {to, subject, body}. The recipient is taken from `to`
 * (the script owner Session can be blank for "Anyone"-access web apps).
 *
 * GET ?diag=1 returns the diagnostics of the last POST (what the web app
 * actually received + whether the email sent) — handy for debugging headless.
 */

function json(o) {
  return ContentService
    .createTextOutput(JSON.stringify(o))
    .setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  var diag = {};
  try {
    diag.hasE = !!e;
    diag.hasPostData = !!(e && e.postData);
    diag.contentType = (e && e.postData) ? e.postData.type : null;
    diag.paramKeys = (e && e.parameter) ? Object.keys(e.parameter) : [];

    // body may arrive as a raw JSON post body OR as form parameters
    var raw = (e && e.postData && e.postData.contents) ? e.postData.contents : null;
    diag.rawLen = raw ? raw.length : 0;
    var data = raw ? JSON.parse(raw) : ((e && e.parameter) ? e.parameter : {});

    var to = data.to || Session.getEffectiveUser().getEmail();
    var subject = data.subject || 'Claude Morning Brief';
    var body = data.body || '(empty)';
    diag.to = to;
    diag.hasHtml = !!data.htmlBody;

    var options = {};
    if (data.htmlBody) options.htmlBody = data.htmlBody;
    GmailApp.sendEmail(to, subject, body, options);
    diag.sent = true;

    PropertiesService.getScriptProperties().setProperty('lastDiag', JSON.stringify(diag));
    return json({ ok: true, to: to });
  } catch (err) {
    diag.error = String(err);
    try { PropertiesService.getScriptProperties().setProperty('lastDiag', JSON.stringify(diag)); } catch (e2) {}
    return json({ ok: false, error: String(err) });
  }
}

function doGet(e) {
  if (e && e.parameter && e.parameter.diag) {
    var d = PropertiesService.getScriptProperties().getProperty('lastDiag') || '{}';
    return json({ lastDiag: JSON.parse(d) });
  }
  // bounce page: https link (clickable in Gmail) -> redirects to a custom scheme
  // that opens the desktop app.
  //   ?open=1        -> claude://            (just focus the app)
  //   ?jump=<title>  -> claudejump://open?title=<title>  (jump to that session)
  if (e && e.parameter && (e.parameter.open || e.parameter.jump)) {
    var scheme;
    if (e.parameter.jump) {
      scheme = 'claudejump://open?title=' + encodeURIComponent(e.parameter.jump);
    } else {
      scheme = 'claude://';
    }
    var html =
      '<!DOCTYPE html><html lang="he" dir="rtl"><head><meta charset="utf-8">' +
      '<meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif;' +
      'text-align:center;padding:54px 20px;background:#f4f5f7;color:#1f2329}' +
      '.b{display:inline-block;background:#1f2329;color:#fff;text-decoration:none;font-size:16px;' +
      'font-weight:600;padding:14px 24px;border-radius:10px;margin-top:18px}' +
      '.s{color:#6b7280;font-size:13px;margin-top:14px}</style></head><body>' +
      '<div style="font-size:19px;font-weight:700">פותח את אפליקציית Claude…</div>' +
      '<a class="b" href="' + scheme + '">↗ פתח את Claude</a>' +
      '<div class="s">אם לא נפתח לבד — לחץ על הכפתור.</div>' +
      '<script>setTimeout(function(){try{top.location.href="' + scheme + '"}catch(e){location.href="' + scheme + '"}},250);</script>' +
      '</body></html>';
    return HtmlService.createHtmlOutput(html)
      .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL)
      .setTitle('Open Claude');
  }
  return json({ ok: true, service: 'morning-brief-mailer' });
}
