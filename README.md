# Admission Calculator

SwiftUI iPhone app for estimating U.S. undergraduate admission chances for Chinese applicants.

The v1 model is intentionally transparent:

- AdmissionSight National Universities plus the reviewed user-provided 2026 U.S. News T50 image supplement and the reviewed user-provided Top30 Liberal Arts Colleges list/rank table define the v1 school scope; supplemental National University rows and LAC base rates use reviewed official College Scorecard/IPEDS data where AdmissionSight is missing or where LAC rates have been officially replaced.
- The report tab exposes per-school source audit notes in a data-source sheet for the major inputs used in probability math.
- Source audit includes structured round-policy fields such as allowed rounds and explicit EA/ED adjustments.
- Hard gates run before probability math; failed required gates return `0%`.
- Hard-gate failures show the rule, official/inferred status, explanation, and source when available.
- Inferred gates are labeled and lower confidence.
- Global gate rules are filtered by applicant status and major before they can block, warn, or lower confidence.
- Default profiles use `其他/手动评估学校` for high-school background so named-school proxy advantages are never applied by default.
- The unknown high-school fallback is validated as conservative and cannot carry a first-tier track-record boost.
- The form exposes both TOEFL and IELTS because either can satisfy the English proof gate.
- Curriculum-specific achievement inputs (AP, IB, A-Level, or Chinese curriculum scores) affect academic readiness and school fit.
- AP average score is counted only when AP course count is greater than 0.
- A-Level A*/A/B subject counts share a total cap of 5 subjects; overflow data is capped before scoring and disclosed as a warning.
- Academic benchmark rows may mix official class-profile fields with inferred fields; the app labels mixed rows explicitly.
- Transcript and Chinese-curriculum grades can be entered as percent scores, 4.0 GPA, 5.0 GPA, or letter grades; non-percent inputs are converted only to an internal academic index.
- School-specific test-free/test-blind policies, such as UC's SAT/ACT policy, are applied to both readiness scoring and target-school academic fit.
- SAT/ACT comparisons use the strongest submitted SAT-equivalent score through the official ACT/SAT concordance.
- Test Optional / 不提交标化 clears SAT/ACT in the form and ignores residual SAT/ACT values in readiness and academic fit.
- EA/ED does not receive a generic probability boost unless school-specific round policy data exists; missing round data is disclosed.
- School-specific round data separates allowed rounds from explicit probability advantages, so an allowed early round does not automatically create a boost.
- Chinese international applicants use a conservative ordinary-applicant prior instead of the raw overall admit rate, with round-specific China admit-count capacity caps when applicant denominators are missing.
- For top-decile students at first-tier Chinese international high schools, the model applies a separate strong-cohort calibration for non-T10 T30 schools so a 15-school T11-T30 portfolio can approach or exceed 90% at-least-one probability when no major negative condition applies. This calibration does not lift T10 capacity caps.
- That strong-cohort calibration is limited to National Universities; Liberal Arts Colleges keep separate LAC probabilities and are not lifted by the National Universities T11-T30 calibration without school/category-specific evidence.
- International financial-aid need is shown as a separate factor and does not penalize domestic/U.S. citizen applicants.
- Portfolio-level National Universities T10/T11-T30/T30/T50, Liberal Arts Colleges T10/T30, and overall probabilities mean the chance of being admitted to at least one school within the currently selected or auto-recommended set.
- Selected schools outside the v1 dataset are excluded from probability math and disclosed as portfolio warnings.
- Recommendation buckets use conservative planning thresholds: `争取` below 20%, `目标` 20%-60%, and `保底` at least 60%; `保底` is still not a guarantee.
- Auto recommendation is an explicit action: users choose one total school count and tap a button; when enough eligible schools exist, the generated count matches that number.
- Auto recommendation scores each eligible school by estimated admission probability × rank-value score and optimizes expected best-admit value with confidence/reliability discounting and same-tier correlation discounting. For app responsiveness, exact search is intentionally limited to small requested counts with a modest bounded total combination space; larger combination spaces use a bounded fast approximation with marginal greedy selection over a confidence-adjusted candidate window that also keeps rank-value and single-school-probability guardrails, plus deterministic one-school replacement passes over guarded candidate/removal shortlists, then keeps the best expected-value ordering among current, marginal-greedy, and rank-value-priority orderings.
- The explicit auto-recommend action carries the just-generated recommendation steps directly into the result, so large portfolios do not run the recommendation search twice.
- Rank-value scores use comparable fixed curves across comprehensive universities and liberal arts colleges, rather than scaling each list to its current last ranked school; Liberal Arts College T10 value is aligned near the comprehensive-university T20-T30 band.
- Automatic results show the expected best-admit value for the requested school count, alongside the per-school recommendation order, so multiple offers are not simply double-counted.
- Manual school selection opens a selectable / selected college directory and has no artificial count cap.
- Manual and empty portfolio results do not carry hidden auto-recommendation school lists.
- Results disclose the portfolio's likely / target / reach / blocked composition and any auto-recommendation total-count shortage.
- Automatic results carry the matching marginal expected-value steps so the result page and report explain the same recommendation order.
- Results include the per-school calculated probability list for every calculated school in the current portfolio.
- Paid AI reports are generated from a dedicated report page and include every selected or auto-recommended school's probability and academic-fit adjustment.
- AI reports for automatic portfolios explain the recommendation basis: single-school probability, rank-value score, confidence/reliability discounting, same-tier marginal discounting, and expected best-admit value.
- AI reports include each selected school's confidence label next to its probability.
- AI reports include a per-school source audit summary for the data used in probability math.
- The app tracks whether a portfolio is empty, manually selected, or auto-recommended so recommendation warnings do not appear on hand-built lists.
- AI reports include computed portfolio warnings and per-school data limitations instead of replacing them with generic advice.
- Report generation is wired to the OpenAI Responses API; Debug builds need an `OPENAI_API_KEY` environment variable, while production should use a server-side proxy rather than embedding secrets in the app.
- Results and AI reports are tied to the submitted profile snapshot; if the live form changes afterward, the app flags the displayed result as stale.
- Multi-school probability uses same-tier correlation discounting.
- Same-tier correlation discounting is strongest for T10 and lighter for non-T10 T30 portfolios, reflecting that 15 well-chosen T11-T30 applications should not be treated as only a few effective attempts.
- Comprehensive-university T10 and Liberal Arts College T10 schools share one extreme-selectivity correlation tier in combined portfolio probability and automatic recommendation value, so top-category outcomes are not treated as independent merely because the school type differs.
- The paid-report surface is wired as a StoreKit-ready placeholder and cannot modify computed probabilities.

## Build

```bash
xcodegen generate
```

Open `AdmissionCalculator.xcodeproj`, or build with XcodeBuildMCP / Xcode.

## Guardrails

See `harness.yaml` and `HARNESS.md`.

## Calculation Flow

See `docs/calculation-flow.md` for the maintained Mermaid flowchart covering hard gates, school-level probability adjustments, automatic recommendation expected-value selection, portfolio at-least-one probabilities, and user-supplied fields that materially affect the result.

## Data Update

The app consumes a generated offline Swift snapshot:

```bash
node scripts/update-admissions-data.mjs
node scripts/update-admissions-data.mjs --check
npm run data:verify
```

Edit the reviewed source files in `data/`, then regenerate:

- `data/admissionsight_colleges.csv`: allowed National Universities statistics seed. AdmissionSight remains the primary source; missing 2026 U.S. News T50 rows from IMG_0749.JPG are allowed only with official College Scorecard/IPEDS base-rate sources.
- `data/liberal_arts_colleges.csv`: allowed Top30 Liberal Arts Colleges list/rank seed extracted from the reviewed user-provided table, with current base rates replaced by reviewed official College Scorecard rows matched by UnitID.
- `data/official_gate_rules.csv`: official and inferred hard gates.
- `data/international_student_signals.csv`: undergraduate-only international data; admit coefficient is used only when undergraduate international admitted count and total admitted count are both available.
- `data/china_undergrad_admissions.csv`: China student undergraduate admit-count signal from reviewed table data.
- `data/china_high_schools.json`: China high school context proxy.
- `data/liberal_arts_unitids.json`: reviewed IPEDS/Scorecard UnitID map for official Liberal Arts College rate import.
- `data/source_registry.json`: source roles, confidence, and refresh notes.

The script rejects schools outside the approved v1 seeds and official gate rules without URLs.
It also validates numeric ranges for rates, ranks, proxy shares, data quality, and China early/RD totals before regenerating Swift data.

The calculator exposes a `纳入文理学院` switch. When it is off, auto recommendation, the manual college directory, Liberal Arts T10/T30 probability views, and the combined at-least-one probability all exclude Liberal Arts Colleges.

To prepare an official College Scorecard review file for Liberal Arts College base rates:

```bash
COLLEGE_SCORECARD_API_KEY=... npm run data:scorecard:lac
# or use the official downloaded Most-Recent-Cohorts-Institution.csv
npm run data:scorecard:lac -- --scorecard-csv /path/Most-Recent-Cohorts-Institution.csv
# or point directly at the official downloaded ZIP
npm run data:scorecard:lac -- --scorecard-zip /path/Most-Recent-Cohorts-Institution.zip
# official College Scorecard raw data ZIPs are also accepted; the latest MERGEDYYYY_YY_PP.csv is selected and disclosed in source_note
npm run data:scorecard:lac -- --scorecard-zip /path/College_Scorecard_Raw_Data.zip
# or pass an official Scorecard CSV/ZIP URL
npm run data:scorecard:lac -- --scorecard-url https://.../Most-Recent-Cohorts-Institution.csv-or.zip
# the current Scorecard download page may use ed-public-download.scorecard.network for official ZIP files
npm run data:scorecard:lac -- --scorecard-url https://ed-public-download.scorecard.network/downloads/<official-scorecard-file>.zip
# or let the script discover the current institution-level ZIP from the official Scorecard data page
npm run data:scorecard:lac -- --check-scorecard-latest-url
npm run data:scorecard:lac -- --scorecard-latest-url
# if the official page is blocked in this network, save the official page HTML and use it only to discover the official download URL
npm run data:scorecard:lac -- --scorecard-page-html /path/official-scorecard-data-page.html --scorecard-latest-url
# or use official NCES/IPEDS Admissions and Test Scores data instead
npm run data:ipeds:lac -- --adm-zip /path/ADM2024.zip
npm run data:ipeds:lac -- --adm-url https://.../ADM2024.csv-or.zip
# or use official NCES/IPEDS derived selectivity/admissions-yield data
npm run data:ipeds:lac -- --ipeds-csv /path/DRVADM2024.csv
npm run data:ipeds:lac -- --ipeds-url https://.../DRVADM2024.csv-or.zip
# or use official NCES/IPEDS Reported Data Admissions pages
npm run data:lac:official-urls -- --year 2024
npm run data:lac:official-urls:check
npm run data:ipeds:lac -- --reported-html-dir /path/nces-reported-admissions-html --year 2024
npm run data:ipeds:lac -- --reported-url-template 'https://nces.ed.gov/ipeds/reported-data/html/{unitid}?year={year}&surveyNumber=12&viewmode=print' --year 2024
npm run data:official:lac:apply -- --dry-run --official data/ipeds_liberal_arts_rates.csv
npm run data:official:lac:check
```

The first command writes a review CSV such as `data/scorecard_liberal_arts_rates.csv` or `data/ipeds_liberal_arts_rates.csv`. After checking official names when available, UNITIDs, and admission-rate fields (`ADM_RATE`, `ADMSSN / APPLCN`, derived IPEDS fields such as `DVADM01`, or NCES Reported Data `Percent admitted`), run `npm run data:official:lac:apply -- --official <review_csv>` to apply the reviewed rates to `data/liberal_arts_colleges.csv`, then regenerate with `npm run data:update`.
`npm run data:lac:official-urls` writes `data/lac_official_url_manifest.csv`, a manual-review helper listing each LAC's reviewed UnitID, College Scorecard school URL, NCES Reported Data Admissions URL, and expected local HTML filename. `npm run data:lac:official-urls:check` verifies the checked-in manifest is current. Use the same `--year` when generating the manifest and importing a local Reported Data HTML directory.
The Scorecard, IPEDS, and apply scripts all validate against `data/liberal_arts_unitids.json`; rows with mismatched UnitIDs, reviewed official school names, or official source URLs that point to a different UNITID/component are rejected before they can replace base rates. The generator also validates applied LAC seed rows directly, so manually editing `data/liberal_arts_colleges.csv` cannot claim official Scorecard/IPEDS provenance unless the source URL, UnitID, component, source note, and data-quality level remain consistent with the reviewed UnitID map. URL-based downloads require HTTPS and are limited to official College Scorecard or NCES/IPEDS hosts; local file inputs are allowed only through the explicit local CSV/ZIP/HTML flags after manual official-source review. Local Scorecard CSV files and ZIP contents must use official institution-level names such as `Most-Recent-Cohorts-Institution*.csv` or raw `MERGEDYYYY_YY_PP*.csv`; local IPEDS CSV/ZIP files must use official `ADMYYYY*` or `DRVADMYYYY*` filenames.
`npm run data:official:lac:check` runs local fixtures through Scorecard, official Scorecard data-page URL discovery, IPEDS ADM, IPEDS DRVADM, IPEDS Reported Data fetch/apply paths, and seed-level manual-edit guards, and confirms that mismatched UNITIDs, reviewed official names, unknown local Scorecard/IPEDS CSV/ZIP filenames, non-HTTPS URL downloads, nonofficial URL hosts, nonofficial discovery pages, mismatched source URLs, wrong Reported Data components, and inflated user-table data quality are rejected.
Live official downloads can fail for environmental reasons: College Scorecard requires a non-rate-limited data.gov API key, and NCES may reset direct HTTPS connections from some networks. In that case, download the official Scorecard, ADM, DRVADM, or NCES Reported Data HTML files manually from the official sites and pass the local CSV/ZIP/HTML path to the same scripts. Do not apply third-party mirrors as authoritative replacement data.
See `docs/lac-official-rate-import-status.md` for the current official LAC-rate import status, verified paths, and external access blockers.
Use `npm run data:verify` before shipping data changes; it runs the generated snapshot check, the official LAC URL manifest freshness check, and the LAC official-rate workflow check.
