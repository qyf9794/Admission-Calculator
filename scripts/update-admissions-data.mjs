import fs from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const dataDir = path.join(root, "data");
const outputPath = path.join(root, "AdmissionCalculator", "Data", "AdmissionsNormalizedData.swift");
const admissionSightURL = "https://admissionsight.com/college-acceptance-rates/";
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

function requireRange(value, min, max, label) {
  if (value !== null && (value < min || value > max)) {
    fail(`${label} must be between ${min} and ${max}; got ${value}.`);
  }
}

function dataQuality(row) {
  const missing = classYears.some((year) => String(row[`rate_${year}`] ?? "").trim() === "");
  return missing ? "0.84" : "0.96";
}

function rateLines(row) {
  return classYears.map((year) => {
    const raw = String(row[`rate_${year}`] ?? "").trim();
    const value = raw ? (Number(raw) / 100).toFixed(5).replace(/0+$/, "").replace(/\.$/, "") : "nil";
    return `            AcceptanceRate(classYear: ${year}, rate: ${value})`;
  }).join(",\n");
}

function validate(colleges, gates, highSchools, registry, internationalSignals, chinaAdmissionSignals, academicBenchmarks) {
  if (!registry.data_version || !registry.generated_at) {
    fail("source_registry.json must include data_version and generated_at.");
  }

  const ids = new Set();
  for (const college of colleges) {
    if (!college.id || !college.name) {
      fail("Every college row must have id and name.");
    }
    if (ids.has(college.id)) {
      fail(`Duplicate college id: ${college.id}`);
    }
    ids.add(college.id);
    if (college.source_url !== admissionSightURL) {
      fail(`College ${college.id} must use AdmissionSight source_url.`);
    }
    const hasRate = classYears.some((year) => String(college[`rate_${year}`] ?? "").trim() !== "");
    if (!hasRate) {
      fail(`College ${college.id} has no acceptance rates.`);
    }
    const rank = optionalInteger(college, "rank", `College ${college.id} rank`);
    requireRange(rank, 1, 500, `College ${college.id} rank`);
    for (const year of classYears) {
      const rate = optionalNumber(college, `rate_${year}`, `College ${college.id} rate_${year}`);
      requireRange(rate, 0.01, 100, `College ${college.id} rate_${year}`);
    }
  }

  for (const gate of gates) {
    if (gate.college_id !== "*" && !ids.has(gate.college_id)) {
      fail(`Gate ${gate.id} targets a school outside AdmissionSight dataset: ${gate.college_id}`);
    }
    if (gate.is_official === "true" && !gate.source_url) {
      fail(`Official gate ${gate.id} must include source_url.`);
    }
  }

  const signalIDs = new Set();
  for (const signal of internationalSignals) {
    if (!ids.has(signal.college_id)) {
      fail(`International signal targets a school outside AdmissionSight dataset: ${signal.college_id}`);
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
      fail(`Academic benchmark targets a school outside AdmissionSight dataset: ${benchmark.college_id}`);
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

  const chinaSignalIDs = new Set();
  for (const signal of chinaAdmissionSignals) {
    if (!ids.has(signal.college_id)) {
      fail(`China admission signal targets a school outside AdmissionSight dataset: ${signal.college_id}`);
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
  for (const school of highSchools.schools ?? []) {
    if (highSchoolIds.has(school.id)) {
      fail(`Duplicate high school id: ${school.id}`);
    }
    highSchoolIds.add(school.id);
  }
  if (!highSchoolIds.has("unknown")) {
    fail("High school data must include unknown fallback.");
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
  return colleges
    .sort((left, right) => Number(left.rank) - Number(right.rank) || left.name.localeCompare(right.name))
    .map((college) => `        College(
            id: ${swiftString(college.id)},
            name: ${swiftString(college.name)},
            rank: ${Number(college.rank)},
            acceptanceRates: [
${rateLines(college)}
            ],
            sourceURL: admissionsSightURL,
            dataQuality: ${dataQuality(college)}
        )`)
    .join(",\n");
}

function renderHighSchools(highSchools) {
  return highSchools.schools.map((school) => `        HighSchoolContext(
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
    "Natural Science": ".naturalScience",
    "Social Science": ".socialScience",
    Humanities: ".humanities",
    Arts: ".arts",
  };

  return gates.map((gate) => `        CollegeGateRule(
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
            affectedMajor: ${swiftOptionalEnum(gate.affected_major, majorMap)},
            minimumStrengthBand: ${swiftOptionalInt(gate.minimum_strength_band)}
        )`).join(",\n");
}

function renderSwift({ registry, colleges, highSchools, gates, internationalSignals, chinaAdmissionSignals, academicBenchmarks }) {
  return `import Foundation

// Generated by scripts/update-admissions-data.mjs from files in data/.
// Edit the source CSV/JSON files, then rerun the script.
enum AdmissionsNormalizedData {
    static let dataVersion = ${swiftString(registry.data_version)}
    static let generatedAt = ${swiftString(registry.generated_at)}
    static let admissionsSightURL = URL(string: ${swiftString(admissionSightURL)})!

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
  const [registry, colleges, highSchools, gates, internationalSignals, chinaAdmissionSignals, academicBenchmarks] = await Promise.all([
    readJson("source_registry.json"),
    readCsv("admissionsight_colleges.csv"),
    readJson("china_high_schools.json"),
    readCsv("official_gate_rules.csv"),
    readCsv("international_student_signals.csv"),
    readCsv("china_undergrad_admissions.csv"),
    readCsv("academic_benchmarks.csv"),
  ]);

  validate(colleges, gates, highSchools, registry, internationalSignals, chinaAdmissionSignals, academicBenchmarks);
  const swift = renderSwift({ registry, colleges, highSchools, gates, internationalSignals, chinaAdmissionSignals, academicBenchmarks });

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
  console.log(`Schools=${colleges.length}, gates=${gates.length}, international_signals=${internationalSignals.length}, china_admission_signals=${chinaAdmissionSignals.length}, academic_benchmarks=${academicBenchmarks.length}, high_schools=${highSchools.schools.length}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
