# Admission Calculator Harness

This app estimates U.S. undergraduate admission chances for Chinese applicants.
The result is an explainable estimate, not a promise of admission.

## Non-Negotiable Rules

- Use the AdmissionSight National Universities acceptance-rate table as the only v1 college statistics seed.
- Treat CollegeVine as a product/modeling reference for fields and explanation style, not as a copied formula.
- Use AdmitRanking-style Chinese high-school context only as a calibration signal.
- Default and sample profiles must use the conservative `其他/手动评估学校` high-school context unless the user explicitly selects a known school.
- Run hard gates before probability math. If a required rule is not met, the school result is `0%`.
- Hard-gate failures must disclose the rule title, official/inferred status, explanatory detail, and source when available.
- Clearly mark inferred gate rules and lower confidence when official sources are missing.
- Only applicable gate rules may be checked, disclosed, or used to lower confidence; irrelevant global rules must not penalize unrelated applicants.
- AI reports may explain and advise, but may not modify computed probabilities or add schools.
- App data must be generated from reviewed source files in `data/` using `scripts/update-admissions-data.mjs`.
- The generated Swift snapshot must remain reproducible with `node scripts/update-admissions-data.mjs --check`.
- Source data validation must reject out-of-range rates, ranks, proxy shares, data-quality scores, and China early/RD counts that do not reconcile to totals.
- The data UI must expose per-school source audit notes for acceptance rates, undergraduate international signals, China undergraduate admit counts, academic benchmarks, and gate rules.
- International student fields must be undergraduate-only. Never use graduate or all-level international data in probability math.
- International admit coefficient may be used only when undergraduate international admitted count and total admitted count are both present.
- International financial-aid policy may affect international applicants who request aid, but it must be a separate disclosed factor and must not penalize domestic/U.S. citizen applicants.
- China student admit-count data may adjust China applicant estimates, but may not be labeled as a share of all admits unless all-admit totals are present.
- For Chinese international applicants, the model must not use the raw overall school admit rate as the final prior. It must apply ordinary-applicant calibration for international status, hooked-seat dilution at highly selective schools, and round-specific China admit-count capacity caps when China applicant denominators are missing.
- T10/T30/T50 portfolio probabilities must describe only the currently selected or auto-recommended application portfolio. Do not display all-dataset tier probabilities as if the applicant planned to apply to every school in that tier.
- Selected schools outside the approved AdmissionSight v1 dataset must be excluded from probability math and disclosed in portfolio-level warnings.
- Recommendation buckets must use conservative planning thresholds: `争取` below 20%, `目标` from 20% to below 60%, and `保底` at 60% or higher. The UI and AI report must disclose that `保底` is not a guarantee.
- Automatic school recommendations must be triggered by an explicit user action and must respect user-requested likely / target / reach counts as far as eligible schools are available. If a bucket has too few eligible schools, do not silently fill it from another bucket. An empty selected-school set must not silently become an auto-recommended portfolio.
- Portfolio results must carry recommended schools only for explicit automatic recommendation results; manual and empty portfolios must not include hidden recommendation lists.
- Results and AI reports must disclose the current portfolio's likely / target / reach / blocked composition, and must warn when the auto-recommendation pool cannot satisfy a requested bucket count.
- AI reports must include probability and academic-fit lines for every school in the current selected or auto-recommended portfolio, not only a shortened preview.
- AI reports must include each selected school's computed confidence label next to its probability so uncertainty is not lost outside the results UI.
- AI reports must include each selected school's source-audit summary for acceptance rates, undergraduate international signals, China undergraduate admit counts, academic benchmarks, and gate rules.
- Auto-recommendation shortage warnings must be shown only for an auto-recommended portfolio, not for a manually selected school list.
- AI reports must include computed portfolio-level warnings and per-school warnings/data limitations; generic advice is not enough to satisfy disclosure.
- Result pages and AI reports must use the submitted profile snapshot that produced the probabilities. If the live form or selected schools change after calculation, the results view must disclose that the displayed probabilities are stale until recalculated.
- Report generation must derive the applicant summary from `PortfolioResult.profileSnapshot`; it must not accept a separate live `StudentProfile` that could diverge from the computed probabilities.
- The application form must expose both TOEFL and IELTS inputs because the English gate accepts either proof route.
- ACT-derived testing scores must use the same official concordance mapping as ACT-derived SAT gate checks.
- Global inferred English floor is TOEFL 90 or IELTS 6.5 unless an official school-specific rule says otherwise.
- ACT scores must be converted with the official ACT/College Board 2018 ACT/SAT concordance midpoint table, not a linear approximation.
- When both SAT and ACT are submitted, standardized-test gates, readiness scoring, and academic benchmark fit must use the strongest SAT-equivalent submitted score, not whichever field happens to be read first.
- When the user chooses Test Optional / not submitting scores, residual SAT/ACT values must not improve readiness or academic benchmark fit; test-required gates may still block the school.
- EA/ED must not receive a generic probability boost without school-specific round policy data; missing school-level round data must be disclosed instead of generalized.
- School-specific round data must distinguish allowed rounds from explicit probability advantages; allowing EA or ED does not by itself create a boost.
- UC campuses must not accept EA or ED as valid first-year rounds; they use the UC first-year filing period and should be treated as the regular application round in this app.
- School-specific test-free/test-blind policies must remove SAT/ACT from both the student readiness score and academic benchmark fit for that school; they must not merely leave SAT/ACT benchmarks blank.
- Arts applicants use a separate profile-weighting path with lower academic/standardized-test weight and higher portfolio-adjacent soft-signal weight; missing portfolio remains a blocking gate.
- School-specific academic benchmarks may adjust probability only after hard gates pass. Inferred GPA/rank/test/rigor benchmarks must be labeled and cannot be presented as official admitted-student averages.
- If an academic benchmark row mixes official class-profile fields with inferred fields, UI and reports must disclose that mixed scope rather than labeling the whole row as fully official or fully inferred.
- Curriculum selection must expose curriculum-specific achievement inputs (AP, IB, A-Level, or Chinese curriculum scores) and those inputs must affect academic readiness and school-specific fit.
- Curriculum-specific achievement inputs must not award performance credit without evidence: for example, AP average score is ignored when AP course count is 0.
- Percent, 4.0 GPA, 5.0 GPA, and letter-grade inputs may be normalized only into an internal academic index. The UI, warnings, and report language must not present that index as a true cross-system percentage conversion.

## Probability Path

1. Validate the selected school exists in the approved dataset.
2. Run the hard-gate checker against official and inferred requirements.
3. If any required gate fails, return `0%` and show the failed rules.
4. If gates pass, compute a school-aware student readiness score from hard, soft, school-context, and strategy signals, respecting official test-free/test-blind policies.
5. Convert the school's latest available acceptance rate into an ordinary-applicant prior. For Chinese international applicants, discount this prior for international data availability, highly selective hooked-seat dilution, and round-specific China admit-count capacity.
6. Adjust the prior using readiness, school-specific academic benchmark fit, high-school context, applicant status, undergraduate international signals, major competition, round, aid, and China trend signals.
7. Compute at-least-one probabilities with same-tier correlation discounting.
8. Display confidence, warnings, and data-source notes.

## Data Update Path

1. Review or update `data/admissionsight_colleges.csv`; this remains the only school statistics source.
2. Review `data/official_gate_rules.csv`; official rules require source URLs and unmet official rules block probability.
3. Review `data/international_student_signals.csv`; rows must be undergraduate-only, and missing admit coefficients must be explicit.
4. Review `data/china_undergrad_admissions.csv`; China admitted counts require source notes and cannot imply all-admit share without a denominator.
5. Review `data/academic_benchmarks.csv`; replace inferred proxy rows with official CDS/class profile values whenever available.
6. Update `data/china_high_schools.json` only as a disclosed proxy.
7. Run `node scripts/update-admissions-data.mjs` to regenerate `AdmissionCalculator/Data/AdmissionsNormalizedData.swift`.
8. Run `node scripts/update-admissions-data.mjs --check` and the unit tests before shipping.

## Validation Standard

The app is acceptable when a user can understand why a school is blocked,
why a probability is low or high, and which data is missing or inferred.
No UI or report may present the estimate as objective certainty.
