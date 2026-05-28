import fs from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const dataDir = path.join(root, "data");
const defaultInputPath = path.join(dataDir, "liberal_arts_colleges.csv");
const defaultScorecardPath = path.join(dataDir, "scorecard_liberal_arts_rates.csv");
const defaultOutputPath = defaultInputPath;
const scorecardSchoolURLPrefix = "https://collegescorecard.ed.gov/school/?";
const ipedsDataFilesURLPrefix = "https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx";
const ipedsReportedDataURLPrefix = "https://nces.ed.gov/ipeds/reported-data/html/";

const unitIDsByCollegeID = JSON.parse(await fs.readFile(path.join(dataDir, "liberal_arts_unitids.json"), "utf8"));

function parseArgs(argv) {
  const args = {
    input: defaultInputPath,
    scorecard: defaultScorecardPath,
    output: defaultOutputPath,
    latestRateSlot: "rate_2029",
    dryRun: false,
    help: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    switch (item) {
    case "--input":
      args.input = path.resolve(argv[++index]);
      break;
    case "--scorecard":
      args.scorecard = path.resolve(argv[++index]);
      break;
    case "--official":
      args.scorecard = path.resolve(argv[++index]);
      break;
    case "--output":
      args.output = path.resolve(argv[++index]);
      break;
    case "--latest-rate-slot":
      args.latestRateSlot = argv[++index] ?? "";
      break;
    case "--dry-run":
      args.dryRun = true;
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
  npm run data:official:lac:apply -- --dry-run --official <review_csv>
  npm run data:official:lac:apply -- --official <review_csv>

Options:
  --input <path>             Existing LAC seed CSV. Defaults to data/liberal_arts_colleges.csv.
  --scorecard <path>         Reviewed Scorecard CSV from data:scorecard:lac.
  --official <path>          Reviewed official CSV from data:scorecard:lac or data:ipeds:lac.
  --output <path>            Output CSV. Defaults to overwriting data/liberal_arts_colleges.csv.
  --latest-rate-slot <name>  Slot to store the reviewed official rate. Defaults to rate_2029.
  --dry-run                  Validate and print planned changes without writing.
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
    return { headers: [], rows: [] };
  }

  return {
    headers,
    rows: body.map((cells, rowIndex) => {
      if (cells.length !== headers.length) {
        throw new Error(`CSV row ${rowIndex + 2} has ${cells.length} cells; expected ${headers.length}.`);
      }
      return headers.reduce((acc, header, index) => {
        acc[header] = cells[index] ?? "";
        return acc;
      }, {});
    })
  };
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

async function readCsvFile(filePath) {
  return parseCsv(await fs.readFile(filePath, "utf8"));
}

function normalizeName(value) {
  return String(value ?? "")
    .toLowerCase()
    .replaceAll("&", "and")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function parseRatePercent(row) {
  const raw = String(row.scorecard_latest_admission_rate_percent ?? row.ipeds_admission_rate_percent ?? "").trim();
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0 || value > 100) {
    throw new Error(`Invalid official admission rate for ${row.id}: ${raw}`);
  }
  return value.toFixed(2);
}

function officialSource(row) {
  if (row.scorecard_latest_admission_rate_percent) {
    const reviewSourceNote = String(row.source_note ?? "")
      .replace(/;?\s*review before replacing LAC base rates\.?/gi, "")
      .trim();
    const scorecardScope = reviewSourceNote || "College Scorecard latest admissions.admission_rate.overall / ADM_RATE";
    return {
      label: "College Scorecard",
      unitID: row.scorecard_unitid,
      reviewedName: row.scorecard_name,
      sourceURL: row.source_url,
      sourceNote: `${scorecardScope}; official base rate applied via UNITID ${row.scorecard_unitid}; reviewed against ${row.scorecard_name}. Original IMG_0742.JPG table retained for LAC list/rank scope.`
    };
  }

  if (row.ipeds_admission_rate_percent) {
    return {
      label: "NCES/IPEDS",
      unitID: row.ipeds_unitid,
      reviewedName: row.name,
      sourceURL: row.source_url,
      sourceNote: `NCES/IPEDS admissions rate via UNITID ${row.ipeds_unitid}; ${row.source_note}. Original IMG_0742.JPG table retained for LAC list/rank scope.`
    };
  }

  throw new Error(`Official review row for ${row.id} does not include a supported admission-rate column.`);
}

function validateOfficialSourceURL(source, expectedUnitID, rowID) {
  const sourceURL = String(source.sourceURL ?? "").trim();
  let parsed;
  try {
    parsed = new URL(sourceURL);
  } catch {
    throw new Error(`Official review row ${rowID} must include a valid official source URL.`);
  }

  if (source.label === "College Scorecard") {
    const expectedURL = `${scorecardSchoolURLPrefix}${expectedUnitID}`;
    if (sourceURL !== expectedURL) {
      throw new Error(`Official review row ${rowID} Scorecard source URL must match UNITID ${expectedUnitID}.`);
    }
    return;
  }

  if (sourceURL.startsWith(ipedsDataFilesURLPrefix)) {
    if (parsed.origin !== "https://nces.ed.gov" || parsed.pathname !== "/ipeds/datacenter/DataFiles.aspx") {
      throw new Error(`Official review row ${rowID} must use the official NCES/IPEDS DataFiles URL.`);
    }
    return;
  }

  if (sourceURL.startsWith(ipedsReportedDataURLPrefix)) {
    const expectedPath = `/ipeds/reported-data/html/${expectedUnitID}`;
    if (parsed.origin !== "https://nces.ed.gov" || parsed.pathname !== expectedPath) {
      throw new Error(`Official review row ${rowID} NCES Reported Data source URL must match UNITID ${expectedUnitID}.`);
    }
    if (parsed.searchParams.get("surveyNumber") !== "12") {
      throw new Error(`Official review row ${rowID} NCES Reported Data source URL must use the Admissions component with surveyNumber=12.`);
    }
    return;
  }

  throw new Error(`Official review row ${rowID} must use a College Scorecard school URL, NCES/IPEDS DataFiles URL, or NCES/IPEDS Reported Data URL.`);
}

function validateOfficialRow(row) {
  const source = officialSource(row);
  if (!row.id || !row.name || !source.unitID || !source.reviewedName) {
    throw new Error(`Official review row is missing required identity fields: ${JSON.stringify(row)}`);
  }
  const expectedUnitID = unitIDsByCollegeID[row.id];
  if (!expectedUnitID) {
    throw new Error(`Official review row ${row.id} is not in the reviewed LAC UnitID map.`);
  }
  if (String(source.unitID).trim() !== expectedUnitID) {
    throw new Error(`Official review row ${row.id} uses UNITID ${source.unitID}; expected ${expectedUnitID}.`);
  }
  validateOfficialSourceURL(source, expectedUnitID, row.id);
  parseRatePercent(row);
  return source;
}

function validateReviewedName(source, seedRow, rowID) {
  const seedName = normalizeName(seedRow.name);
  const reviewedName = normalizeName(source.reviewedName);
  if (!seedName || !reviewedName || (!seedName.includes(reviewedName) && !reviewedName.includes(seedName))) {
    throw new Error(`Official review row ${rowID} reviewed school name "${source.reviewedName}" does not match seed school name "${seedRow.name}".`);
  }
}

function applyRates(seedRows, officialRows, latestRateSlot) {
  if (!latestRateSlot.startsWith("rate_")) {
    throw new Error("--latest-rate-slot must be a rate_* column.");
  }

  const officialByID = new Map(officialRows.map((row) => [row.id, row]));
  if (officialByID.size !== officialRows.length) {
    throw new Error("Official review file contains duplicate ids.");
  }
  if (officialRows.length !== seedRows.length) {
    throw new Error(`Official review row count ${officialRows.length} does not match LAC seed row count ${seedRows.length}.`);
  }

  return seedRows.map((row) => {
    const official = officialByID.get(row.id);
    if (!official) {
      throw new Error(`Missing official review row for ${row.id}.`);
    }
    const source = validateOfficialRow(official);
    if (row.name !== official.name || row.rank !== official.rank) {
      throw new Error(`Official review row ${row.id} no longer matches seed name/rank.`);
    }
    validateReviewedName(source, row, row.id);

    return {
      ...row,
      [latestRateSlot]: parseRatePercent(official),
      source_url: source.sourceURL,
      source_note: source.sourceNote,
      data_quality: "0.9"
    };
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const { headers, rows: seedRows } = await readCsvFile(args.input);
  const { rows: officialRows } = await readCsvFile(args.scorecard);
  if (!headers.includes(args.latestRateSlot)) {
    throw new Error(`Input CSV does not include ${args.latestRateSlot}.`);
  }

  const updatedRows = applyRates(seedRows, officialRows, args.latestRateSlot);
  const changed = updatedRows.filter((row, index) => row[args.latestRateSlot] !== seedRows[index][args.latestRateSlot]).length;
  if (args.dryRun) {
    console.log(`Validated ${updatedRows.length} official LAC rate rows. ${changed} ${args.latestRateSlot} values would change.`);
    return;
  }

  await fs.writeFile(args.output, toCsv(headers, updatedRows), "utf8");
  console.log(`Applied ${updatedRows.length} official LAC rates to ${path.relative(root, args.output)}.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
