# Admission Calculator Harness

This app estimates U.S. undergraduate admission chances for Chinese applicants.
The result is an explainable estimate, not a promise of admission.

## Non-Negotiable Rules

- Use the AdmissionSight National Universities acceptance-rate table as the only v1 college statistics seed.
- Treat CollegeVine as a product/modeling reference for fields and explanation style, not as a copied formula.
- Use AdmitRanking-style Chinese high-school context only as a calibration signal.
- Run hard gates before probability math. If a required rule is not met, the school result is `0%`.
- Clearly mark inferred gate rules and lower confidence when official sources are missing.
- AI reports may explain and advise, but may not modify computed probabilities or add schools.
- App data must be generated from reviewed source files in `data/` using `scripts/update-admissions-data.mjs`.
- The generated Swift snapshot must remain reproducible with `node scripts/update-admissions-data.mjs --check`.
- International student fields must be undergraduate-only. Never use graduate or all-level international data in probability math.
- International admit coefficient may be used only when undergraduate international admitted count and total admitted count are both present.
- China student admit-count data may adjust China applicant estimates, but may not be labeled as a share of all admits unless all-admit totals are present.
- For Chinese international applicants, the model must not use the raw overall school admit rate as the final prior. It must apply ordinary-applicant calibration for international status, hooked-seat dilution at highly selective schools, and round-specific China admit-count capacity caps when China applicant denominators are missing.
- T10/T30/T50 portfolio probabilities must describe only the currently selected or auto-recommended application portfolio. Do not display all-dataset tier probabilities as if the applicant planned to apply to every school in that tier.
- Automatic school recommendations must be triggered by an explicit user action and must respect user-requested likely / target / reach counts as far as eligible schools are available. If a bucket has too few eligible schools, do not silently fill it from another bucket. An empty selected-school set must not silently become an auto-recommended portfolio.
- Global inferred English floor is TOEFL 90 or IELTS 6.5 unless an official school-specific rule says otherwise.
- ACT scores must be converted with the official ACT/College Board 2018 ACT/SAT concordance midpoint table, not a linear approximation.
- UC campuses must not accept EA or ED as valid first-year rounds; they use the UC first-year filing period and should be treated as the regular application round in this app.
- Arts applicants use a separate profile-weighting path with lower academic/standardized-test weight and higher portfolio-adjacent soft-signal weight; missing portfolio remains a blocking gate.
- School-specific academic benchmarks may adjust probability only after hard gates pass. Inferred GPA/rank/test/rigor benchmarks must be labeled and cannot be presented as official admitted-student averages.
- Curriculum selection must expose curriculum-specific achievement inputs (AP, IB, A-Level, or Chinese curriculum scores) and those inputs must affect academic readiness and school-specific fit.
- Percent, 4.0 GPA, 5.0 GPA, and letter-grade inputs may be normalized only into an internal academic index. The UI, warnings, and report language must not present that index as a true cross-system percentage conversion.

## Probability Path

1. Validate the selected school exists in the approved dataset.
2. Run the hard-gate checker against official and inferred requirements.
3. If any required gate fails, return `0%` and show the failed rules.
4. If gates pass, compute a student readiness score from hard, soft, school-context, and strategy signals.
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
