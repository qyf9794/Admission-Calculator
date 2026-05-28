import fs from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const dataDir = path.join(root, "data");
const defaultInputPath = path.join(dataDir, "liberal_arts_colleges.csv");
const defaultOutputPath = path.join(dataDir, "lac_official_url_manifest.csv");
const scorecardSchoolURLPrefix = "https://collegescorecard.ed.gov/school/?";
const ncesReportedDataURLPrefix = "https://nces.ed.gov/ipeds/reported-data/html/";

function parseArgs(argv) {
  const args = {
    input: defaultInputPath,
    output: defaultOutputPath,
    year: "2024",
    check: false,
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
    case "--year":
      args.year = String(argv[++index] ?? "").trim();
      break;
    case "--check":
      args.check = true;
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
  npm run data:lac:official-urls
  npm run data:lac:official-urls -- --year 2024 --output data/lac_official_url_manifest.csv

Options:
  --input <path>   Reviewed LAC seed CSV. Defaults to data/liberal_arts_colleges.csv.
  --output <path>  Output CSV. Defaults to data/lac_official_url_manifest.csv.
  --year <year>    NCES Reported Data year parameter. Defaults to 2024.
  --check          Verify the output file is current instead of writing it.
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
    "scorecard_school_url",
    "nces_reported_admissions_url",
    "reported_html_filename"
  ];
  return [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => csvEscape(row[header])).join(","))
  ].join("\n") + "\n";
}

async function checkOutput(filePath, expectedText) {
  let currentText;
  try {
    currentText = await fs.readFile(filePath, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") {
      throw new Error(`Official LAC URL manifest is missing at ${filePath}. Run npm run data:lac:official-urls.`);
    }
    throw error;
  }

  if (currentText !== expectedText) {
    throw new Error(`Official LAC URL manifest is out of date at ${filePath}. Run npm run data:lac:official-urls -- --year ${argsYearHint(expectedText)}.`);
  }
}

function argsYearHint(csvText) {
  const match = csvText.match(/[?&]year=(\d{4})&/);
  return match?.[1] ?? "2024";
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const colleges = parseCsv(await fs.readFile(args.input, "utf8"));
  const unitIDsByCollegeID = JSON.parse(await fs.readFile(path.join(dataDir, "liberal_arts_unitids.json"), "utf8"));
  const rows = colleges.map((college) => {
    const unitID = unitIDsByCollegeID[college.id];
    if (!unitID) {
      throw new Error(`No reviewed IPEDS UNITID mapping for ${college.id}.`);
    }
    return {
      id: college.id,
      name: college.name,
      rank: college.rank,
      ipeds_unitid: unitID,
      scorecard_school_url: `${scorecardSchoolURLPrefix}${unitID}`,
      nces_reported_admissions_url: `${ncesReportedDataURLPrefix}${unitID}?year=${encodeURIComponent(args.year)}&surveyNumber=12&viewmode=print`,
      reported_html_filename: `${unitID}.html`
    };
  });

  const csvText = toCsv(rows);
  if (args.check) {
    await checkOutput(args.output, csvText);
    console.log(`Official LAC URL manifest is current at ${args.output}.`);
    return;
  }

  await fs.writeFile(args.output, csvText, "utf8");
  console.log(`Wrote ${rows.length} official LAC URL rows to ${args.output}.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
