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
const defaultOutputPath = path.join(dataDir, "ipeds_liberal_arts_rates.csv");
const ipedsDataFilesURL = "https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx?rtid=7";
const ipedsReportedDataURLPrefix = "https://nces.ed.gov/ipeds/reported-data/html/";
const allowedIPEDSSourceHosts = new Set(["nces.ed.gov"]);
const execFileAsync = promisify(execFile);

const unitIDsByCollegeID = JSON.parse(await fs.readFile(path.join(dataDir, "liberal_arts_unitids.json"), "utf8"));

function parseArgs(argv) {
  const args = {
    input: defaultInputPath,
    output: defaultOutputPath,
    ipedsPath: null,
    ipedsUrl: null,
    reportedHtmlDir: null,
    reportedUrlTemplate: null,
    year: "2024",
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
    case "--adm-csv":
    case "--adm-zip":
    case "--ipeds-csv":
    case "--ipeds-zip":
      args.ipedsPath = path.resolve(argv[++index]);
      break;
    case "--adm-url":
    case "--ipeds-url":
      args.ipedsUrl = String(argv[++index] ?? "").trim();
      break;
    case "--reported-html-dir":
      args.reportedHtmlDir = path.resolve(argv[++index]);
      break;
    case "--reported-url-template":
      args.reportedUrlTemplate = String(argv[++index] ?? "").trim();
      break;
    case "--year":
      args.year = String(argv[++index] ?? "").trim();
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
  npm run data:ipeds:lac -- --adm-zip /path/ADM2024.zip
  npm run data:ipeds:lac -- --adm-csv /path/ADM2024.csv
  npm run data:ipeds:lac -- --adm-url https://.../ADM2024.csv-or.zip
  npm run data:ipeds:lac -- --ipeds-csv /path/DRVADM2024.csv
  npm run data:ipeds:lac -- --reported-html-dir /path/nces-reported-admissions-html
  npm run data:ipeds:lac -- --reported-url-template 'https://nces.ed.gov/ipeds/reported-data/html/{unitid}?year=2023&surveyNumber=12&viewmode=print'

Options:
  --input <path>       Reviewed LAC seed CSV. Defaults to data/liberal_arts_colleges.csv.
  --output <path>      Draft output CSV. Defaults to data/ipeds_liberal_arts_rates.csv.
  --adm-zip <path>     Official NCES/IPEDS Admissions and Test Scores ZIP, e.g. ADM2024.zip.
  --adm-csv <path>     Official NCES/IPEDS Admissions and Test Scores CSV, e.g. ADM2024.csv.
  --adm-url <url>      Download an official NCES/IPEDS ADM CSV/ZIP URL and parse it directly.
  --ipeds-zip <path>   Official NCES/IPEDS admissions/selectivity ZIP, e.g. ADM2024.zip or DRVADM2024.zip.
  --ipeds-csv <path>   Official NCES/IPEDS admissions/selectivity CSV, e.g. ADM2024.csv or DRVADM2024.csv.
  --ipeds-url <url>    Download an official NCES/IPEDS admissions/selectivity CSV/ZIP URL and parse it directly.
  --reported-html-dir <path>
                       Directory of official NCES Reported Data Admissions HTML pages, named by UNITID or college id.
  --reported-url-template <url>
                       Official NCES Reported Data Admissions URL template. Must include {unitid}; {year} is optional.
  --year <year>        IPEDS data year label for source notes. Defaults to 2024.
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
    "ipeds_unitid",
    "ipeds_admission_rate_percent",
    "ipeds_applicants",
    "ipeds_admitted",
    "source_url",
    "source_note"
  ];
  return [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => csvEscape(row[header])).join(","))
  ].join("\n") + "\n";
}

async function readCsvFile(filePath) {
  return parseCsv(await fs.readFile(filePath, "utf8"));
}

async function readAdmFile(filePath, sourceLabel = path.basename(filePath)) {
  let rows;
  if (/\.zip$/i.test(filePath)) {
    rows = await readAdmZip(filePath, sourceLabel);
  } else {
    validateIpedsCsvSourceName(filePath, sourceLabel);
    rows = await readCsvFile(filePath);
  }
  return rows.map(normalizeAdmRow);
}

function ipedsSourceFilename(filePath, sourceLabel) {
  try {
    const sourceURL = new URL(sourceLabel);
    return path.basename(sourceURL.pathname);
  } catch {
    return path.basename(filePath);
  }
}

function validateIpedsCsvSourceName(filePath, sourceLabel = path.basename(filePath)) {
  const filename = ipedsSourceFilename(filePath, sourceLabel);
  if (/^(?:ADM|DRVADM)\d{4}.*\.csv$/i.test(filename)) {
    return;
  }
  throw new Error(`IPEDS CSV ${sourceLabel} must be an official ADMYYYY*.csv or DRVADMYYYY*.csv file.`);
}

function validateIpedsZipSourceName(filePath, sourceLabel = path.basename(filePath)) {
  const filename = ipedsSourceFilename(filePath, sourceLabel);
  if (/^(?:ADM|DRVADM)\d{4}.*\.zip$/i.test(filename)) {
    return;
  }
  throw new Error(`IPEDS ZIP ${sourceLabel} must be an official ADMYYYY*.zip or DRVADMYYYY*.zip file.`);
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

async function materializeSourceURL(sourceURL, label) {
  let url;
  try {
    url = new URL(sourceURL);
  } catch {
    throw new Error(`${label} must be a valid URL.`);
  }

  if (url.protocol !== "https:") {
    throw new Error(`${label} must use https:// for official data downloads.`);
  }
  if (!allowedIPEDSSourceHosts.has(url.hostname)) {
    throw new Error(`${label} must point to an official NCES/IPEDS host: ${[...allowedIPEDSSourceHosts].join(", ")}.`);
  }

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "admission-ipeds-"));
  const filePath = path.join(tempDir, `ipeds-adm-source${extensionForDownloadedURL(sourceURL)}`);
  let response;
  try {
    response = await fetch(url);
  } catch (error) {
    throw new Error(`Could not download ${label} from ${sourceURL}: ${fetchFailureDetail(error)}. Use an official local CSV/ZIP via --adm-csv/--adm-zip/--ipeds-csv/--ipeds-zip if the NCES host blocks this network.`);
  }
  if (!response.ok || !response.body) {
    const body = await response.text().catch(() => "");
    throw new Error(`Could not download ${label}: HTTP ${response.status} ${body.slice(0, 240)}`);
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

async function readAdmZip(filePath, sourceLabel = path.basename(filePath)) {
  validateIpedsZipSourceName(filePath, sourceLabel);
  let listing;
  try {
    ({ stdout: listing } = await execFileAsync("unzip", ["-Z1", filePath], { maxBuffer: 10 * 1024 * 1024 }));
  } catch (error) {
    throw new Error(`Could not inspect IPEDS ZIP ${filePath}. Ensure the official ZIP exists and macOS unzip is available. ${error.message}`);
  }

  const names = listing.split(/\r?\n/).filter(Boolean);
  const csvName = names.find((name) => /^ADM\d{4}.*\.csv$/i.test(path.basename(name))) ??
    names.find((name) => /^DRVADM\d{4}.*\.csv$/i.test(path.basename(name)));
  if (!csvName) {
    throw new Error(`IPEDS ZIP ${filePath} does not contain an ADMYYYY or DRVADMYYYY CSV file.`);
  }

  let csvText;
  try {
    ({ stdout: csvText } = await execFileAsync("unzip", ["-p", filePath, csvName], { maxBuffer: 512 * 1024 * 1024 }));
  } catch (error) {
    throw new Error(`Could not read ${csvName} from IPEDS ZIP ${filePath}. ${error.message}`);
  }
  return parseCsv(csvText);
}

function normalizeAdmRow(row) {
  return Object.entries(row).reduce((acc, [key, value]) => {
    acc[key.trim().toUpperCase()] = value;
    return acc;
  }, {});
}

function parseNumber(value) {
  const text = String(value ?? "").trim();
  if (!text || text === "." || text.toLowerCase() === "privacysuppressed") {
    return null;
  }
  const parsed = Number(text);
  if (Number.isFinite(parsed) && parsed < 0) {
    return null;
  }
  return Number.isFinite(parsed) ? parsed : null;
}

function validateAdmColumns(row) {
  if (!("UNITID" in row)) {
    throw new Error("IPEDS admissions/selectivity file must include a UNITID column.");
  }
  if (!("APPLCN" in row) && !("ADMSSN" in row) && !("ADM_RATE" in row) && !("ADMRATE" in row) && !("DVADM01" in row) && !("DVADM01_P" in row)) {
    throw new Error("IPEDS admissions/selectivity file must include APPLCN/ADMSSN or a recognized derived admission-rate column.");
  }
}

function computedRate(row, college) {
  const applicants = parseNumber(row.APPLCN);
  const admitted = parseNumber(row.ADMSSN);
  if (applicants !== null && admitted !== null && applicants > 0 && admitted >= 0 && admitted <= applicants) {
    return { rate: admitted / applicants * 100, applicants, admitted, method: "ADMSSN/APPLCN" };
  }

  for (const field of ["ADM_RATE", "ADMRATE", "DVADM01", "DVADM01_P"]) {
    const rawRate = parseNumber(row[field]);
    if (rawRate !== null && rawRate > 0) {
      return {
        rate: rawRate <= 1 ? rawRate * 100 : rawRate,
        applicants: applicants ?? "",
        admitted: admitted ?? "",
        method: field
      };
    }
  }

  throw new Error(`IPEDS row for ${college.name} has no usable APPLCN/ADMSSN or derived admission-rate field.`);
}

function decodeHtmlEntities(value) {
  return String(value ?? "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/gi, "\"");
}

function htmlToText(html) {
  return decodeHtmlEntities(html)
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeName(value) {
  return String(value ?? "")
    .toLowerCase()
    .replaceAll("&", "and")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function parseAdmissionsReportedHTML(html, college, sourceURL) {
  const unitID = unitIDsByCollegeID[college.id];
  const text = htmlToText(html);
  const normalizedText = normalizeName(text);
  const normalizedCollegeName = normalizeName(college.name);
  if (!text.includes(unitID)) {
    throw new Error(`NCES Reported Data page for ${college.name} does not include expected UNITID ${unitID}.`);
  }
  if (!normalizedText.includes(normalizedCollegeName)) {
    throw new Error(`NCES Reported Data page for ${college.name} does not include the expected school name.`);
  }
  if (!/Admissions/i.test(text)) {
    throw new Error(`NCES Reported Data page for ${college.name} does not appear to be the Admissions component.`);
  }

  const applicantsMatch = text.match(/Number of applicants\s+([\d,]+)/i);
  const rateMatch = text.match(/Percent admitted\s+(\d+(?:\.\d+)?)\s*%/i);
  if (!rateMatch) {
    throw new Error(`NCES Reported Data page for ${college.name} does not include a usable Percent admitted value.`);
  }

  const rate = Number(rateMatch[1]);
  if (!Number.isFinite(rate) || rate <= 0 || rate > 100) {
    throw new Error(`NCES Reported Data admission rate for ${college.name} is out of range: ${rateMatch[1]}`);
  }

  const applicants = applicantsMatch ? Number(applicantsMatch[1].replaceAll(",", "")) : "";
  if (applicants !== "" && (!Number.isFinite(applicants) || applicants <= 0)) {
    throw new Error(`NCES Reported Data applicants value for ${college.name} is invalid: ${applicantsMatch[1]}`);
  }

  return {
    rate,
    applicants,
    admitted: "",
    method: "NCES Reported Data Admissions Percent admitted",
    sourceURL
  };
}

function reportedDataURL(unitID, year, template) {
  const source = template || `${ipedsReportedDataURLPrefix}${unitID}?year={year}&surveyNumber=12&viewmode=print`;
  if (!source.includes("{unitid}") && template) {
    throw new Error("--reported-url-template must include {unitid}.");
  }
  if (template && !source.startsWith(`${ipedsReportedDataURLPrefix}{unitid}`)) {
    throw new Error("--reported-url-template must point to the official NCES/IPEDS Reported Data HTML endpoint.");
  }
  if (template) {
    let parsed;
    try {
      parsed = new URL(source.replaceAll("{unitid}", unitID).replaceAll("{year}", year));
    } catch {
      throw new Error("--reported-url-template must be a valid URL template.");
    }
    if (parsed.searchParams.get("surveyNumber") !== "12") {
      throw new Error("--reported-url-template must point to the NCES/IPEDS Admissions component with surveyNumber=12.");
    }
  }
  return source
    .replaceAll("{unitid}", unitID)
    .replaceAll("{year}", year);
}

async function readReportedHTMLFromDir(dirPath, college) {
  const unitID = unitIDsByCollegeID[college.id];
  const candidates = [
    `${unitID}.html`,
    `${unitID}.htm`,
    `${college.id}.html`,
    `${college.id}.htm`
  ];
  for (const filename of candidates) {
    const filePath = path.join(dirPath, filename);
    try {
      return await fs.readFile(filePath, "utf8");
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw error;
      }
    }
  }
  throw new Error(`No NCES Reported Data HTML file found for ${college.name}; expected one of ${candidates.join(", ")}.`);
}

async function readReportedHTMLFromTemplate(template, college, year) {
  const unitID = unitIDsByCollegeID[college.id];
  const url = reportedDataURL(unitID, year, template);
  let response;
  try {
    response = await fetch(url);
  } catch (error) {
    throw new Error(`Could not download NCES Reported Data page for ${college.name} from ${url}: ${fetchFailureDetail(error)}. If NCES blocks direct HTTPS from this network, save the official pages locally and rerun with --reported-html-dir, or use an official ADM/DRVADM CSV/ZIP.`);
  }
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`Could not download NCES Reported Data page for ${college.name} from ${url}: HTTP ${response.status} ${body.slice(0, 240)}`);
  }
  return response.text();
}

async function draftReportedRows(colleges, args) {
  return Promise.all(colleges.map(async (college) => {
    const unitID = unitIDsByCollegeID[college.id];
    if (!unitID) {
      throw new Error(`No reviewed IPEDS UNITID mapping for ${college.id}.`);
    }
    const sourceURL = reportedDataURL(unitID, args.year, args.reportedUrlTemplate);
    const html = args.reportedHtmlDir
      ? await readReportedHTMLFromDir(args.reportedHtmlDir, college)
      : await readReportedHTMLFromTemplate(args.reportedUrlTemplate, college, args.year);
    const result = parseAdmissionsReportedHTML(html, college, sourceURL);
    return {
      id: college.id,
      name: college.name,
      rank: college.rank,
      ipeds_unitid: unitID,
      ipeds_admission_rate_percent: result.rate.toFixed(2),
      ipeds_applicants: result.applicants,
      ipeds_admitted: result.admitted,
      source_url: result.sourceURL,
      source_note: `NCES/IPEDS Reported Data Admissions ${args.year}; rate read from official Admissions component Percent admitted for UNITID ${unitID}.`
    };
  }));
}

function sourceComponentLabel(sourcePath, year) {
  const basename = path.basename(sourcePath ?? "").toUpperCase();
  if (basename.includes("DRVADM")) {
    return `DRVADM${year} Selectivity and admissions yield`;
  }
  if (basename.includes("ADM")) {
    return `ADM${year} Admissions and Test Scores`;
  }
  return `IPEDS ${year} admissions/selectivity data`;
}

function draftRow(college, admRows, year, sourcePath) {
  const unitID = unitIDsByCollegeID[college.id];
  if (!unitID) {
    throw new Error(`No reviewed IPEDS UNITID mapping for ${college.id}.`);
  }

  const row = admRows.find((item) => String(item.UNITID ?? "").trim() === unitID);
  if (!row) {
    throw new Error(`No IPEDS ADM row for ${college.name} / UNITID ${unitID}.`);
  }

  const result = computedRate(row, college);
  if (result.rate <= 0 || result.rate > 100) {
    throw new Error(`Computed IPEDS admission rate for ${college.name} is out of range: ${result.rate}`);
  }

  return {
    id: college.id,
    name: college.name,
    rank: college.rank,
    ipeds_unitid: unitID,
    ipeds_admission_rate_percent: result.rate.toFixed(2),
    ipeds_applicants: result.applicants,
    ipeds_admitted: result.admitted,
    source_url: ipedsDataFilesURL,
    source_note: `NCES/IPEDS ${sourceComponentLabel(sourcePath, year)}; rate computed from ${result.method} for UNITID ${unitID}.`
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }
  const sourceCount = [args.ipedsPath, args.ipedsUrl, args.reportedHtmlDir, args.reportedUrlTemplate].filter(Boolean).length;
  if (sourceCount === 0) {
    throw new Error("Missing official IPEDS admissions/selectivity source. Pass --adm-zip /path/ADM2024.zip, --adm-csv /path/ADM2024.csv, --ipeds-csv /path/DRVADM2024.csv, --ipeds-url https://.../ADM2024-or-DRVADM2024.csv-or.zip, --reported-html-dir /path/html, or --reported-url-template 'https://nces.ed.gov/ipeds/reported-data/html/{unitid}?year={year}&surveyNumber=12&viewmode=print'.");
  }
  if (sourceCount > 1) {
    throw new Error("Use only one IPEDS admissions/selectivity source.");
  }

  const tempDirs = [];
  try {
    const colleges = await readCsvFile(args.input);
    if (args.reportedHtmlDir || args.reportedUrlTemplate) {
      const rows = await draftReportedRows(colleges, args);
      await fs.writeFile(args.output, toCsv(rows), "utf8");
      console.log(`Wrote ${rows.length} IPEDS Reported Data LAC rate rows to ${path.relative(root, args.output)}.`);
      return;
    }

    let ipedsPath = args.ipedsPath;
    const sourceDescriptor = args.ipedsUrl || args.ipedsPath;
    if (args.ipedsUrl) {
      const downloaded = await materializeSourceURL(args.ipedsUrl, "--ipeds-url");
      ipedsPath = downloaded.filePath;
      if (downloaded.tempDir) {
        tempDirs.push(downloaded.tempDir);
      }
    }

    const admRows = await readAdmFile(ipedsPath, sourceDescriptor);
    if (admRows.length === 0) {
      throw new Error("IPEDS admissions/selectivity file contains no data rows.");
    }
    validateAdmColumns(admRows[0]);
    const rows = colleges.map((college) => draftRow(college, admRows, args.year, sourceDescriptor));

    await fs.writeFile(args.output, toCsv(rows), "utf8");
    console.log(`Wrote ${rows.length} IPEDS LAC rate rows to ${path.relative(root, args.output)}.`);
  } finally {
    await Promise.all(tempDirs.map((tempDir) => fs.rm(tempDir, { recursive: true, force: true })));
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
