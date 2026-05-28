import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { pathToFileURL } from "node:url";

const root = process.cwd();
const dataDir = path.join(root, "data");
const execFileAsync = promisify(execFile);

function parseCsv(text) {
  const rows = [];
  let field = "";
  let row = [];
  let inQuotes = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];

    if (char === "\"") {
      if (inQuotes && next === "\"") {
        field += "\"";
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char === "," && !inQuotes) {
      row.push(field);
      field = "";
      continue;
    }

    if ((char === "\n" || char === "\r") && !inQuotes) {
      if (char === "\r" && next === "\n") {
        index += 1;
      }
      row.push(field);
      field = "";
      if (row.some((cell) => cell.length > 0)) {
        rows.push(row);
      }
      row = [];
      continue;
    }

    field += char;
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  const [headers, ...body] = rows;
  if (!headers) {
    return [];
  }

  return body.map((cells, rowIndex) => {
    if (cells.length !== headers.length) {
      throw new Error(`CSV row ${rowIndex + 2} has ${cells.length} cells; expected ${headers.length}.`);
    }
    return headers.reduce((acc, header, index) => {
      acc[header] = cells[index] ?? "";
      return acc;
    }, {});
  });
}

function csvEscape(value) {
  const text = String(value ?? "");
  return /[",\n\r]/.test(text) ? `"${text.replaceAll("\"", "\"\"")}"` : text;
}

function toCsv(headers, rows) {
  return [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => csvEscape(row[header])).join(","))
  ].join("\n") + "\n";
}

async function runNode(args, options = {}) {
  return execFileAsync(process.execPath, args, {
    cwd: root,
    maxBuffer: 20 * 1024 * 1024,
    ...options
  });
}

async function expectFailure(args, expectedMessage) {
  try {
    await runNode(args);
  } catch (error) {
    const output = `${error.stdout ?? ""}${error.stderr ?? ""}`;
    if (!output.includes(expectedMessage)) {
      throw new Error(`Expected failure to include "${expectedMessage}", got: ${output}`);
    }
    return;
  }
  throw new Error(`Expected command to fail: node ${args.join(" ")}`);
}

async function expectSeedValidationFailure(rows, expectedMessage) {
  const seedRoot = await fs.mkdtemp(path.join(tempDir, "seed-validation-"));
  const seedDataDir = path.join(seedRoot, "data");
  const seedGeneratedDataDir = path.join(seedRoot, "AdmissionCalculator/Data");
  await fs.cp(dataDir, seedDataDir, { recursive: true });
  await fs.mkdir(seedGeneratedDataDir, { recursive: true });
  const headers = [
    "id",
    "name",
    "rank",
    "rate_2029",
    "rate_2028",
    "rate_2027",
    "rate_2026",
    "rate_2025",
    "rate_2024",
    "source_url",
    "source_note",
    "data_quality"
  ];
  await fs.writeFile(path.join(seedDataDir, "liberal_arts_colleges.csv"), toCsv(headers, rows), "utf8");
  try {
    await execFileAsync(process.execPath, [path.join(root, "scripts/update-admissions-data.mjs"), "--check"], {
      cwd: seedRoot,
      maxBuffer: 20 * 1024 * 1024
    });
  } catch (error) {
    const output = `${error.stdout ?? ""}${error.stderr ?? ""}`;
    if (!output.includes(expectedMessage)) {
      throw new Error(`Expected seed validation failure to include "${expectedMessage}", got: ${output}`);
    }
    return;
  } finally {
    await fs.rm(seedRoot, { recursive: true, force: true });
  }
  throw new Error(`Expected update-admissions-data seed validation to fail with: ${expectedMessage}`);
}

const colleges = parseCsv(await fs.readFile(path.join(dataDir, "liberal_arts_colleges.csv"), "utf8"));
const unitIDsByCollegeID = JSON.parse(await fs.readFile(path.join(dataDir, "liberal_arts_unitids.json"), "utf8"));
const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "admission-lac-check-"));

try {
  const scorecardFixture = path.join(tempDir, "Most-Recent-Cohorts-Institution.csv");
  const staleScorecardFixture = path.join(tempDir, "MERGED2021_22_PP.csv");
  const latestRawScorecardFixture = path.join(tempDir, "MERGED2022_23_PP.csv");
  const rawScorecardZip = path.join(tempDir, "College_Scorecard_Raw_Data_fixture.zip");
  const unknownScorecardFixture = path.join(tempDir, "scorecard-looking-but-unknown.csv");
  const unknownScorecardZip = path.join(tempDir, "scorecard-looking-but-unknown.zip");
  const scorecardDiscoveryHTML = path.join(tempDir, "scorecard-data-page.html");
  const scorecardDiscoveryWithoutInstitutionHTML = path.join(tempDir, "scorecard-data-page-without-institution.html");
  const scorecardReviewCSV = path.join(tempDir, "scorecard_liberal_arts_rates.csv");
  const rawScorecardCSVReviewCSV = path.join(tempDir, "scorecard_liberal_arts_rates_raw_csv.csv");
  const rawScorecardReviewCSV = path.join(tempDir, "scorecard_liberal_arts_rates_raw_zip.csv");
  const rawScorecardAppliedCSV = path.join(tempDir, "liberal_arts_colleges_raw_scorecard_applied.csv");
  const badScorecardReviewCSV = path.join(tempDir, "scorecard_liberal_arts_rates_bad_unitid.csv");
  const badScorecardReviewedNameCSV = path.join(tempDir, "scorecard_liberal_arts_rates_bad_reviewed_name.csv");
  const badScorecardSourceURLCSV = path.join(tempDir, "scorecard_liberal_arts_rates_bad_source_url.csv");
  const ipedsFixture = path.join(tempDir, "ADM2024.csv");
  const ipedsReviewCSV = path.join(tempDir, "ipeds_liberal_arts_rates.csv");
  const ipedsDerivedFixture = path.join(tempDir, "DRVADM2024.csv");
  const ipedsDerivedReviewCSV = path.join(tempDir, "ipeds_liberal_arts_rates_derived.csv");
  const unknownIpedsFixture = path.join(tempDir, "ipeds-looking-but-unknown.csv");
  const unknownIpedsZip = path.join(tempDir, "ipeds-looking-but-unknown.zip");
  const ipedsReportedHTMLDir = path.join(tempDir, "reported-html");
  const badIpedsReportedUnitIDDir = path.join(tempDir, "reported-html-bad-unitid");
  const badIpedsReportedNameDir = path.join(tempDir, "reported-html-bad-name");
  const badIpedsReportedRateDir = path.join(tempDir, "reported-html-missing-rate");
  const ipedsReportedReviewCSV = path.join(tempDir, "ipeds_liberal_arts_rates_reported.csv");
  const badIpedsReviewCSV = path.join(tempDir, "ipeds_liberal_arts_rates_bad_unitid.csv");
  const badIpedsReportedSourceURLCSV = path.join(tempDir, "ipeds_liberal_arts_rates_bad_reported_source_url.csv");
  const badIpedsReportedSurveyCSV = path.join(tempDir, "ipeds_liberal_arts_rates_bad_reported_survey.csv");
  const urlManifestCSV = path.join(tempDir, "lac_official_url_manifest.csv");

  const scorecardRows = colleges.map((college) => ({
    UNITID: unitIDsByCollegeID[college.id],
    INSTNM: college.name,
    ADM_RATE: (Number(college.rate_2029) / 100).toFixed(4),
    UGDS: "2000"
  }));
  await fs.writeFile(scorecardFixture, toCsv(["UNITID", "INSTNM", "ADM_RATE", "UGDS"], scorecardRows), "utf8");
  await fs.writeFile(
    staleScorecardFixture,
    toCsv(["UNITID", "INSTNM", "ADM_RATE", "UGDS"], scorecardRows.map((row) => ({ ...row, ADM_RATE: "0.0100" }))),
    "utf8"
  );
  await fs.writeFile(latestRawScorecardFixture, toCsv(["UNITID", "INSTNM", "ADM_RATE", "UGDS"], scorecardRows), "utf8");
  await execFileAsync("zip", ["-j", "-q", rawScorecardZip, staleScorecardFixture, latestRawScorecardFixture], { cwd: tempDir });
  await fs.writeFile(unknownScorecardFixture, toCsv(["UNITID", "INSTNM", "ADM_RATE", "UGDS"], scorecardRows), "utf8");
  await execFileAsync("zip", ["-j", "-q", unknownScorecardZip, unknownScorecardFixture], { cwd: tempDir });
  await fs.writeFile(
    scorecardDiscoveryHTML,
    `<!doctype html>
<html>
  <body>
    <a href="https://ed-public-download.scorecard.network/downloads/Most-Recent-Cohorts-Field-of-Study_03232026.zip">Field of Study</a>
    <a href="https://ed-public-download.scorecard.network/downloads/College_Scorecard_Raw_Data_01162025.zip">Raw Data</a>
    <a href="https://ed-public-download.scorecard.network/downloads/Most-Recent-Cohorts-Institution_03232026.zip">Most Recent Institution-Level Data</a>
  </body>
</html>`,
    "utf8"
  );
  await fs.writeFile(
    scorecardDiscoveryWithoutInstitutionHTML,
    `<!doctype html><html><body><a href="https://ed-public-download.scorecard.network/downloads/Most-Recent-Cohorts-Field-of-Study_03232026.zip">Field of Study</a></body></html>`,
    "utf8"
  );

  await runNode([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--scorecard-csv",
    scorecardFixture,
    "--output",
    scorecardReviewCSV
  ]);
  await runNode([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--scorecard-csv",
    latestRawScorecardFixture,
    "--output",
    rawScorecardCSVReviewCSV
  ]);
  await runNode([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--scorecard-zip",
    rawScorecardZip,
    "--output",
    rawScorecardReviewCSV
  ]);

  await runNode([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    scorecardReviewCSV
  ]);
  await runNode([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    rawScorecardCSVReviewCSV
  ]);
  await runNode([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    rawScorecardReviewCSV
  ]);
  await runNode([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--official",
    rawScorecardReviewCSV,
    "--output",
    rawScorecardAppliedCSV
  ]);
  const rawScorecardReviewRows = parseCsv(await fs.readFile(rawScorecardReviewCSV, "utf8"));
  if (rawScorecardReviewRows.some((row) => row.scorecard_latest_admission_rate_percent === "1.00")) {
    throw new Error("Raw Scorecard ZIP parser used a stale MERGED CSV instead of the latest available MERGED year.");
  }
  if (rawScorecardReviewRows.some((row) => !row.source_note.includes("MERGED2022_23_PP.csv"))) {
    throw new Error("Raw Scorecard ZIP review rows must disclose the selected latest MERGED CSV in source_note.");
  }
  const rawScorecardAppliedRows = parseCsv(await fs.readFile(rawScorecardAppliedCSV, "utf8"));
  if (rawScorecardAppliedRows.some((row) => !row.source_note.includes("MERGED2022_23_PP.csv"))) {
    throw new Error("Applied LAC seed rows must preserve the selected raw Scorecard MERGED CSV in source_note.");
  }

  const badSeedScorecardRows = colleges.map((row) => ({ ...row }));
  badSeedScorecardRows[0].source_url = "https://collegescorecard.ed.gov/school/?999999";
  badSeedScorecardRows[0].source_note = `College Scorecard admission rate via UNITID ${unitIDsByCollegeID[colleges[0].id]}; manually edited bad seed row. Original IMG_0742.JPG table retained for LAC list/rank scope.`;
  badSeedScorecardRows[0].data_quality = "0.9";
  await expectSeedValidationFailure(badSeedScorecardRows, "Scorecard source_url must match reviewed UNITID");

  const lowQualityOfficialRows = colleges.map((row) => ({ ...row }));
  lowQualityOfficialRows[0].data_quality = "0.40";
  await expectSeedValidationFailure(lowQualityOfficialRows, "reviewed official data_quality >= 0.85");

  const badSeedReportedRows = colleges.map((row) => ({ ...row }));
  badSeedReportedRows[0].source_url = `https://nces.ed.gov/ipeds/reported-data/html/${unitIDsByCollegeID[colleges[0].id]}?year=2023&surveyNumber=9&viewmode=print`;
  badSeedReportedRows[0].source_note = `NCES/IPEDS admissions rate via UNITID ${unitIDsByCollegeID[colleges[0].id]}; manually edited bad seed row. Original IMG_0742.JPG table retained for LAC list/rank scope.`;
  badSeedReportedRows[0].data_quality = "0.9";
  await expectSeedValidationFailure(badSeedReportedRows, "Admissions component with surveyNumber=12");

  const inflatedReviewedSeedRows = colleges.map((row) => ({ ...row }));
  inflatedReviewedSeedRows[0].source_url = "https://github.com/qyf9794/Admission-Calculator/blob/main/data/liberal_arts_colleges.csv";
  inflatedReviewedSeedRows[0].source_note = "Extracted from user-provided IMG_0742.JPG Top30 Liberal Arts Colleges 2024-25 table; overall admit rate used as base rate";
  inflatedReviewedSeedRows[0].data_quality = "0.95";
  await expectSeedValidationFailure(inflatedReviewedSeedRows, "proxy data_quality <= 0.8");

  await expectFailure([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--scorecard-zip",
    unknownScorecardZip,
    "--output",
    path.join(tempDir, "scorecard_liberal_arts_rates_unknown_zip.csv")
  ], "does not contain a Scorecard institution CSV or raw MERGEDYYYY_YY_PP CSV file");

  await expectFailure([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--scorecard-csv",
    unknownScorecardFixture,
    "--output",
    path.join(tempDir, "scorecard_liberal_arts_rates_unknown_csv.csv")
  ], "Scorecard CSV");

  const { stdout: discoveredScorecardURL } = await runNode([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--check-scorecard-latest-url",
    "--scorecard-page-html",
    scorecardDiscoveryHTML
  ]);
  if (!discoveredScorecardURL.includes("Most-Recent-Cohorts-Institution_03232026.zip")) {
    throw new Error(`Scorecard latest URL discovery should prefer the institution-level file, got: ${discoveredScorecardURL}`);
  }

  await expectFailure([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--check-scorecard-latest-url",
    "--scorecard-page-html",
    scorecardDiscoveryWithoutInstitutionHTML
  ], "Could not discover an official Scorecard institution CSV/ZIP URL");

  await expectFailure([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--check-scorecard-latest-url",
    "--scorecard-discovery-url",
    "https://example.com/data/"
  ], "official College Scorecard data page");

  await runNode([
    "scripts/write-lac-official-url-manifest.mjs",
    "--output",
    urlManifestCSV,
    "--year",
    "2024"
  ]);
  await runNode([
    "scripts/write-lac-official-url-manifest.mjs",
    "--output",
    urlManifestCSV,
    "--year",
    "2024",
    "--check"
  ]);
  const manifestRows = parseCsv(await fs.readFile(urlManifestCSV, "utf8"));
  if (manifestRows.length !== colleges.length) {
    throw new Error(`Official URL manifest row count ${manifestRows.length} does not match LAC seed row count ${colleges.length}.`);
  }
  for (const row of manifestRows) {
    const expectedUnitID = unitIDsByCollegeID[row.id];
    if (row.ipeds_unitid !== expectedUnitID) {
      throw new Error(`Official URL manifest row ${row.id} uses UNITID ${row.ipeds_unitid}; expected ${expectedUnitID}.`);
    }
    if (row.scorecard_school_url !== `https://collegescorecard.ed.gov/school/?${expectedUnitID}`) {
      throw new Error(`Official URL manifest row ${row.id} has an unexpected Scorecard URL.`);
    }
    if (row.nces_reported_admissions_url !== `https://nces.ed.gov/ipeds/reported-data/html/${expectedUnitID}?year=2024&surveyNumber=12&viewmode=print`) {
      throw new Error(`Official URL manifest row ${row.id} has an unexpected NCES Reported Data URL.`);
    }
    if (row.reported_html_filename !== `${expectedUnitID}.html`) {
      throw new Error(`Official URL manifest row ${row.id} has an unexpected local HTML filename.`);
    }
  }

  const scorecardHeaders = [
    "id",
    "name",
    "rank",
    "scorecard_unitid",
    "scorecard_name",
    "scorecard_latest_admission_rate_percent",
    "scorecard_student_size",
    "source_url",
    "source_note"
  ];
  const scorecardReviewRows = parseCsv(await fs.readFile(scorecardReviewCSV, "utf8"));
  const badScorecardUnitIDRows = scorecardReviewRows.map((row) => ({ ...row }));
  badScorecardUnitIDRows[0].scorecard_unitid = "999999";
  await fs.writeFile(
    badScorecardReviewCSV,
    toCsv(scorecardHeaders, badScorecardUnitIDRows),
    "utf8"
  );
  const badScorecardReviewedNameRows = scorecardReviewRows.map((row) => ({ ...row }));
  badScorecardReviewedNameRows[0].scorecard_name = "Different College";
  await fs.writeFile(
    badScorecardReviewedNameCSV,
    toCsv(scorecardHeaders, badScorecardReviewedNameRows),
    "utf8"
  );
  const badScorecardSourceURLRows = scorecardReviewRows.map((row) => ({ ...row }));
  badScorecardSourceURLRows[0].source_url = "https://collegescorecard.ed.gov/school/?999999";
  await fs.writeFile(
    badScorecardSourceURLCSV,
    toCsv(scorecardHeaders, badScorecardSourceURLRows),
    "utf8"
  );

  await expectFailure([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--check-scorecard-url",
    "https://example.com/Most-Recent-Cohorts-Institution.csv",
  ], "official College Scorecard download host");

  await expectFailure([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--check-scorecard-url",
    pathToFileURL(scorecardFixture).href,
  ], "must use https:// for official data downloads");

  await expectFailure([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--check-scorecard-url",
    "https://ed-public-download.scorecard.network/downloads/Most-Recent-Cohorts-Field-of-Study_03232026.zip",
  ], "Scorecard institution CSV/ZIP or raw data ZIP");

  await runNode([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--check-scorecard-url",
    "https://ed-public-download.scorecard.network/downloads/Most-Recent-Cohorts-Institution_03232026.zip"
  ]);
  await runNode([
    "scripts/fetch-scorecard-lac-rates.mjs",
    "--check-scorecard-url",
    "https://ed-public-download.scorecard.network/downloads/College_Scorecard_Raw_Data_03232026.zip"
  ]);

  await expectFailure([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    badScorecardReviewCSV
  ], `expected ${unitIDsByCollegeID[colleges[0].id]}`);

  await expectFailure([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    badScorecardReviewedNameCSV
  ], "reviewed school name");

  await expectFailure([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    badScorecardSourceURLCSV
  ], "Scorecard source URL must match UNITID");

  const ipedsRows = colleges.map((college) => {
    const applicants = 10000;
    const admitted = Math.round(Number(college.rate_2029) / 100 * applicants);
    return {
      UNITID: unitIDsByCollegeID[college.id],
      APPLCN: String(applicants),
      ADMSSN: String(admitted)
    };
  });
  await fs.writeFile(ipedsFixture, toCsv(["UNITID", "APPLCN", "ADMSSN"], ipedsRows), "utf8");
  await fs.writeFile(
    ipedsDerivedFixture,
    toCsv(["UNITID", "DVADM01"], colleges.map((college) => ({
      UNITID: unitIDsByCollegeID[college.id],
      DVADM01: Number(college.rate_2029).toFixed(2)
    }))),
    "utf8"
  );
  await fs.writeFile(
    unknownIpedsFixture,
    toCsv(["UNITID", "DVADM01"], colleges.map((college) => ({
      UNITID: unitIDsByCollegeID[college.id],
      DVADM01: Number(college.rate_2029).toFixed(2)
    }))),
    "utf8"
  );
  await execFileAsync("zip", ["-j", "-q", unknownIpedsZip, unknownIpedsFixture], { cwd: tempDir });
  await fs.mkdir(ipedsReportedHTMLDir, { recursive: true });
  await Promise.all(colleges.map((college) => {
    const unitID = unitIDsByCollegeID[college.id];
    const rate = Number(college.rate_2029).toFixed(2);
    const html = `<!doctype html>
<html>
<head><title>Reported Data</title></head>
<body>
  <h1>Admissions 2023-24</h1>
  <p>Institution: ${college.name} (${unitID})</p>
  <table>
    <tr><th>ADMISSIONS INFORMATION</th><th>Total</th><th>Male</th><th>Female</th></tr>
    <tr><td>Number of applicants</td><td>10,000</td><td>4,800</td><td>5,200</td></tr>
    <tr><td>Percent admitted</td><td>${rate}%</td><td>${rate}%</td><td>${rate}%</td></tr>
  </table>
</body>
</html>`;
    return fs.writeFile(path.join(ipedsReportedHTMLDir, `${unitID}.html`), html, "utf8");
  }));
  await fs.cp(ipedsReportedHTMLDir, badIpedsReportedUnitIDDir, { recursive: true });
  await fs.cp(ipedsReportedHTMLDir, badIpedsReportedNameDir, { recursive: true });
  await fs.cp(ipedsReportedHTMLDir, badIpedsReportedRateDir, { recursive: true });
  await fs.writeFile(
    path.join(badIpedsReportedUnitIDDir, `${unitIDsByCollegeID[colleges[0].id]}.html`),
    `<!doctype html><html><body><h1>Admissions 2023-24</h1><p>Institution: ${colleges[0].name} (999999)</p><p>Percent admitted 8.30%</p></body></html>`,
    "utf8"
  );
  await fs.writeFile(
    path.join(badIpedsReportedNameDir, `${unitIDsByCollegeID[colleges[0].id]}.html`),
    `<!doctype html><html><body><h1>Admissions 2023-24</h1><p>Institution: Different College (${unitIDsByCollegeID[colleges[0].id]})</p><p>Number of applicants 10,000</p><p>Percent admitted 8.30%</p></body></html>`,
    "utf8"
  );
  await fs.writeFile(
    path.join(badIpedsReportedRateDir, `${unitIDsByCollegeID[colleges[0].id]}.html`),
    `<!doctype html><html><body><h1>Admissions 2023-24</h1><p>Institution: ${colleges[0].name} (${unitIDsByCollegeID[colleges[0].id]})</p><p>Admissions considerations only</p></body></html>`,
    "utf8"
  );

  await runNode([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--adm-csv",
    ipedsFixture,
    "--output",
    ipedsReviewCSV
  ]);

  await runNode([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--ipeds-csv",
    ipedsDerivedFixture,
    "--output",
    ipedsDerivedReviewCSV
  ]);

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--ipeds-csv",
    unknownIpedsFixture,
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_unknown_csv.csv")
  ], "IPEDS CSV");

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--ipeds-zip",
    unknownIpedsZip,
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_unknown_zip.csv")
  ], "IPEDS ZIP");

  await runNode([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--reported-html-dir",
    ipedsReportedHTMLDir,
    "--year",
    "2023",
    "--output",
    ipedsReportedReviewCSV
  ]);

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--reported-html-dir",
    badIpedsReportedUnitIDDir,
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_bad_reported_unitid.csv")
  ], `expected UNITID ${unitIDsByCollegeID[colleges[0].id]}`);

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--reported-html-dir",
    badIpedsReportedNameDir,
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_bad_reported_name.csv")
  ], "expected school name");

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--reported-html-dir",
    badIpedsReportedRateDir,
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_bad_reported_rate.csv")
  ], "does not include a usable Percent admitted value");

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--adm-url",
    "https://example.com/ADM2024.csv",
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_nonofficial_url.csv")
  ], "official NCES/IPEDS host");

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--reported-url-template",
    "https://example.com/{unitid}.html",
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_nonofficial.csv")
  ], "official NCES/IPEDS Reported Data HTML endpoint");

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--reported-url-template",
    "https://nces.ed.gov/ipeds/reported-data/html/static?year={year}&surveyNumber=12&viewmode=print",
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_missing_unitid.csv")
  ], "must include {unitid}");

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--reported-url-template",
    "https://nces.ed.gov/ipeds/reported-data/html/{unitid}?year={year}&surveyNumber=9&viewmode=print",
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_wrong_component.csv")
  ], "Admissions component with surveyNumber=12");

  await runNode([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    ipedsReviewCSV
  ]);
  await runNode([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    ipedsDerivedReviewCSV
  ]);
  await runNode([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    ipedsReportedReviewCSV
  ]);

  await expectFailure([
    "scripts/fetch-ipeds-lac-rates.mjs",
    "--adm-url",
    pathToFileURL(ipedsFixture).href,
    "--output",
    path.join(tempDir, "ipeds_liberal_arts_rates_file_url.csv")
  ], "must use https:// for official data downloads");

  const ipedsHeaders = [
    "id",
    "name",
    "rank",
    "ipeds_unitid",
    "ipeds_admission_rate_percent",
    "ipeds_applicants",
    "ipeds_admitted",
    "source_url",
    "source_note"
  ];
  const ipedsReviewRows = parseCsv(await fs.readFile(ipedsReviewCSV, "utf8"));
  const badIpedsUnitIDRows = ipedsReviewRows.map((row) => ({ ...row }));
  badIpedsUnitIDRows[0].ipeds_unitid = "999999";
  await fs.writeFile(
    badIpedsReviewCSV,
    toCsv(ipedsHeaders, badIpedsUnitIDRows),
    "utf8"
  );
  const ipedsReportedReviewRows = parseCsv(await fs.readFile(ipedsReportedReviewCSV, "utf8"));
  const badIpedsReportedSourceURLRows = ipedsReportedReviewRows.map((row) => ({ ...row }));
  badIpedsReportedSourceURLRows[0].source_url = "https://nces.ed.gov/ipeds/reported-data/html/999999?year=2023&surveyNumber=12&viewmode=print";
  await fs.writeFile(
    badIpedsReportedSourceURLCSV,
    toCsv(ipedsHeaders, badIpedsReportedSourceURLRows),
    "utf8"
  );
  const badIpedsReportedSurveyRows = ipedsReportedReviewRows.map((row) => ({ ...row }));
  badIpedsReportedSurveyRows[0].source_url = `https://nces.ed.gov/ipeds/reported-data/html/${unitIDsByCollegeID[colleges[0].id]}?year=2023&surveyNumber=9&viewmode=print`;
  await fs.writeFile(
    badIpedsReportedSurveyCSV,
    toCsv(ipedsHeaders, badIpedsReportedSurveyRows),
    "utf8"
  );

  await expectFailure([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    badIpedsReviewCSV
  ], `expected ${unitIDsByCollegeID[colleges[0].id]}`);

  await expectFailure([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    badIpedsReportedSourceURLCSV
  ], "NCES Reported Data source URL must match UNITID");

  await expectFailure([
    "scripts/apply-scorecard-lac-rates.mjs",
    "--dry-run",
    "--official",
    badIpedsReportedSurveyCSV
  ], "Admissions component with surveyNumber=12");

  console.log(`LAC official import workflow check passed for ${colleges.length} schools via Scorecard institution CSV, Scorecard raw CSV, Scorecard raw ZIP latest-year selection and source-note disclosure, official Scorecard data-page URL discovery, unknown local Scorecard CSV/ZIP filename rejection, IPEDS ADM, IPEDS DRVADM, unknown local IPEDS CSV/ZIP filename rejection, IPEDS Reported Data fixtures, official URL manifest generation, official URL scheme/host checks, reviewed official-name consistency checks, source-URL consistency checks, and seed-level manual edit guards.`);
} finally {
  await fs.rm(tempDir, { recursive: true, force: true });
}
