/**
 * Google Drive export (optional, Apps Script version) -- see docs/google-drive.md.
 *
 * Does the same job as scripts/00_drive_export.R, but runs inside Google, with nothing to
 * install: it finds every Google Sheet below SOURCE_FOLDER_ID, converts each one to a real
 * .xlsx file, and saves it into DEST_FOLDER_ID. Real .xlsx files already in Drive are left
 * alone -- they do not have the "Google Sheet" problem described in docs/google-drive.md, so
 * they only need DEST_FOLDER_ID to be set up as Drive for Desktop reads it (or to be the same
 * folder as SOURCE_FOLDER_ID).
 *
 * Set-up:
 *   1. Go to script.google.com, create a new project, paste this whole file in.
 *   2. Fill in SOURCE_FOLDER_ID and DEST_FOLDER_ID below (the id is the part of the folder's
 *      URL after "folders/"). Adjust FILE_PATTERNS / EXCLUDE_PATTERNS to match
 *      `source: file_patterns` / `source: exclude_patterns` in config.yml.
 *   3. Run exportDriveSheetsToXlsx() once from the editor (Run menu) and approve the
 *      permissions it asks for (read Drive, in DEST_FOLDER_ID: write).
 *   4. Optional: Triggers (clock icon) -> Add Trigger -> run exportDriveSheetsToXlsx on a
 *      time-driven schedule, so DEST_FOLDER_ID always has fresh .xlsx copies.
 *
 * A file whose Drive "last updated" time has not changed since the last run is left alone,
 * unless FORCE_REFRESH is true. A manifest CSV (same columns as the R script's) is kept in
 * DEST_FOLDER_ID as drive_export_manifest.csv.
 */

var SOURCE_FOLDER_ID = "PUT-THE-SOURCE-FOLDER-ID-HERE";
var DEST_FOLDER_ID = "PUT-THE-DESTINATION-FOLDER-ID-HERE";
var FORCE_REFRESH = false;

// Keep these in sync with source: file_patterns / source: exclude_patterns in config.yml.
// A file is exported if its name (with ".xlsx" added) matches ANY pattern and NONE of the
// exclude patterns. Patterns are plain JavaScript regular expressions, matched case-insensitively.
var FILE_PATTERNS = [
  /ECW \(Results\) template.*\.xlsx$/,
  /ECW \(Programme\) template.*\.xlsx$/,
  /ECW \(Finance\) template.*\.xlsx$/,
  /ECW \(Aligned funding\) template.*\.xlsx$/
];
var EXCLUDE_PATTERNS = [/^ARCHIVED/];

var MANIFEST_NAME = "drive_export_manifest.csv";
var MANIFEST_HEADER = ["id", "name", "kind", "dest", "modified", "md5", "status", "n_tables", "exported_at"];

/** Entry point: run this. */
function exportDriveSheetsToXlsx() {
  var destFolder = DriveApp.getFolderById(DEST_FOLDER_ID);
  var previous = readManifest(destFolder);
  var sheets = [];
  listGoogleSheetsRecursive(DriveApp.getFolderById(SOURCE_FOLDER_ID), sheets);

  var exportedAt = new Date().toISOString();
  var rows = [];
  var nDownloaded = 0, nUpToDate = 0, nError = 0;

  sheets.forEach(function (file) {
    var name = file.getName() + ".xlsx";
    if (!matchesAnyPattern(name, FILE_PATTERNS) || matchesAnyPattern(name, EXCLUDE_PATTERNS)) return;

    var id = file.getId();
    var modified = file.getLastUpdated().toISOString();
    var prior = previous[id];
    var existing = destFolder.getFilesByName(name);
    var destFile = existing.hasNext() ? existing.next() : null;

    if (!FORCE_REFRESH && prior && prior.modified === modified && destFile) {
      rows.push([id, name, "sheet", name, modified, prior.md5 || "", "up_to_date", prior.n_tables || "", exportedAt]);
      nUpToDate++;
      return;
    }

    try {
      var blob = file.getAs(MimeType.MICROSOFT_EXCEL);
      if (destFile) destFile.setTrashed(true);        // File.setContent() is for text; replace instead
      destFolder.createFile(blob).setName(name);

      var md5 = md5OfBlob(blob);
      var nTables = countExcelTables(blob);
      if (nTables === 0) {
        Logger.log("WARNING: " + name + " has no Excel Table. Google Sheets does not keep " +
          "named Excel tables across an export; Combiner needs them.");
      }
      rows.push([id, name, "sheet", name, modified, md5, prior ? "updated" : "downloaded", nTables, exportedAt]);
      nDownloaded++;
    } catch (e) {
      Logger.log("ERROR exporting " + name + ": " + e);
      rows.push([id, name, "sheet", name, modified, (prior && prior.md5) || "", "error", "", exportedAt]);
      nError++;
    }
  });

  writeManifest(destFolder, rows);
  Logger.log("Done: " + nDownloaded + " downloaded/updated, " + nUpToDate + " up to date, " + nError + " error(s).");
}

/** All Google Sheets below `folder`, recursing into subfolders; appends File objects to `out`. */
function listGoogleSheetsRecursive(folder, out) {
  var files = folder.getFilesByType(MimeType.GOOGLE_SHEETS);
  while (files.hasNext()) out.push(files.next());
  var subfolders = folder.getFolders();
  while (subfolders.hasNext()) listGoogleSheetsRecursive(subfolders.next(), out);
}

function matchesAnyPattern(name, patterns) {
  return patterns.some(function (re) { return re.test(name); });
}

/** MD5 of a Blob's bytes, as a lower-case hex string (matches Drive's own md5Checksum). */
function md5OfBlob(blob) {
  var digest = Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, blob.getBytes());
  return digest.map(function (b) {
    b = (b < 0) ? b + 256 : b;
    return (b < 16 ? "0" : "") + b.toString(16);
  }).join("");
}

/** Number of Excel Tables in an .xlsx Blob (one xl/tables/tableN.xml entry per table). */
function countExcelTables(blob) {
  try {
    var entries = Utilities.unzip(blob);
    var count = 0;
    entries.forEach(function (entry) {
      if (/^xl\/tables\/table\d+\.xml$/.test(entry.getName())) count++;
    });
    return count;
  } catch (e) {
    return "";
  }
}

/** Previous manifest from DEST_FOLDER_ID, as {id: {modified, md5, n_tables}}, or {} if none yet. */
function readManifest(destFolder) {
  var files = destFolder.getFilesByName(MANIFEST_NAME);
  if (!files.hasNext()) return {};
  var lines = files.next().getBlob().getDataAsString().split("\n").filter(function (l) { return l.length; });
  var out = {};
  for (var i = 1; i < lines.length; i++) {           // skip the header row
    var cols = parseCsvLine(lines[i]);
    if (cols.length < 9) continue;
    out[cols[0]] = { modified: cols[4], md5: cols[5], n_tables: cols[7] };
  }
  return out;
}

/** Write the manifest CSV into DEST_FOLDER_ID, replacing any previous copy. */
function writeManifest(destFolder, rows) {
  var csv = [MANIFEST_HEADER].concat(rows).map(function (row) {
    return row.map(csvEscape).join(",");
  }).join("\n");
  var existing = destFolder.getFilesByName(MANIFEST_NAME);
  if (existing.hasNext()) existing.next().setContent(csv);
  else destFolder.createFile(MANIFEST_NAME, csv, MimeType.CSV);
}

function csvEscape(value) {
  value = String(value === undefined || value === null ? "" : value);
  return /[",\n]/.test(value) ? '"' + value.replace(/"/g, '""') + '"' : value;
}

/** Minimal RFC4180 CSV line parser (handles quoted fields with commas/escaped quotes). */
function parseCsvLine(line) {
  var out = [], field = "", inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    var c = line[i];
    if (inQuotes) {
      if (c === '"' && line[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') inQuotes = false;
      else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ",") { out.push(field); field = ""; }
    else field += c;
  }
  out.push(field);
  return out;
}
