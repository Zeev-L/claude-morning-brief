/**
 * Morning Brief — Mailer (Apps Script Web App)
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
    var subject = data.subject || 'Morning Brief';
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
  return json({ ok: true, service: 'morning-brief-mailer' });
}
