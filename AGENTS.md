# AGENTS.md

Guidance for future Codex sessions working in this repository.

## First Step

Before making plans or edits, read:

- `harness.yaml`
- `HARNESS.md`
- `README.md`

Treat `harness.yaml` and `HARNESS.md` as the project contract. If a user request conflicts with them, explain the conflict and ask before changing the contract.

## Product Goal

Build a SwiftUI iPhone app that estimates U.S. undergraduate admission chances for Chinese applicants as objectively and realistically as the available data allows.

The app must be useful for planning, but it must never imply certainty. Outputs are estimates, not predictions or promises.

## Core Rules

- Hard gates run before probability math. If an official required condition is unmet, that school probability is `0%`.
- Use only the AdmissionSight college list/rank/acceptance-rate table as the v1 school statistics scope.
- Use undergraduate data only. Do not mix graduate, all-level, or SEVIS active-student counts into undergraduate admission probability.
- CollegeVine is a reference for field categories and transparent chancing concepts only. Do not copy proprietary formulas, weights, or scores.
- AdmitRanking-style high-school context is a calibration proxy only, not proof of individual outcome.
- AI reports may explain computed results and suggest strategy, but must not change probabilities, add schools outside scope, or guarantee admission.
- For arts applicants, reduce academic/test emphasis and respect portfolio requirements.
- For international and Chinese applicant adjustments, disclose when data is missing, proxy-based, or not school-specific.

## Objectivity Standard

Prefer official school admissions pages, Common Data Set, IPEDS, or reviewed source tables. When data is missing:

- Do not invent precision.
- Use conservative proxy logic only when it is documented.
- Mark inferred values explicitly.
- Lower confidence.
- Add user-facing warnings.
- Ask the user for data if the missing field would materially change the result.

Never present inferred GPA, class rank, SAT/ACT, course rigor, international share, or China admit-count data as official admitted-student averages unless the source proves that exact scope.

## Data Update Workflow

Reviewed data lives in `data/`. Generated Swift data lives in:

- `AdmissionCalculator/Data/AdmissionsNormalizedData.swift`

After changing source data or the generator:

1. Run `npm run data:update`.
2. Run `npm run data:check`.
3. Run iOS tests with XcodeBuildMCP.

Do not manually edit generated Swift data unless the generator is broken and the change is temporary and clearly documented.

## Probability Model Expectations

The model should remain explainable:

- Start from the school base acceptance rate.
- Apply hard-gate failure first.
- Adjust only after gates pass.
- Keep each adjustment bounded.
- Show factors, warnings, and confidence.
- Multi-school “at least one” probability must account for correlated outcomes among similarly selective schools.

For target-school academic fit, compare the applicant's GPA, class rank, SAT/ACT, and course rigor against school-level benchmarks. If those benchmarks are inferred, label them as inferred and keep their impact modest.

## Verification

Before handing work back, verify the relevant path:

- Data changes: `npm run data:check`
- Model changes: unit tests for directionality, hard-gate behavior, warnings, and probability bounds
- UI changes: build/test with the active simulator

If tests cannot be run, say so clearly and explain the residual risk.
