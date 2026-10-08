/**
 * Healer Boy's — Google Sheets sync
 * ---------------------------------
 * 1. Open the Google Sheet in that Drive folder.
 * 2. Extensions → Apps Script → paste this file → Save.
 * 3. Deploy → New deployment → Web app
 *    Execute as: Me
 *    Who has access: Anyone
 * 4. Copy the Web app URL into index.html as SHEET_WEBHOOK_URL.
 *
 * Apps from the Healer Boy's app append a row here:
 *   Members | Payments | Donations
 */
const SHEETS = {
  member: "Members",
  payment: "Payments",
  donation: "Donations"
};

const HEADERS = {
  member: ["Time", "Action", "ID", "Name", "Email", "Avatar URL"],
  payment: ["Time", "Action", "ID", "Member ID", "Member Name", "Type", "Amount", "Date"],
  donation: ["Time", "Action", "ID", "Description", "Amount", "Date"]
};

function doPost(e) {
  try {
    const body = JSON.parse((e && e.postData && e.postData.contents) || "{}");
    const kind = String(body.kind || "");
    const action = String(body.action || "add");
    const row = body.row || {};
    const sheetName = SHEETS[kind];
    if (!sheetName) {
      return json({ ok: false, error: "Unknown kind: " + kind });
    }

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    let sheet = ss.getSheetByName(sheetName);
    if (!sheet) sheet = ss.insertSheet(sheetName);
    ensureHeader(sheet, HEADERS[kind]);

    const stamp = new Date();
    let values;
    if (kind === "member") {
      values = [stamp, action, row.id || "", row.name || "", row.email || "", row.avatar_url || ""];
    } else if (kind === "payment") {
      values = [stamp, action, row.id || "", row.member_id || "", row.member_name || "", row.type || "", Number(row.amount || 0), row.date || ""];
    } else {
      values = [stamp, action, row.id || "", row.description || "", Number(row.amount || 0), row.date || ""];
    }

    sheet.appendRow(values);
    return json({ ok: true, sheet: sheetName });
  } catch (err) {
    return json({ ok: false, error: String(err) });
  }
}

function doGet() {
  return json({ ok: true, app: "Healer Boy's sheet sync" });
}

function ensureHeader(sheet, headers) {
  if (sheet.getLastRow() === 0) {
    sheet.appendRow(headers);
    sheet.getRange(1, 1, 1, headers.length).setFontWeight("bold");
    sheet.setFrozenRows(1);
  }
}

function json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
