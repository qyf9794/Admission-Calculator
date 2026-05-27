# Admission Calculator

SwiftUI iPhone app for estimating U.S. undergraduate admission chances for Chinese applicants.

The v1 model is intentionally transparent:

- AdmissionSight National Universities acceptance rates are the only school statistics seed.
- Hard gates run before probability math; failed required gates return `0%`.
- Inferred gates are labeled and lower confidence.
- Global gate rules are filtered by applicant status and major before they can block, warn, or lower confidence.
- The form exposes both TOEFL and IELTS because either can satisfy the English proof gate.
- Curriculum-specific achievement inputs (AP, IB, A-Level, or Chinese curriculum scores) affect academic readiness and school fit.
- AP average score is counted only when AP course count is greater than 0.
- Transcript and Chinese-curriculum grades can be entered as percent scores, 4.0 GPA, 5.0 GPA, or letter grades; non-percent inputs are converted only to an internal academic index.
- School-specific test-free/test-blind policies, such as UC's SAT/ACT policy, are applied to both readiness scoring and target-school academic fit.
- SAT/ACT comparisons use the strongest submitted SAT-equivalent score through the official ACT/SAT concordance.
- Chinese international applicants use a conservative ordinary-applicant prior instead of the raw overall admit rate, with round-specific China admit-count capacity caps when applicant denominators are missing.
- Portfolio-level T10/T30/T50 probabilities are scoped to the currently selected or auto-recommended school set.
- Selected schools outside the v1 dataset are excluded from probability math and disclosed as portfolio warnings.
- Auto recommendation is an explicit action: users choose likely / target / reach counts and tap a button to populate the school set.
- Results disclose the portfolio's likely / target / reach / blocked composition and any auto-recommendation bucket shortages.
- The app tracks whether a portfolio is empty, manually selected, or auto-recommended so recommendation warnings do not appear on hand-built lists.
- Results and AI reports are tied to the submitted profile snapshot; if the live form changes afterward, the app flags the displayed result as stale.
- Multi-school probability uses same-tier correlation discounting.
- The paid-report surface is wired as a StoreKit-ready placeholder and cannot modify computed probabilities.

## Build

```bash
xcodegen generate
```

Open `AdmissionCalculator.xcodeproj`, or build with XcodeBuildMCP / Xcode.

## Guardrails

See `harness.yaml` and `HARNESS.md`.

## Data Update

The app consumes a generated offline Swift snapshot:

```bash
node scripts/update-admissions-data.mjs
node scripts/update-admissions-data.mjs --check
```

Edit the reviewed source files in `data/`, then regenerate:

- `data/admissionsight_colleges.csv`: only allowed school statistics seed.
- `data/official_gate_rules.csv`: official and inferred hard gates.
- `data/international_student_signals.csv`: undergraduate-only international data; admit coefficient is used only when undergraduate international admitted count and total admitted count are both available.
- `data/china_undergrad_admissions.csv`: China student undergraduate admit-count signal from reviewed table data.
- `data/china_high_schools.json`: China high school context proxy.
- `data/source_registry.json`: source roles, confidence, and refresh notes.

The script rejects schools outside the AdmissionSight seed and official gate rules without URLs.
It also validates numeric ranges for rates, ranks, proxy shares, data quality, and China early/RD totals before regenerating Swift data.
