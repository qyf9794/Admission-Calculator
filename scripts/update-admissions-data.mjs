import fs from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const dataDir = path.join(root, "data");
const outputPath = path.join(root, "AdmissionCalculator", "Data", "AdmissionsNormalizedData.swift");
const admissionSightURL = "https://admissionsight.com/college-acceptance-rates/";
const liberalArtsCollegeURL = "https://github.com/qyf9794/Admission-Calculator/blob/main/data/liberal_arts_colleges.csv";
const collegeScorecardSchoolURLPrefix = "https://collegescorecard.ed.gov/school/?";
const ipedsDataFilesURLPrefix = "https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx";
const ipedsReportedDataURLPrefix = "https://nces.ed.gov/ipeds/reported-data/html/";
const classYears = [2029, 2028, 2027, 2026, 2025, 2024];

function parseArgs(argv) {
  return {
    check: argv.includes("--check"),
  };
}

function parseCsv(text) {
  const rows = [];
  let field = "";
  let row = [];
  let inQuotes = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];

    if (char === '"') {
      if (inQuotes && next === '"') {
        field += '"';
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

async function readCsv(fileName) {
  return parseCsv(await fs.readFile(path.join(dataDir, fileName), "utf8"));
}

async function readJson(fileName) {
  return JSON.parse(await fs.readFile(path.join(dataDir, fileName), "utf8"));
}

function swiftString(value) {
  return `"${String(value).replaceAll("\\", "\\\\").replaceAll('"', '\\"').replaceAll("\n", "\\n")}"`;
}

function swiftOptionalString(value) {
  return value ? `URL(string: ${swiftString(value)})` : "nil";
}

function swiftOptionalInt(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed ? trimmed : "nil";
}

function swiftOptionalDouble(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed ? trimmed : "nil";
}

function swiftOptionalEnum(value, mapping) {
  const trimmed = String(value ?? "").trim();
  return trimmed ? mapping[trimmed] ?? fail(`Unsupported enum value: ${trimmed}`) : "nil";
}

function swiftEnumArray(value, mapping, label) {
  return String(value ?? "")
    .split("|")
    .map((item) => item.trim())
    .filter(Boolean)
    .map((item) => mapping[item] ?? fail(`Unsupported ${label}: ${item}`))
    .join(", ");
}

function fail(message) {
  throw new Error(message);
}

function optionalNumber(row, field, label = field) {
  const raw = String(row[field] ?? "").trim();
  if (!raw) {
    return null;
  }
  const value = Number(raw);
  if (!Number.isFinite(value)) {
    fail(`${label} must be numeric; got ${raw}.`);
  }
  return value;
}

function optionalInteger(row, field, label = field) {
  const value = optionalNumber(row, field, label);
  if (value === null) {
    return null;
  }
  if (!Number.isInteger(value)) {
    fail(`${label} must be an integer; got ${value}.`);
  }
  return value;
}

function requiredInteger(row, field, label = field) {
  const value = optionalInteger(row, field, label);
  if (value === null) {
    fail(`${label} is required.`);
  }
  return value;
}

function requireRange(value, min, max, label) {
  if (value !== null && (value < min || value > max)) {
    fail(`${label} must be between ${min} and ${max}; got ${value}.`);
  }
}

function dataQuality(row) {
  const explicit = String(row.data_quality ?? "").trim();
  if (explicit) {
    return Number(explicit).toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
  }
  const missing = classYears.some((year) => String(row[`rate_${year}`] ?? "").trim() === "");
  return missing ? "0.84" : "0.96";
}

function validateNationalUniversitySource(college) {
  const sourceURL = String(college.source_url ?? "").trim();
  const sourceNote = String(college.source_note ?? "").trim();

  if (sourceURL === admissionSightURL) {
    return;
  }

  let parsed;
  try {
    parsed = new URL(sourceURL);
  } catch {
    fail(`National university ${college.id} must use a valid reviewed source_url.`);
  }

  if (sourceURL.startsWith(collegeScorecardSchoolURLPrefix)) {
    const unitID = parsed.search.replace("?", "").trim();
    if (!/^\d{6}$/.test(unitID)) {
      fail(`National university ${college.id} Scorecard source_url must include a six-digit UNITID.`);
    }
    if (!sourceNote.includes("College Scorecard") || !sourceNote.includes(`UNITID ${unitID}`)) {
      fail(`National university ${college.id} Scorecard source_note must disclose College Scorecard and UNITID ${unitID}.`);
    }
    if (!sourceNote.includes("IMG_0749.JPG")) {
      fail(`National university ${college.id} non-AdmissionSight source_note must disclose IMG_0749.JPG rank scope.`);
    }
    return;
  }

  const allowedOfficialHosts = new Set(["irp.osu.edu", "oir.uga.edu"]);
  if (allowedOfficialHosts.has(parsed.hostname)) {
    if (!sourceNote.includes("IPEDS")) {
      fail(`National university ${college.id} official-school source_note must disclose IPEDS provenance.`);
    }
    if (!sourceNote.includes("IMG_0749.JPG")) {
      fail(`National university ${college.id} non-AdmissionSight source_note must disclose IMG_0749.JPG rank scope.`);
    }
    return;
  }

  fail(`National university ${college.id} must use AdmissionSight, exact College Scorecard school URL, or reviewed official IPEDS school source_url.`);
}

function rateLines(row) {
  return classYears.map((year) => {
    const raw = String(row[`rate_${year}`] ?? "").trim();
    const value = raw ? (Number(raw) / 100).toFixed(5).replace(/0+$/, "").replace(/\.$/, "") : "nil";
    return `            AcceptanceRate(classYear: ${year}, rate: ${value})`;
  }).join(",\n");
}

function validateLiberalArtsSource(college, liberalArtsUnitIDs) {
  const sourceURL = String(college.source_url ?? "").trim();
  const sourceNote = String(college.source_note ?? "").trim();

  if (sourceURL === liberalArtsCollegeURL) {
    if (!sourceNote.includes("IMG_0742.JPG")) {
      fail(`Reviewed LAC seed row ${college.id} must disclose the IMG_0742.JPG table in source_note.`);
    }
    const quality = optionalNumber(college, "data_quality", `College ${college.id} data_quality`);
    if (quality !== null && quality > 0.8) {
      fail(`Reviewed user-provided LAC seed row ${college.id} must keep proxy data_quality <= 0.8 until replaced by official Scorecard/IPEDS data.`);
    }
    return;
  }

  const expectedUnitID = String(liberalArtsUnitIDs?.[college.id] ?? "").trim();
  if (!/^\d{6}$/.test(expectedUnitID)) {
    fail(`Liberal arts college ${college.id} must have a reviewed six-digit UNITID before using official LAC source_url.`);
  }
  const quality = optionalNumber(college, "data_quality", `College ${college.id} data_quality`);
  if (quality === null || quality < 0.85) {
    fail(`Official LAC seed row ${college.id} must keep reviewed official data_quality >= 0.85.`);
  }

  let parsed;
  try {
    parsed = new URL(sourceURL);
  } catch {
    fail(`Liberal arts college ${college.id} must use a valid reviewed LAC source_url.`);
  }

  if (sourceURL.startsWith(collegeScorecardSchoolURLPrefix)) {
    const expectedURL = `${collegeScorecardSchoolURLPrefix}${expectedUnitID}`;
    if (sourceURL !== expectedURL) {
      fail(`Liberal arts college ${college.id} Scorecard source_url must match reviewed UNITID ${expectedUnitID}.`);
    }
    if (!sourceNote.includes(`UNITID ${expectedUnitID}`)) {
      fail(`Liberal arts college ${college.id} Scorecard source_note must disclose reviewed UNITID ${expectedUnitID}.`);
    }
    return;
  }

  if (sourceURL.startsWith(ipedsDataFilesURLPrefix)) {
    if (parsed.origin !== "https://nces.ed.gov" || parsed.pathname !== "/ipeds/datacenter/DataFiles.aspx") {
      fail(`Liberal arts college ${college.id} must use the official NCES/IPEDS DataFiles source_url.`);
    }
    if (!sourceNote.includes(`UNITID ${expectedUnitID}`)) {
      fail(`Liberal arts college ${college.id} NCES/IPEDS source_note must disclose reviewed UNITID ${expectedUnitID}.`);
    }
    return;
  }

  if (sourceURL.startsWith(ipedsReportedDataURLPrefix)) {
    const expectedPath = `/ipeds/reported-data/html/${expectedUnitID}`;
    if (parsed.origin !== "https://nces.ed.gov" || parsed.pathname !== expectedPath) {
      fail(`Liberal arts college ${college.id} NCES Reported Data source_url must match reviewed UNITID ${expectedUnitID}.`);
    }
    if (parsed.searchParams.get("surveyNumber") !== "12") {
      fail(`Liberal arts college ${college.id} NCES Reported Data source_url must use the Admissions component with surveyNumber=12.`);
    }
    if (!sourceNote.includes(`UNITID ${expectedUnitID}`)) {
      fail(`Liberal arts college ${college.id} NCES Reported Data source_note must disclose reviewed UNITID ${expectedUnitID}.`);
    }
    return;
  }

  fail(`Liberal arts college ${college.id} must use reviewed LAC source_url, exact College Scorecard school URL, NCES/IPEDS DataFiles URL, or NCES Reported Data Admissions URL.`);
}

function validate(colleges, gates, highSchools, registry, internationalSignals, chinaAdmissionSignals, academicBenchmarks, majorSelectivitySignals, liberalArtsUnitIDs) {
  if (!registry.data_version || !registry.generated_at) {
    fail("source_registry.json must include data_version and generated_at.");
  }

  const ids = new Set();
  for (const college of colleges) {
    if (!college.id || !college.name) {
      fail("Every college row must have id and name.");
    }
    if (!college.source_url || !college.source_note) {
      fail(`College ${college.id} must include source_url and source_note.`);
    }
    if (ids.has(college.id)) {
      fail(`Duplicate college id: ${college.id}`);
    }
    ids.add(college.id);
    if (!["national_university", "liberal_arts_college"].includes(college.category)) {
      fail(`College ${college.id} has unsupported category: ${college.category}`);
    }
    if (college.category === "national_university") {
      validateNationalUniversitySource(college);
    }
    if (college.category === "liberal_arts_college") {
      validateLiberalArtsSource(college, liberalArtsUnitIDs);
    }
    const hasRate = classYears.some((year) => String(college[`rate_${year}`] ?? "").trim() !== "");
    if (!hasRate) {
      fail(`College ${college.id} has no acceptance rates.`);
    }
    const rank = optionalInteger(college, "rank", `College ${college.id} rank`);
    requireRange(rank, 1, 500, `College ${college.id} rank`);
    requireRange(optionalNumber(college, "data_quality", `College ${college.id} data_quality`), 0, 1, `College ${college.id} data_quality`);
    for (const year of classYears) {
      const rate = optionalNumber(college, `rate_${year}`, `College ${college.id} rate_${year}`);
      requireRange(rate, 0.01, 100, `College ${college.id} rate_${year}`);
    }
  }

  for (const gate of gates) {
    if (gate.college_id !== "*" && !ids.has(gate.college_id)) {
      fail(`Gate ${gate.id} targets a school outside approved dataset: ${gate.college_id}`);
    }
    if (gate.is_official === "true" && !gate.source_url) {
      fail(`Official gate ${gate.id} must include source_url.`);
    }
    requireRange(optionalNumber(gate, "early_action_adjustment", `Gate ${gate.id} early_action_adjustment`), -1, 1, `Gate ${gate.id} early_action_adjustment`);
    requireRange(optionalNumber(gate, "early_decision_adjustment", `Gate ${gate.id} early_decision_adjustment`), -1, 1, `Gate ${gate.id} early_decision_adjustment`);
  }

  const signalIDs = new Set();
  for (const signal of internationalSignals) {
    if (!ids.has(signal.college_id)) {
      fail(`International signal targets a school outside approved dataset: ${signal.college_id}`);
    }
    if (signalIDs.has(signal.college_id)) {
      fail(`Duplicate international signal row: ${signal.college_id}`);
    }
    if (signal.is_undergrad_only !== "true") {
      fail(`International signal ${signal.college_id} must be undergraduate-only to participate in the model.`);
    }
    const coefficient = String(signal.international_admit_coefficient ?? "").trim();
    const intlAdmitted = String(signal.international_admitted_count ?? "").trim();
    const totalAdmitted = String(signal.total_admitted_count ?? "").trim();
    if (coefficient && (!intlAdmitted || !totalAdmitted)) {
      fail(`International admit coefficient for ${signal.college_id} requires both admitted counts.`);
    }
    requireRange(optionalNumber(signal, "undergrad_nonresident_share", `International signal ${signal.college_id} undergrad_nonresident_share`), 0, 1, `International signal ${signal.college_id} undergrad_nonresident_share`);
    requireRange(optionalNumber(signal, "international_admit_coefficient", `International signal ${signal.college_id} international_admit_coefficient`), 0, 1, `International signal ${signal.college_id} international_admit_coefficient`);
    requireRange(optionalNumber(signal, "data_quality", `International signal ${signal.college_id} data_quality`), 0, 1, `International signal ${signal.college_id} data_quality`);
    const admitted = optionalInteger(signal, "international_admitted_count", `International signal ${signal.college_id} international_admitted_count`);
    const total = optionalInteger(signal, "total_admitted_count", `International signal ${signal.college_id} total_admitted_count`);
    requireRange(admitted, 0, Number.MAX_SAFE_INTEGER, `International signal ${signal.college_id} international_admitted_count`);
    requireRange(total, 1, Number.MAX_SAFE_INTEGER, `International signal ${signal.college_id} total_admitted_count`);
    if (admitted !== null && total !== null && admitted > total) {
      fail(`International admitted count for ${signal.college_id} cannot exceed total admitted count.`);
    }
    signalIDs.add(signal.college_id);
  }
  for (const id of ids) {
    if (!signalIDs.has(id)) {
      fail(`Missing international signal row for ${id}`);
    }
  }

  const benchmarkIDs = new Set();
  for (const benchmark of academicBenchmarks) {
    if (!ids.has(benchmark.college_id)) {
      fail(`Academic benchmark targets a school outside approved dataset: ${benchmark.college_id}`);
    }
    if (benchmarkIDs.has(benchmark.college_id)) {
      fail(`Duplicate academic benchmark row: ${benchmark.college_id}`);
    }
    if (benchmark.is_inferred !== "true" && !benchmark.source_url) {
      fail(`Official academic benchmark ${benchmark.college_id} must include source_url.`);
    }
    requireRange(optionalNumber(benchmark, "gpa_percent_benchmark", `Academic benchmark ${benchmark.college_id} gpa_percent_benchmark`), 0, 100, `Academic benchmark ${benchmark.college_id} gpa_percent_benchmark`);
    requireRange(optionalNumber(benchmark, "class_rank_percentile_benchmark", `Academic benchmark ${benchmark.college_id} class_rank_percentile_benchmark`), 0, 100, `Academic benchmark ${benchmark.college_id} class_rank_percentile_benchmark`);
    requireRange(optionalInteger(benchmark, "sat_benchmark", `Academic benchmark ${benchmark.college_id} sat_benchmark`), 400, 1600, `Academic benchmark ${benchmark.college_id} sat_benchmark`);
    requireRange(optionalInteger(benchmark, "act_benchmark", `Academic benchmark ${benchmark.college_id} act_benchmark`), 1, 36, `Academic benchmark ${benchmark.college_id} act_benchmark`);
    requireRange(optionalInteger(benchmark, "rigor_benchmark", `Academic benchmark ${benchmark.college_id} rigor_benchmark`), 1, 5, `Academic benchmark ${benchmark.college_id} rigor_benchmark`);
    requireRange(optionalNumber(benchmark, "data_quality", `Academic benchmark ${benchmark.college_id} data_quality`), 0, 1, `Academic benchmark ${benchmark.college_id} data_quality`);
    benchmarkIDs.add(benchmark.college_id);
  }
  for (const id of ids) {
    if (!benchmarkIDs.has(id)) {
      fail(`Missing academic benchmark row for ${id}`);
    }
  }

  const majorSignalKeys = new Set();
  const supportedMajorCategories = new Set([
    "Computer Science",
    "Engineering",
    "Business",
    "Economics",
    "Nursing",
    "Natural Science",
    "Social Science",
    "Humanities",
    "Film",
    "Architecture",
    "Aviation",
    "Arts",
  ]);
  const supportedSourceTiers = new Set([
    "official",
    "institution_adjacent",
    "reputable_secondary",
    "consultant_estimate",
  ]);
  const supportedApplicantScopes = new Set([
    "all_applicants",
    "international_or_nonresident",
  ]);
  for (const signal of majorSelectivitySignals) {
    if (!ids.has(signal.college_id)) {
      fail(`Major selectivity signal targets a school outside approved dataset: ${signal.college_id}`);
    }
    if (!supportedMajorCategories.has(signal.major_category)) {
      fail(`Major selectivity signal ${signal.college_id} has unsupported major_category: ${signal.major_category}`);
    }
    if (!signal.program_label || !signal.source_url || !signal.source_note) {
      fail(`Major selectivity signal ${signal.college_id}/${signal.major_category} must include program_label, source_url, and source_note.`);
    }
    if (!supportedSourceTiers.has(signal.source_tier)) {
      fail(`Major selectivity signal ${signal.college_id}/${signal.major_category} has unsupported source_tier: ${signal.source_tier}`);
    }
    if (!supportedApplicantScopes.has(signal.applicant_scope)) {
      fail(`Major selectivity signal ${signal.college_id}/${signal.major_category} has unsupported applicant_scope: ${signal.applicant_scope}`);
    }
    if (signal.is_undergrad_first_year !== "true") {
      fail(`Major selectivity signal ${signal.college_id}/${signal.major_category} must be undergraduate first-year scope.`);
    }
    if (signal.is_direct_admit_rate === "true" && !String(signal.admit_rate ?? "").trim()) {
      fail(`Direct major selectivity signal ${signal.college_id}/${signal.major_category} requires admit_rate.`);
    }
    const key = [
      signal.college_id,
      signal.major_category,
      signal.program_label,
      signal.applicant_scope,
    ].join("|");
    if (majorSignalKeys.has(key)) {
      fail(`Duplicate major selectivity signal row: ${key}`);
    }
    majorSignalKeys.add(key);
    try {
      new URL(signal.source_url);
    } catch {
      fail(`Major selectivity signal ${signal.college_id}/${signal.major_category} must use a valid source_url.`);
    }
    const applicants = optionalInteger(signal, "applicants", `Major selectivity signal ${signal.college_id}/${signal.major_category} applicants`);
    const admits = optionalInteger(signal, "admits", `Major selectivity signal ${signal.college_id}/${signal.major_category} admits`);
    const enrolledOrSpots = optionalInteger(signal, "enrolled_or_spots", `Major selectivity signal ${signal.college_id}/${signal.major_category} enrolled_or_spots`);
    requireRange(applicants, 0, Number.MAX_SAFE_INTEGER, `Major selectivity signal ${signal.college_id}/${signal.major_category} applicants`);
    requireRange(admits, 0, Number.MAX_SAFE_INTEGER, `Major selectivity signal ${signal.college_id}/${signal.major_category} admits`);
    requireRange(enrolledOrSpots, 0, Number.MAX_SAFE_INTEGER, `Major selectivity signal ${signal.college_id}/${signal.major_category} enrolled_or_spots`);
    if (applicants !== null && admits !== null && admits > applicants) {
      fail(`Major selectivity signal ${signal.college_id}/${signal.major_category} admits cannot exceed applicants.`);
    }
    const entryYear = optionalInteger(signal, "entry_year", `Major selectivity signal ${signal.college_id}/${signal.major_category} entry_year`);
    const classYear = optionalInteger(signal, "class_year", `Major selectivity signal ${signal.college_id}/${signal.major_category} class_year`);
    if (entryYear === null) {
      fail(`Major selectivity signal ${signal.college_id}/${signal.major_category} requires entry_year.`);
    }
    requireRange(entryYear, 2000, 2100, `Major selectivity signal ${signal.college_id}/${signal.major_category} entry_year`);
    requireRange(classYear, 2000, 2100, `Major selectivity signal ${signal.college_id}/${signal.major_category} class_year`);
    if (classYear !== null && (classYear < entryYear || classYear > entryYear + 6)) {
      fail(`Major selectivity signal ${signal.college_id}/${signal.major_category} class_year must be consistent with entry_year; got entry_year=${entryYear}, class_year=${classYear}.`);
    }
    requireRange(optionalNumber(signal, "admit_rate", `Major selectivity signal ${signal.college_id}/${signal.major_category} admit_rate`), 0, 1, `Major selectivity signal ${signal.college_id}/${signal.major_category} admit_rate`);
    requireRange(optionalNumber(signal, "overall_admit_rate", `Major selectivity signal ${signal.college_id}/${signal.major_category} overall_admit_rate`), 0, 1, `Major selectivity signal ${signal.college_id}/${signal.major_category} overall_admit_rate`);
    requireRange(optionalNumber(signal, "selectivity_ratio", `Major selectivity signal ${signal.college_id}/${signal.major_category} selectivity_ratio`), 0, 5, `Major selectivity signal ${signal.college_id}/${signal.major_category} selectivity_ratio`);
    requireRange(optionalNumber(signal, "data_quality", `Major selectivity signal ${signal.college_id}/${signal.major_category} data_quality`), 0, 1, `Major selectivity signal ${signal.college_id}/${signal.major_category} data_quality`);
  }

  const chinaSignalIDs = new Set();
  for (const signal of chinaAdmissionSignals) {
    if (!ids.has(signal.college_id)) {
      fail(`China admission signal targets a school outside approved dataset: ${signal.college_id}`);
    }
    if (chinaSignalIDs.has(signal.college_id)) {
      fail(`Duplicate China admission signal row: ${signal.college_id}`);
    }
    const total2030 = String(signal.china_2030_total ?? "").trim();
    if (!total2030) {
      fail(`China admission signal ${signal.college_id} must include china_2030_total.`);
    }
    for (const year of [2028, 2029, 2030]) {
      const early = optionalInteger(signal, `china_${year}_early`, `China admission signal ${signal.college_id} china_${year}_early`);
      const rd = optionalInteger(signal, `china_${year}_rd`, `China admission signal ${signal.college_id} china_${year}_rd`);
      const total = optionalInteger(signal, `china_${year}_total`, `China admission signal ${signal.college_id} china_${year}_total`);
      requireRange(early, 0, Number.MAX_SAFE_INTEGER, `China admission signal ${signal.college_id} china_${year}_early`);
      requireRange(rd, 0, Number.MAX_SAFE_INTEGER, `China admission signal ${signal.college_id} china_${year}_rd`);
      requireRange(total, 0, Number.MAX_SAFE_INTEGER, `China admission signal ${signal.college_id} china_${year}_total`);
      if (early !== null && rd !== null && total !== null && early + rd !== total) {
        fail(`China admission signal ${signal.college_id} ${year} total must equal early + RD.`);
      }
    }
    requireRange(optionalNumber(signal, "china_share_of_all_admits", `China admission signal ${signal.college_id} china_share_of_all_admits`), 0, 1, `China admission signal ${signal.college_id} china_share_of_all_admits`);
    requireRange(optionalNumber(signal, "data_quality", `China admission signal ${signal.college_id} data_quality`), 0, 1, `China admission signal ${signal.college_id} data_quality`);
    chinaSignalIDs.add(signal.college_id);
  }

  const highSchoolIds = new Set();
  let unknownHighSchool = null;
  for (const school of highSchools.schools ?? []) {
    if (!school.id || !school.name || !school.city) {
      fail(`Every high school row must include id, name, and city: ${JSON.stringify(school)}`);
    }
    if (highSchoolIds.has(school.id)) {
      fail(`Duplicate high school id: ${school.id}`);
    }
    const admitRankingBand = requiredInteger(school, "admit_ranking_band", `High school ${school.id} admit_ranking_band`);
    const resources = requiredInteger(school, "resources", `High school ${school.id} resources`);
    const counseling = requiredInteger(school, "counseling", `High school ${school.id} counseling`);
    const top30TrackRecord = requiredInteger(school, "top30_track_record", `High school ${school.id} top30_track_record`);
    const transparency = requiredInteger(school, "transparency", `High school ${school.id} transparency`);
    requireRange(admitRankingBand, 1, 5, `High school ${school.id} admit_ranking_band`);
    requireRange(resources, 1, 5, `High school ${school.id} resources`);
    requireRange(counseling, 1, 5, `High school ${school.id} counseling`);
    requireRange(top30TrackRecord, 1, 5, `High school ${school.id} top30_track_record`);
    requireRange(transparency, 1, 5, `High school ${school.id} transparency`);
    if (school.id === "unknown") {
      unknownHighSchool = {
        admitRankingBand,
        resources,
        counseling,
        top30TrackRecord,
        transparency
      };
    }
    highSchoolIds.add(school.id);
  }
  if (!highSchoolIds.has("unknown")) {
    fail("High school data must include unknown fallback.");
  }
  if (
    unknownHighSchool.admitRankingBand < 3 ||
    unknownHighSchool.resources > 3 ||
    unknownHighSchool.counseling > 3 ||
    unknownHighSchool.top30TrackRecord > 2 ||
    unknownHighSchool.transparency > 3
  ) {
    fail("High school unknown fallback must remain conservative: band >= 3, resources/counseling/transparency <= 3, and top30_track_record <= 2.");
  }

  const liberalArtsIDs = colleges
    .filter((college) => college.category === "liberal_arts_college")
    .map((college) => college.id);
  const unitIDEntries = Object.entries(liberalArtsUnitIDs ?? {});
  const seenUnitIDs = new Set();
  for (const [collegeID, unitID] of unitIDEntries) {
    if (!liberalArtsIDs.includes(collegeID)) {
      fail(`LAC UnitID map includes ${collegeID}, which is not in data/liberal_arts_colleges.csv.`);
    }
    const normalized = String(unitID ?? "").trim();
    if (!/^\d{6}$/.test(normalized)) {
      fail(`LAC UnitID for ${collegeID} must be a six-digit IPEDS/Scorecard UNITID.`);
    }
    if (seenUnitIDs.has(normalized)) {
      fail(`Duplicate LAC UNITID in data/liberal_arts_unitids.json: ${normalized}.`);
    }
    seenUnitIDs.add(normalized);
  }
  for (const collegeID of liberalArtsIDs) {
    if (!Object.hasOwn(liberalArtsUnitIDs ?? {}, collegeID)) {
      fail(`Missing LAC UnitID mapping for ${collegeID}.`);
    }
  }
}

function renderSources(registry) {
  return registry.sources.map((source) => `        DataSourceRecord(
            id: ${swiftString(source.id)},
            name: ${swiftString(source.name)},
            url: URL(string: ${swiftString(source.url)})!,
            role: ${swiftString(source.role)},
            refreshMode: ${swiftString(source.refresh_mode)},
            confidence: ${swiftString(source.confidence)},
            note: ${swiftString(source.note)}
        )`).join(",\n");
}

function renderColleges(colleges) {
  const categoryMap = {
    national_university: ".nationalUniversity",
    liberal_arts_college: ".liberalArtsCollege",
  };

  return colleges
    .sort((left, right) => {
      const order = { national_university: 0, liberal_arts_college: 1 };
      const categoryOrder = order[left.category] - order[right.category];
      return categoryOrder || Number(left.rank) - Number(right.rank) || left.name.localeCompare(right.name);
    })
    .map((college) => `        College(
            id: ${swiftString(college.id)},
            name: ${swiftString(college.name)},
            category: ${categoryMap[college.category] ?? fail(`Unsupported college category: ${college.category}`)},
            rank: ${Number(college.rank)},
            acceptanceRates: [
${rateLines(college)}
            ],
            sourceURL: URL(string: ${swiftString(college.source_url)})!,
            sourceNote: ${swiftString(college.source_note)},
            dataQuality: ${dataQuality(college)}
        )`)
    .join(",\n");
}

function renderHighSchools(highSchools) {
  const orderedSchools = [
    ...highSchools.schools.filter((school) => school.id === "unknown"),
    ...highSchools.schools.filter((school) => school.id !== "unknown"),
  ];
  return orderedSchools.map((school) => `        HighSchoolContext(
            id: ${swiftString(school.id)},
            name: ${swiftString(school.name)},
            city: ${swiftString(school.city)},
            admitRankingBand: ${Number(school.admit_ranking_band)},
            resources: ${Number(school.resources)},
            counseling: ${Number(school.counseling)},
            top30TrackRecord: ${Number(school.top30_track_record)},
            transparency: ${Number(school.transparency)}
        )`).join(",\n");
}

function renderInternationalSignals(signals) {
  const policyMap = {
    need_blind: ".needBlind",
    need_aware: ".needAware",
    limited: ".limited",
    unknown: ".unknown",
  };

  return signals.map((signal) => {
    const sourceFields = String(signal.source_fields || "")
      .split("|")
      .map((item) => item.trim())
      .filter(Boolean)
      .map(swiftString)
      .join(", ");
    return `        InternationalSignal(
            collegeID: ${swiftString(signal.college_id)},
            undergradNonresidentShare: ${swiftOptionalDouble(signal.undergrad_nonresident_share)},
            internationalAdmittedCount: ${swiftOptionalInt(signal.international_admitted_count)},
            totalAdmittedCount: ${swiftOptionalInt(signal.total_admitted_count)},
            internationalAdmitCoefficient: ${swiftOptionalDouble(signal.international_admit_coefficient)},
            internationalAidPolicy: ${policyMap[signal.international_aid_policy] ?? fail(`Unsupported aid policy: ${signal.international_aid_policy}`)},
            isUndergradOnly: ${signal.is_undergrad_only === "true" ? "true" : "false"},
            dataScope: ${swiftString(signal.data_scope)},
            sourceFields: [${sourceFields}],
            sourceURL: ${swiftOptionalString(signal.source_url)},
            sourceNote: ${swiftString(signal.source_note)},
            dataQuality: ${swiftOptionalDouble(signal.data_quality) === "nil" ? "0.30" : swiftOptionalDouble(signal.data_quality)}
        )`;
  }).join(",\n");
}

function renderChinaAdmissionSignals(signals) {
  return signals.map((signal) => `        ChinaUndergradAdmissionSignal(
            collegeID: ${swiftString(signal.college_id)},
            early2028: ${swiftOptionalInt(signal.china_2028_early)},
            rd2028: ${swiftOptionalInt(signal.china_2028_rd)},
            total2028: ${swiftOptionalInt(signal.china_2028_total)},
            early2029: ${swiftOptionalInt(signal.china_2029_early)},
            rd2029: ${swiftOptionalInt(signal.china_2029_rd)},
            total2029: ${swiftOptionalInt(signal.china_2029_total)},
            early2030: ${swiftOptionalInt(signal.china_2030_early)},
            rd2030: ${swiftOptionalInt(signal.china_2030_rd)},
            total2030: ${swiftOptionalInt(signal.china_2030_total)},
            chinaShareOfAllAdmits: ${swiftOptionalDouble(signal.china_share_of_all_admits)},
            dataScope: ${swiftString(signal.data_scope)},
            sourceNote: ${swiftString(signal.source_note)},
            dataQuality: ${swiftOptionalDouble(signal.data_quality) === "nil" ? "0.50" : swiftOptionalDouble(signal.data_quality)}
        )`).join(",\n");
}

function renderAcademicBenchmarks(benchmarks) {
  return benchmarks.map((benchmark) => {
    const sourceFields = String(benchmark.source_fields || "")
      .split("|")
      .map((item) => item.trim())
      .filter(Boolean)
      .map(swiftString)
      .join(", ");
    return `        AcademicBenchmark(
            collegeID: ${swiftString(benchmark.college_id)},
            gpaPercentBenchmark: ${swiftOptionalDouble(benchmark.gpa_percent_benchmark)},
            classRankPercentileBenchmark: ${swiftOptionalDouble(benchmark.class_rank_percentile_benchmark)},
            satBenchmark: ${swiftOptionalInt(benchmark.sat_benchmark)},
            actBenchmark: ${swiftOptionalInt(benchmark.act_benchmark)},
            rigorBenchmark: ${swiftOptionalInt(benchmark.rigor_benchmark)},
            isInferred: ${benchmark.is_inferred === "true" ? "true" : "false"},
            sourceFields: [${sourceFields}],
            sourceURL: ${swiftOptionalString(benchmark.source_url)},
            sourceNote: ${swiftString(benchmark.source_note)},
            dataQuality: ${swiftOptionalDouble(benchmark.data_quality) === "nil" ? "0.40" : swiftOptionalDouble(benchmark.data_quality)}
        )`;
  }).join(",\n");
}

function renderMajorSelectivitySignals(signals) {
  const majorMap = {
    "Computer Science": ".computerScience",
    Engineering: ".engineering",
    Business: ".business",
    Economics: ".economics",
    Nursing: ".nursing",
    "Natural Science": ".naturalScience",
    "Social Science": ".socialScience",
    Humanities: ".humanities",
    Film: ".film",
    Architecture: ".architecture",
    Aviation: ".aviation",
    Arts: ".arts",
  };
  const sourceTierMap = {
    official: ".official",
    institution_adjacent: ".institutionAdjacent",
    reputable_secondary: ".reputableSecondary",
    consultant_estimate: ".consultantEstimate",
  };
  const applicantScopeMap = {
    all_applicants: ".allApplicants",
    international_or_nonresident: ".internationalOrNonresident",
  };

  return signals.map((signal) => `        MajorSelectivitySignal(
            collegeID: ${swiftString(signal.college_id)},
            majorCategory: ${majorMap[signal.major_category] ?? fail(`Unsupported major category: ${signal.major_category}`)},
            programLabel: ${swiftString(signal.program_label)},
            entryYear: ${Number(signal.entry_year)},
            classYear: ${swiftOptionalInt(signal.class_year)},
            metricScope: ${swiftString(signal.metric_scope)},
            applicantScope: ${applicantScopeMap[signal.applicant_scope] ?? fail(`Unsupported applicant scope: ${signal.applicant_scope}`)},
            applicants: ${swiftOptionalInt(signal.applicants)},
            admits: ${swiftOptionalInt(signal.admits)},
            admitRate: ${swiftOptionalDouble(signal.admit_rate)},
            enrolledOrSpots: ${swiftOptionalInt(signal.enrolled_or_spots)},
            overallAdmitRate: ${swiftOptionalDouble(signal.overall_admit_rate)},
            selectivityRatio: ${swiftOptionalDouble(signal.selectivity_ratio)},
            isDirectAdmitRate: ${signal.is_direct_admit_rate === "true" ? "true" : "false"},
            isUndergradFirstYear: ${signal.is_undergrad_first_year === "true" ? "true" : "false"},
            sourceTier: ${sourceTierMap[signal.source_tier] ?? fail(`Unsupported source tier: ${signal.source_tier}`)},
            sourceURL: URL(string: ${swiftString(signal.source_url)})!,
            sourceNote: ${swiftString(signal.source_note)},
            dataQuality: ${swiftOptionalDouble(signal.data_quality) === "nil" ? "0.40" : swiftOptionalDouble(signal.data_quality)}
        )`).join(",\n");
}

function renderGateRules(gates) {
  const typeMap = {
    standardizedTest: ".standardizedTest",
    english: ".english",
    curriculum: ".curriculum",
    portfolio: ".portfolio",
    round: ".round",
  };
  const roundMap = {
    EA: ".earlyAction",
    ED: ".earlyDecision",
    RD: ".regularDecision",
  };
  const majorMap = {
    "Computer Science": ".computerScience",
    Engineering: ".engineering",
    Business: ".business",
    Economics: ".economics",
    Nursing: ".nursing",
    "Natural Science": ".naturalScience",
    "Social Science": ".socialScience",
    Humanities: ".humanities",
    Film: ".film",
    Architecture: ".architecture",
    Aviation: ".aviation",
    Arts: ".arts",
  };

  return gates.map((gate) => {
    const allowedRounds = swiftEnumArray(gate.allowed_rounds, roundMap, `allowed round for ${gate.id}`);
    return `        CollegeGateRule(
            id: ${swiftString(gate.id)},
            collegeID: ${swiftString(gate.college_id)},
            type: ${typeMap[gate.type] ?? fail(`Unsupported gate type: ${gate.type}`)},
            title: ${swiftString(gate.title)},
            detail: ${swiftString(gate.detail)},
            isOfficial: ${gate.is_official === "true" ? "true" : "false"},
            sourceURL: ${swiftOptionalString(gate.source_url)},
            minimumSAT: ${swiftOptionalInt(gate.minimum_sat)},
            minimumTOEFL: ${swiftOptionalInt(gate.minimum_toefl)},
            requiredRound: ${swiftOptionalEnum(gate.required_round, roundMap)},
            allowedRounds: [${allowedRounds}],
            earlyActionAdjustment: ${swiftOptionalDouble(gate.early_action_adjustment)},
            earlyDecisionAdjustment: ${swiftOptionalDouble(gate.early_decision_adjustment)},
            affectedMajor: ${swiftOptionalEnum(gate.affected_major, majorMap)},
            minimumStrengthBand: ${swiftOptionalInt(gate.minimum_strength_band)}
        )`;
  }).join(",\n");
}

function renderSwift({ registry, colleges, highSchools, gates, internationalSignals, chinaAdmissionSignals, academicBenchmarks, majorSelectivitySignals }) {
  return `import Foundation

// Generated by scripts/update-admissions-data.mjs from files in data/.
// Edit the source CSV/JSON files, then rerun the script.
enum AdmissionsNormalizedData {
    static let dataVersion = ${swiftString(registry.data_version)}
    static let generatedAt = ${swiftString(registry.generated_at)}
    static let admissionsSightURL = URL(string: ${swiftString(admissionSightURL)})!
    static let liberalArtsCollegeURL = URL(string: ${swiftString(liberalArtsCollegeURL)})!

    static let sourceRecords: [DataSourceRecord] = [
${renderSources(registry)}
    ]

    static let colleges: [College] = [
${renderColleges(colleges)}
    ].sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }

    static let internationalSignals: [InternationalSignal] = [
${renderInternationalSignals(internationalSignals)}
    ]

    static let chinaAdmissionSignals: [ChinaUndergradAdmissionSignal] = [
${renderChinaAdmissionSignals(chinaAdmissionSignals)}
    ]

    static let academicBenchmarks: [AcademicBenchmark] = [
${renderAcademicBenchmarks(academicBenchmarks)}
    ]

    static let majorSelectivitySignals: [MajorSelectivitySignal] = [
${renderMajorSelectivitySignals(majorSelectivitySignals)}
    ]

    static let highSchools: [HighSchoolContext] = [
${renderHighSchools(highSchools)}
    ]

    static let gateRules: [CollegeGateRule] = [
${renderGateRules(gates)}
    ]
}
`;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const [registry, nationalUniversities, liberalArtsColleges, highSchools, gates, internationalSignals, chinaAdmissionSignals, academicBenchmarks, majorSelectivitySignals, liberalArtsUnitIDs] = await Promise.all([
    readJson("source_registry.json"),
    readCsv("admissionsight_colleges.csv"),
    readCsv("liberal_arts_colleges.csv"),
    readJson("china_high_schools.json"),
    readCsv("official_gate_rules.csv"),
    readCsv("international_student_signals.csv"),
    readCsv("china_undergrad_admissions.csv"),
    readCsv("academic_benchmarks.csv"),
    readCsv("major_selectivity_signals.csv"),
    readJson("liberal_arts_unitids.json"),
  ]);
  const colleges = [
    ...nationalUniversities.map((college) => ({ ...college, category: "national_university" })),
    ...liberalArtsColleges.map((college) => ({ ...college, category: "liberal_arts_college" })),
  ];

  validate(colleges, gates, highSchools, registry, internationalSignals, chinaAdmissionSignals, academicBenchmarks, majorSelectivitySignals, liberalArtsUnitIDs);
  const swift = renderSwift({ registry, colleges, highSchools, gates, internationalSignals, chinaAdmissionSignals, academicBenchmarks, majorSelectivitySignals });

  if (options.check) {
    const existing = await fs.readFile(outputPath, "utf8");
    if (existing !== swift) {
      fail("Generated admissions data is out of date. Run `node scripts/update-admissions-data.mjs`.");
    }
    console.log("Admissions data is up to date.");
    return;
  }

  await fs.writeFile(outputPath, swift, "utf8");
  console.log(`Wrote ${outputPath}`);
  console.log(`Schools=${colleges.length}, national_universities=${nationalUniversities.length}, liberal_arts_colleges=${liberalArtsColleges.length}, gates=${gates.length}, international_signals=${internationalSignals.length}, china_admission_signals=${chinaAdmissionSignals.length}, academic_benchmarks=${academicBenchmarks.length}, major_selectivity_signals=${majorSelectivitySignals.length}, high_schools=${highSchools.schools.length}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
