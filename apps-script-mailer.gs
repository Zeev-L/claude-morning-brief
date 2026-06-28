/**
 * Morning Brief — Mailer (Apps Script Web App)
 * --------------------------------------------
 * A tiny endpoint that emails your morning brief to yourself, server-side,
 * from your own Google account. No local credentials, runs fully headless.
 *
 * The deployment /exec URL IS the secret (long, unguessable — Slack-style),
 * exactly like the MiK webhook pattern.
 *
 * SETUP (one time):
 *   1. script.google.com → New project → paste this file.
 *   2. Deploy → New deployment → type "Web app".
 *        - Execute as: Me (your account)
 *        - Who has access: Anyone   (the long URL is the secret)
 *   3. Authorize when prompted (gives it permission to send mail as you).
 *   4. Copy the Web app URL (ends in /exec).
 *   5. Save it locally:
 *        echo 'PASTE_THE_EXEC_URL_HERE' > ~/.claude/morning-brief/state/email-webhook.txt
 *
 * Test from the terminal:
 *   curl -s -X POST "$(cat ~/.claude/morning-brief/state/email-webhook.txt)" \
 *     -H 'Content-Type: application/json' \
 *     --data '{"subject":"MB test","body":"hello from the webhook"}'
 */

function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);
    var subject = data.subject || 'Morning Brief';
    var body = data.body || '(empty)';

    // recipient = the account running the script (you)
    var to = Session.getActiveUser().getEmail();

    // markdown body sent as plain text — renders readably in Gmail.
    GmailApp.sendEmail(to, subject, body);

    return ContentService
      .createTextOutput(JSON.stringify({ ok: true, to: to }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: false, error: String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// optional: lets you open the /exec URL in a browser to confirm it's live
function doGet() {
  return ContentService
    .createTextOutput(JSON.stringify({ ok: true, service: 'morning-brief-mailer' }))
    .setMimeType(ContentService.MimeType.JSON);
}
