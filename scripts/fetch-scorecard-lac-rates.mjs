import fs from "node:fs/promises";
import { createWriteStream } from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

const root = process.cwd();
const dataDir = path.join(root, "data");
const defaultInputPath = path.join(dataDir, "liberal_arts_colleges.csv");
const defaultOutputPath = path.join(dataDir, "scorecard_liberal_arts_rates.csv");
const scorecardBaseURL = "https://api.data.gov/ed/collegescorecard/v1/schools";
const scorecardDataPageURL = "https://collegescorecard.ed.gov/data/";
const allowedScorecardDownloadHosts = new Set([
  "collegescorecard.ed.gov",
  "data.ed.gov",
  "ed-public-download.app.cloud.gov",
  "ed-public-download.scorecard.network"
]);
const allowedScorecardDownloadPath = /(?:Most-Recent-Cohorts-Institution|College_?Scorecard_Raw_Data).*\.(?:csv|zip)$/i;
const requestedFields = [
  "id",
  "school.name",
  "latest.admissions.admission_rate.overall",
  "latest.student.size"
];
const apiBatchSize = 100;
const execFileAsync = promisify(execFile);

const unitIDsByCollegeID = JSON.parse(await fs.readFile(path.join(dataDir, "liberal_arts_unitids.json"), "utf8"));

function parseArgs(argv) {
  const args = {
    input: defaultInputPath,
    output: defaultOutputPath,
    scorecardPath: null,
    scorecardUrl: null,
    scorecardLatestUrl: false,
    scorecardPageHtml: null,
    scorecardDiscoveryUrl: scorecardDataPageURL,
    checkScorecardUrl: false,
    checkScorecardLatestUrl: false,
    apiKey: process.env.COLLEGE_SCORECARD_API_KEY || process.env.DATA_GOV_API_KEY || "",
    help: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    switch (item) {
    case "--input":
      args.input = path.resolve(argv[++index]);
      break;
    case "--output":
      args.output = path.resolve(argv[++index]);
      break;
    case "--scorecard-csv":
      args.scorecardPath = path.resolve(argv[++index]);
      break;
    case "--scorecard-zip":
      args.scorecardPath = path.resolve(argv[++index]);
      break;
    case "--scorecard-url":
      args.scorecardUrl = String(argv[++index] ?? "").trim();
      break;
    case "--scorecard-latest-url":
      args.scorecardLatestUrl = true;
      break;
    case "--scorecard-page-html":
      args.scorecardPageHtml = path.resolve(argv[++index]);
      break;
    case "--scorecard-discovery-url":
      args.scorecardDiscoveryUrl = String(argv[++index] ?? "").trim();
      break;
    case "--check-scorecard-url":
      args.scorecardUrl = String(argv[++index] ?? "").trim();
      args.checkScorecardUrl = true;
      break;
    case "--check-scorecard-latest-url":
      args.checkScorecardLatestUrl = true;
      break;
    case "--api-key":
      args.apiKey = argv[++index] ?? "";
      break;
    case "--help":
    case "-h":
      args.help = true;
      break;
    default:
      throw new Error(`Unknown argument: ${item}`);
    }
  }

  return args;
}

function usage() {
  return `Usage:
  npm run data:scorecard:lac -- --api-key <DATA_GOV_KEY>
  npm run data:scorecard:lac -- --scorecard-csv /path/Most-Recent-Cohorts-Institution.csv
  npm run data:scorecard:lac -- --scorecard-zip /path/Most-Recent-Cohorts-Institution.zip
  npm run data:scorecard:lac -- --scorecard-url https://.../Most-Recent-Cohorts-Institution.csv-or.zip
  npm run data:scorecard:lac -- --scorecard-latest-url
  npm run data:scorecard:lac -- --scorecard-page-html /path/official-scorecard-data-page.html --scorecard-latest-url
  npm run data:scorecard:lac -- --check-scorecard-url https://.../Most-Recent-Cohorts-Institution.csv-or.zip
  npm run data:scorecard:lac -- --check-scorecard-latest-url

Options:
  --input <path>           Reviewed LAC seed CSV. Defaults to data/liberal_arts_colleges.csv.
  --output <path>          Draft output CSV. Defaults to data/scorecard_liberal_arts_rates.csv.
  --api-key <key>          College Scorecard/data.gov API key. Env COLLEGE_SCORECARD_API_KEY or DATA_GOV_API_KEY also works.
  --scorecard-csv <path>   Use official downloaded Scorecard institution CSV instead of the API.
  --scorecard-zip <path>   Use official downloaded Scorecard institution ZIP without manually unzipping it.
  --scorecard-url <url>    Download an official Scorecard institution CSV/ZIP URL and parse it directly.
  --scorecard-latest-url   Discover the current institution ZIP from the official College Scorecard data page and parse it.
  --scorecard-page-html    Use a saved official College Scorecard data-page HTML file for URL discovery when live page access is blocked.
  --scorecard-discovery-url <url>
                           Official College Scorecard data page used by --scorecard-latest-url. Defaults to ${scorecardDataPageURL}.
  --check-scorecard-url    Validate an official Scorecard download URL without downloading it.
  --check-scorecard-latest-url
                           Discover and validate the official current Scorecard institution download URL without downloading it.
`;
}

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

function toCsv(rows) {
  const headers = [
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
  return [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => csvEscape(row[header])).join(","))
  ].join("\n") + "\n";
}

function normalizeName(value) {
  return String(value ?? "")
    .toLowerCase()
    .replaceAll("&", "and")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function parseRate(raw) {
  const text = String(raw ?? "").trim();
  if (!text || text === "NULL" || text === "PrivacySuppressed") {
    return null;
  }
  const value = Number(text);
  if (!Number.isFinite(value) || value <= 0 || value > 1) {
    return null;
  }
  return value;
}

async function readCsvFile(filePath) {
  return parseCsv(await fs.readFile(filePath, "utf8"));
}

async function readScorecardFile(filePath, sourceLabel = path.basename(filePath)) {
  if (/\.zip$/i.test(filePath)) {
    return readScorecardZip(filePath, sourceLabel);
  }
  validateScorecardCsvSourceName(filePath, sourceLabel);
  return {
    rows: await readCsvFile(filePath),
    sourceDescription: sourceLabel
  };
}

function validateScorecardCsvSourceName(filePath, sourceLabel = path.basename(filePath)) {
  const filename = scorecardCsvSourceFilename(filePath, sourceLabel);
  if (/Most-Recent-Cohorts-Institution.*\.csv$/i.test(filename) ||
    /^MERGED\d{4}_\d{2}_PP.*\.csv$/i.test(filename)) {
    return;
  }
  throw new Error(`Scorecard CSV ${sourceLabel} must be an official Most-Recent-Cohorts-Institution*.csv or raw MERGEDYYYY_YY_PP*.csv file.`);
}

function scorecardCsvSourceFilename(filePath, sourceLabel) {
  try {
    const sourceURL = new URL(sourceLabel);
    return path.basename(sourceURL.pathname);
  } catch {
    return path.basename(filePath);
  }
}

function extensionForDownloadedURL(sourceURL, fallback = ".csv") {
  const pathname = new URL(sourceURL).pathname;
  if (/\.zip$/i.test(pathname)) {
    return ".zip";
  }
  if (/\.csv$/i.test(pathname)) {
    return ".csv";
  }
  return fallback;
}

function validateScorecardSourceURL(sourceURL, label) {
  let url;
  try {
    url = new URL(sourceURL);
  } catch {
    throw new Error(`${label} must be a valid URL.`);
  }

  if (url.protocol !== "https:") {
    throw new Error(`${label} must use https:// for official data downloads.`);
  }
  if (!allowedScorecardDownloadHosts.has(url.hostname)) {
    throw new Error(`${label} must point to an official College Scorecard download host: ${[...allowedScorecardDownloadHosts].join(", ")}.`);
  }
  if (!allowedScorecardDownloadPath.test(url.pathname)) {
    throw new Error(`${label} must point to a Scorecard institution CSV/ZIP or raw data ZIP, not an unrelated official-host file.`);
  }
  return url;
}

function validateScorecardDiscoveryURL(sourceURL, label) {
  let url;
  try {
    url = new URL(sourceURL);
  } catch {
    throw new Error(`${label} must be a valid URL.`);
  }

  if (url.protocol !== "https:") {
    throw new Error(`${label} must use https:// for the official College Scorecard data page.`);
  }
  if (url.hostname !== "collegescorecard.ed.gov" || !url.pathname.startsWith("/data")) {
    throw new Error(`${label} must point to the official College Scorecard data page on collegescorecard.ed.gov/data/.`);
  }
  return url;
}

function decodeHTMLText(value) {
  return String(value ?? "")
    .replace(/\\\//g, "/")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function scorecardDownloadCandidateSortValue(sourceURL) {
  const filename = path.basename(new URL(sourceURL).pathname);
  const dateMatch = filename.match(/_(\d{2})(\d{2})(\d{4})\.(?:csv|zip)$/i);
  if (dateMatch) {
    return Number(`${dateMatch[3]}${dateMatch[1]}${dateMatch[2]}`);
  }
  const rawDateMatch = filename.match(/_(\d{8})\.(?:csv|zip)$/i);
  if (rawDateMatch) {
    return Number(rawDateMatch[1]);
  }
  return 0;
}

function discoverScorecardInstitutionURLFromHTML(html, pageURL = scorecardDataPageURL) {
  const decoded = decodeHTMLText(html);
  const normalized = decoded.replaceAll("\\u002F", "/");
  const rawCandidates = new Set();
  const urlPattern = /https:\/\/[^\s"'<>]+(?:Most-Recent-Cohorts-Institution|College_?Scorecard_Raw_Data)[^\s"'<>]*\.(?:csv|zip)/gi;
  for (const match of normalized.matchAll(urlPattern)) {
    rawCandidates.add(match[0]);
  }

  const hrefPattern = /(?:href|url)\s*[:=]\s*["']([^"']*(?:Most-Recent-Cohorts-Institution|College_?Scorecard_Raw_Data)[^"']*\.(?:csv|zip))["']/gi;
  for (const match of normalized.matchAll(hrefPattern)) {
    rawCandidates.add(new URL(match[1], pageURL).href);
  }

  const candidates = [...rawCandidates]
    .map((candidate) => {
      try {
        return validateScorecardSourceURL(candidate, "discovered Scorecard URL").href;
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((lhs, rhs) => {
      const lhsInstitution = /Most-Recent-Cohorts-Institution/i.test(new URL(lhs).pathname) ? 1 : 0;
      const rhsInstitution = /Most-Recent-Cohorts-Institution/i.test(new URL(rhs).pathname) ? 1 : 0;
      if (lhsInstitution !== rhsInstitution) {
        return rhsInstitution - lhsInstitution;
      }
      return scorecardDownloadCandidateSortValue(rhs) - scorecardDownloadCandidateSortValue(lhs) ||
        lhs.localeCompare(rhs);
    });

  const selected = candidates.find((candidate) => /Most-Recent-Cohorts-Institution/i.test(new URL(candidate).pathname));
  if (!selected) {
    throw new Error("Could not discover an official Scorecard institution CSV/ZIP URL from the College Scorecard data page HTML.");
  }
  return selected;
}

async function readScorecardDiscoveryHTML(args) {
  if (args.scorecardPageHtml) {
    return fs.readFile(args.scorecardPageHtml, "utf8");
  }

  const url = validateScorecardDiscoveryURL(args.scorecardDiscoveryUrl, "--scorecard-discovery-url");
  let response;
  try {
    response = await fetch(url, {
      headers: {
        "User-Agent": "AdmissionCalculatorDataReview/1.0 (+https://github.com/qyf9794/Admission-Calculator)"
      }
    });
  } catch (error) {
    throw new Error(`Could not load official College Scorecard data page ${url.href}: ${fetchFailureDetail(error)}. If the page blocks this network, save the official page HTML and pass --scorecard-page-html.`);
  }
  const body = await response.text().catch(() => "");
  if (!response.ok) {
    throw new Error(`Could not load official College Scorecard data page ${url.href}: HTTP ${response.status} ${body.slice(0, 240)}. If the page blocks this network, save the official page HTML and pass --scorecard-page-html.`);
  }
  return body;
}

async function discoverScorecardLatestURL(args) {
  const html = await readScorecardDiscoveryHTML(args);
  return discoverScorecardInstitutionURLFromHTML(html, args.scorecardDiscoveryUrl);
}

async function materializeSourceURL(sourceURL, label) {
  const url = validateScorecardSourceURL(sourceURL, label);

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "admission-scorecard-"));
  const filePath = path.join(tempDir, `scorecard-source${extensionForDownloadedURL(sourceURL)}`);
  let response;
  try {
    response = await fetch(url);
  } catch (error) {
    throw new Error(`Could not download ${label} from ${sourceURL}: ${fetchFailureDetail(error)}. Use an official local Scorecard CSV/ZIP via --scorecard-csv/--scorecard-zip if the download host blocks this network.`);
  }
  if (!response.ok || !response.body) {
    const body = await response.text().catch(() => "");
    throw new Error(`Could not download ${label} from ${sourceURL}: HTTP ${response.status} ${body.slice(0, 240)}`);
  }

  await pipeline(Readable.fromWeb(response.body), createWriteStream(filePath));
  return { filePath, tempDir };
}

function fetchFailureDetail(error) {
  const cause = error?.cause;
  const causeParts = [
    cause?.code,
    cause?.errno,
    cause?.syscall,
    cause?.hostname
  ].filter(Boolean);
  const causeText = causeParts.length > 0 ? ` (${causeParts.join(", ")})` : "";
  return `${error?.message ?? "fetch failed"}${causeText}`;
}

async function readScorecardZip(filePath, sourceLabel = path.basename(filePath)) {
  let listing;
  try {
    ({ stdout: listing } = await execFileAsync("unzip", ["-Z1", filePath], { maxBuffer: 10 * 1024 * 1024 }));
  } catch (error) {
    throw new Error(`Could not inspect Scorecard ZIP ${filePath}. Ensure the official ZIP exists and macOS unzip is available. ${error.message}`);
  }

  const names = listing.split(/\r?\n/).filter(Boolean);
  const csvName = selectScorecardCsvName(names);
  if (!csvName) {
    throw new Error(`Scorecard ZIP ${filePath} does not contain a Scorecard institution CSV or raw MERGEDYYYY_YY_PP CSV file.`);
  }

  let csvText;
  try {
    ({ stdout: csvText } = await execFileAsync("unzip", ["-p", filePath, csvName], { maxBuffer: 512 * 1024 * 1024 }));
  } catch (error) {
    throw new Error(`Could not read ${csvName} from Scorecard ZIP ${filePath}. ${error.message}`);
  }
  return {
    rows: parseCsv(csvText),
    sourceDescription: `${sourceLabel} / ${csvName}`
  };
}

function selectScorecardCsvName(names) {
  const institutionFile = names.find((name) => /Most-Recent-Cohorts-Institution.*\.csv$/i.test(path.basename(name)));
  if (institutionFile) {
    return institutionFile;
  }

  const mergedFiles = names
    .map((name) => {
      const match = path.basename(name).match(/^MERGED(\d{4})_\d{2}_PP.*\.csv$/i);
      return match ? { name, year: Number(match[1]) } : null;
    })
    .filter(Boolean)
    .sort((lhs, rhs) => rhs.year - lhs.year || lhs.name.localeCompare(rhs.name));
  if (mergedFiles.length > 0) {
    return mergedFiles[0].name;
  }

  return null;
}

function chunked(items, size) {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

async function fetchFromApi(colleges, apiKey) {
  const rows = [];
  for (const batch of chunked(colleges, apiBatchSize)) {
    rows.push(...await fetchBatchFromApi(batch, apiKey));
    await new Promise((resolve) => setTimeout(resolve, 120));
  }
  return rows;
}

async function fetchBatchFromApi(colleges, apiKey) {
  const missingUnitIDs = colleges.filter((college) => !unitIDsByCollegeID[college.id]);
  if (missingUnitIDs.length > 0) {
    throw new Error(`Missing reviewed UNITID mapping for: ${missingUnitIDs.map((college) => college.id).join(", ")}`);
  }

  const unitIDs = colleges.map((college) => unitIDsByCollegeID[college.id]);
  const url = new URL(scorecardBaseURL);
  url.searchParams.set("api_key", apiKey);
  url.searchParams.set("id", unitIDs.join(","));
  url.searchParams.set("fields", requestedFields.join(","));
  url.searchParams.set("per_page", String(Math.max(20, unitIDs.length)));

  const response = await fetch(url);
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`College Scorecard API failed for ${colleges.length} UNITIDs: HTTP ${response.status} ${body.slice(0, 240)}`);
  }

  const payload = JSON.parse(body);
  const resultsByUnitID = new Map((payload.results ?? []).map((item) => [String(item.id), item]));

  return colleges.map((college) => {
    const unitID = unitIDsByCollegeID[college.id];
    const matched = resultsByUnitID.get(unitID);
    if (!matched) {
      throw new Error(`No Scorecard API result for ${college.name} / UNITID ${unitID}.`);
    }

    const rate = parseRate(matched["latest.admissions.admission_rate.overall"]);
    if (rate === null) {
      throw new Error(`Scorecard result for ${college.name} / UNITID ${unitID} has no usable admission rate.`);
    }

    return draftRow(college, {
      unitid: matched.id,
      name: matched["school.name"],
      rate,
      studentSize: matched["latest.student.size"]
    });
  });
}

function findInScorecardCsv(college, scorecardRows, sourceDescription) {
  const unitID = unitIDsByCollegeID[college.id];
  const wanted = normalizeName(college.name);
  const exactID = unitID ? scorecardRows.find((row) => String(row.UNITID).trim() === unitID) : null;
  if (unitID && !exactID) {
    throw new Error(`No Scorecard CSV row for ${college.name} / UNITID ${unitID}.`);
  }
  const exact = exactID ?? scorecardRows.find((row) => normalizeName(row.INSTNM) === wanted);
  const loose = exact ?? scorecardRows.find((row) => normalizeName(row.INSTNM).includes(wanted) || wanted.includes(normalizeName(row.INSTNM)));
  if (!loose) {
    throw new Error(`No Scorecard CSV row for ${college.name}.`);
  }

  const rate = parseRate(loose.ADM_RATE);
  if (rate === null) {
    throw new Error(`Scorecard CSV row for ${college.name} has no usable ADM_RATE.`);
  }

  return draftRow(college, {
    unitid: loose.UNITID,
    name: loose.INSTNM,
    rate,
    studentSize: loose.UGDS,
    sourceDescription
  });
}

function draftRow(college, scorecard) {
  const sourceURL = `https://collegescorecard.ed.gov/school/?${scorecard.unitid}`;
  return {
    id: college.id,
    name: college.name,
    rank: college.rank,
    scorecard_unitid: scorecard.unitid,
    scorecard_name: scorecard.name,
    scorecard_latest_admission_rate_percent: (scorecard.rate * 100).toFixed(2),
    scorecard_student_size: scorecard.studentSize ?? "",
    source_url: sourceURL,
    source_note: `College Scorecard latest.admissions.admission_rate.overall / ADM_RATE${scorecard.sourceDescription ? ` from ${scorecard.sourceDescription}` : ""}; review before replacing LAC base rates.`
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }
  if (args.checkScorecardUrl) {
    if (!args.scorecardUrl) {
      throw new Error("Missing URL for --check-scorecard-url.");
    }
    validateScorecardSourceURL(args.scorecardUrl, "--check-scorecard-url");
    console.log(`Official Scorecard URL host accepted: ${new URL(args.scorecardUrl).hostname}`);
    return;
  }
  if (args.checkScorecardLatestUrl) {
    const discoveredURL = await discoverScorecardLatestURL(args);
    console.log(`Official Scorecard latest institution URL discovered: ${discoveredURL}`);
    return;
  }

  const tempDirs = [];
  try {
    const colleges = await readCsvFile(args.input);
    let rows;
    if (args.scorecardPath || args.scorecardUrl || args.scorecardLatestUrl) {
      const sourceCount = [args.scorecardPath, args.scorecardUrl, args.scorecardLatestUrl].filter(Boolean).length;
      if (sourceCount > 1) {
        throw new Error("Use only one Scorecard source: --scorecard-csv/--scorecard-zip, --scorecard-url, or --scorecard-latest-url.");
      }
      let scorecardPath = args.scorecardPath;
      let scorecardUrl = args.scorecardUrl;
      if (args.scorecardLatestUrl) {
        scorecardUrl = await discoverScorecardLatestURL(args);
        console.log(`Discovered official Scorecard latest institution URL: ${scorecardUrl}`);
      }
      if (scorecardUrl) {
        const downloaded = await materializeSourceURL(scorecardUrl, args.scorecardLatestUrl ? "--scorecard-latest-url" : "--scorecard-url");
        scorecardPath = downloaded.filePath;
        if (downloaded.tempDir) {
          tempDirs.push(downloaded.tempDir);
        }
      }
      const sourceLabel = scorecardUrl || path.basename(scorecardPath);
      const scorecardSource = await readScorecardFile(scorecardPath, sourceLabel);
      rows = colleges.map((college) => findInScorecardCsv(college, scorecardSource.rows, scorecardSource.sourceDescription));
    } else {
      if (!args.apiKey) {
        throw new Error("Missing College Scorecard API key. Set COLLEGE_SCORECARD_API_KEY or pass --api-key. Use --scorecard-csv, --scorecard-zip, or --scorecard-url for downloaded official data.");
      }
      rows = await fetchFromApi(colleges, args.apiKey);
    }

    await fs.writeFile(args.output, toCsv(rows), "utf8");
    console.log(`Wrote ${rows.length} College Scorecard LAC rate rows to ${path.relative(root, args.output)}.`);
  } finally {
    await Promise.all(tempDirs.map((tempDir) => fs.rm(tempDir, { recursive: true, force: true })));
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
