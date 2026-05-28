# Admission Calculator Harness

This app estimates U.S. undergraduate admission chances for Chinese applicants.
The result is an explainable estimate, not a promise of admission.

## Non-Negotiable Rules

- Use AdmissionSight National Universities plus the reviewed user-provided 2026 U.S. News T50 National Universities image supplement and the reviewed user-provided Top30 Liberal Arts Colleges list/rank table as the only v1 school scope; supplemental National University rows and LAC base rates may be added or replaced only by reviewed official Scorecard/IPEDS rows matched to exact school identity.
- Treat CollegeVine as a product/modeling reference for fields and explanation style, not as a copied formula.
- Use AdmitRanking-style Chinese high-school context only as a calibration signal.
- Default and sample profiles must use the conservative `其他/手动评估学校` high-school context unless the user explicitly selects a known school.
- The `unknown` high-school fallback must remain conservative: band 3 or weaker, resources/counseling/transparency no higher than 3, and Top 30 track record no higher than 2.
- Run hard gates before probability math. If a required rule is not met, the school result is `0%`.
- Hard-gate failures must disclose the rule title, official/inferred status, explanatory detail, and source when available.
- Clearly mark inferred gate rules and lower confidence when official sources are missing.
- Only applicable gate rules may be checked, disclosed, or used to lower confidence; irrelevant global rules must not penalize unrelated applicants.
- AI reports may explain and advise, but may not modify computed probabilities or add schools.
- App data must be generated from reviewed source files in `data/` using `scripts/update-admissions-data.mjs`.
- The generated Swift snapshot must remain reproducible with `node scripts/update-admissions-data.mjs --check`.
- Source data validation must reject out-of-range rates, ranks, proxy shares, data-quality scores, and China early/RD counts that do not reconcile to totals.
- Source data validation must also require `data/liberal_arts_unitids.json` to cover exactly the reviewed Liberal Arts College rows with unique six-digit UNITIDs.
- `npm run data:official:lac:check` must validate that Scorecard institution CSV, Scorecard raw CSV/ZIP, IPEDS ADM-style, IPEDS DRVADM-style, and IPEDS Reported Data Admissions HTML LAC official-rate workflows accept UNITID-matched rows, that official Scorecard data-page HTML discovery finds the current institution-level download URL and rejects pages without one, that raw Scorecard ZIP parsing selects the latest `MERGEDYYYY_YY_PP.csv` and discloses the selected CSV in review-row and applied seed source notes, that local Scorecard CSV/ZIP and IPEDS CSV/ZIP parsing reject unknown CSV filenames even if they contain plausible official-looking columns, that Scorecard URL validation accepts the current official `ed-public-download.scorecard.network` host, that URL-based downloads reject non-HTTPS, nonofficial hosts, official data-page discovery URLs outside `collegescorecard.ed.gov/data/`, and official-host URLs that do not point to an institution CSV/ZIP or raw Scorecard ZIP, that the manual official URL manifest is generated from the same UnitID map, that mismatched UnitIDs, reviewed official school names, or mismatched per-row official source URLs are rejected before replacement, and that direct manual edits to `data/liberal_arts_colleges.csv` cannot claim official Scorecard/IPEDS sources unless the source URL, UnitID, component, source note, and data-quality level are consistent with the reviewed UnitID map.
- `npm run data:verify` must run the generated snapshot check, the checked-in official LAC URL manifest freshness check, and the LAC official-rate workflow check.
- The data UI must expose per-school source audit notes for acceptance rates, undergraduate international signals, China undergraduate admit counts, academic benchmarks, and gate rules.
- Per-school source audit must disclose structured round policy fields, including allowed rounds and any explicit EA/ED probability adjustments.
- International student fields must be undergraduate-only. Never use graduate or all-level international data in probability math.
- International admit coefficient may be used only when undergraduate international admitted count and total admitted count are both present.
- International financial-aid policy may affect international applicants who request aid, but it must be a separate disclosed factor and must not penalize domestic/U.S. citizen applicants.
- China student admit-count data may adjust China applicant estimates, but may not be labeled as a share of all admits unless all-admit totals are present.
- For Chinese international applicants, the model must not use the raw overall school admit rate as the final prior. It must apply ordinary-applicant calibration for international status, hooked-seat dilution at highly selective schools, and round-specific China admit-count capacity caps when China applicant denominators are missing.
- T10/T11-T30/T30/T50 portfolio probabilities must describe only the currently selected or auto-recommended application portfolio. T11-T30 must be shown separately from the traditional T30-including-T10 view. Do not display all-dataset tier probabilities as if the applicant planned to apply to every school in that tier.
- Selected schools outside the approved v1 dataset must be excluded from probability math and disclosed in portfolio-level warnings.
- 文理学院必须作为可开关的独立学校选项进入选校范围。开启时，选校列表可选择文理学院，计算后必须分别显示“文理学院 T10 至少一所”和“文理学院 T30 至少一所”的录取概率，并把这些已选文理学院同步纳入“全部已选至少一所”的综合概率；关闭时，自动推荐、手动目录、T10/T30 文理学院概率和综合至少一所概率都不得纳入文理学院。
- Recommendation buckets must use conservative planning thresholds: `争取` below 20%, `目标` from 20% to below 60%, and `保底` at 60% or higher. The UI and AI report must disclose that `保底` is not a guarantee.
- Automatic school recommendations must be triggered by an explicit user action and must respect the user-requested total school count as far as eligible schools are available. Manual selection has no artificial count cap. An empty selected-school set must not silently become an auto-recommended portfolio.
- Automatic school recommendations must not select only by admission probability or fixed bucket quotas. Each eligible school receives a rank-value score, and recommendation should maximize expected best-admit value: estimated admission probability × rank-value score, with confidence/reliability discounting, same-tier correlation discounting, and no double-counting of multiple offers. For app responsiveness, exact search is intentionally limited to small requested counts with a modest bounded total combination space; recommendation quality should favor fast, deterministic approximation over maximum mathematical precision. When the exact limit is met, recommendation may use deterministic exhaustive search for the highest expected best-admit value, using the same best-ordering comparison for each candidate combination. For larger combination spaces, it should use a fast approximation: marginal greedy selection over a bounded confidence-adjusted candidate window with rank-value and single-school-probability guardrails, followed by bounded deterministic one-school replacement passes over the same kind of guarded candidate shortlist and a fixed-size removal shortlist; each accepted replacement must improve the selected portfolio's expected best-admit value. Replacement trials and final ordering may compare current, marginal-greedy, and rank-value-priority orderings, then keep the ordering with the highest expected best-admit value without expanding into exhaustive search.
- Rank-value scores must use comparable fixed curves across comprehensive universities and liberal arts colleges, so a rank-30 liberal arts college is not pushed to the floor merely because the LAC seed list currently stops at 30. Liberal Arts College T10 rank value should sit near the comprehensive-university T20-T30 band, not the comprehensive-university T10 band.
- Automatic recommendation results must expose the selected portfolio's expected best-admit value, not only the per-school order, so users can understand the value being optimized for the requested school count.
- 同层相关性折扣必须区分极端选择性和非 T10 T30 组合：T10 仍强相关、强保守；T11-T30 组合不能按极端 T10 逻辑过度折扣。对一流国际学校 top10% 中国籍国际生，若选择约 15 所综合大学 T11-T30 且无硬门槛/资助/专业重大负面条件，T30 至少一所概率应接近或超过 90%；该校准不得同步抬高 T10 单校上限。
- 综合大学 T10 与文理学院 T10 在综合至少一所概率和自动推荐期望值中必须共享同一个极端选择性相关性层；不能因为学校类别不同而把顶尖校结果当作相互独立。
- 上述一流高中强队列校准仅适用于综合大学路径；文理学院缺少同等中国籍录取分母与校准样本时，不得套用综合大学 T11-T30 的强队列抬升。
- Portfolio results must carry recommended schools only for explicit automatic recommendation results; manual and empty portfolios must not include hidden recommendation lists.
- Results and AI reports must disclose the current portfolio's likely / target / reach / blocked composition, and must warn when the auto-recommendation pool cannot satisfy the requested total school count.
- Automatic portfolio results should carry the exact marginal expected-value recommendation steps when the current school set still matches the submitted profile snapshot, so the result page and report can explain the same order.
- Supplied automatic recommendation steps may be reused only when they match the current school results and the regenerated automatic recommendation order/value metadata for the submitted profile snapshot; self-consistent but differently ordered supplied steps must be ignored.
- The app's explicit auto-recommend action may use a single engine path that generates recommendation steps once and carries those same steps into the result, avoiding a second large-portfolio recommendation pass.
- Result pages must show per-school calculated probabilities for every calculated school in the selected or auto-recommended portfolio; the per-school result count must match the calculated school count after exclusions.
- AI reports must include probability and academic-fit lines for every school in the current selected or auto-recommended portfolio, not only a shortened preview.
- AI reports for automatic portfolios must explain that recommendation uses probability × rank-value score with confidence/reliability discounting, same-tier marginal discounting, and expected best-admit value, not raw probability sorting.
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
- A-Level A*/A/B 科目数必须共享最多 5 门的总上限；UI 不得允许三个成绩档各自独立填 5 门，模型也必须对异常溢出数据截断并披露。
- Percent, 4.0 GPA, 5.0 GPA, and letter-grade inputs may be normalized only into an internal academic index. The UI, warnings, and report language must not present that index as a true cross-system percentage conversion.

## Probability Path

1. Validate the selected school exists in the approved dataset.
2. Run the hard-gate checker against official and inferred requirements.
3. If any required gate fails, return `0%` and show the failed rules.
4. If gates pass, compute a school-aware student readiness score from hard, soft, school-context, and strategy signals, respecting official test-free/test-blind policies.
5. Convert the school's latest available acceptance rate into an ordinary-applicant prior. For Chinese international applicants, discount this prior for international data availability, highly selective hooked-seat dilution, and round-specific China admit-count capacity.
6. Adjust the prior using readiness, school-specific academic benchmark fit, high-school context, applicant status, undergraduate international signals, major competition, round, aid, and China trend signals.
7. Compute at-least-one probabilities with same-tier correlation discounting, including separate National Universities T10/T11-T30/T30/T50 and Liberal Arts Colleges T10/T30 views plus the combined selected-school view.
8. Display confidence, warnings, and data-source notes.

## Data Update Path

1. Review or update `data/admissionsight_colleges.csv` for National Universities and `data/liberal_arts_colleges.csv` for the reviewed Top30 Liberal Arts Colleges list/rank scope. National Universities are normally seeded from AdmissionSight; missing 2026 U.S. News T50 schools may be added only when the rank/list comes from reviewed IMG_0749.JPG and the base acceptance rate comes from official College Scorecard or IPEDS school data. LAC base-rate rows may stay as reviewed user-table proxy rows only when clearly labeled and `data_quality <= 0.8`, or may use official Scorecard/IPEDS replacement rows only after UnitID review with `data_quality >= 0.85`.
   - Before replacing Liberal Arts College base rates, run either `npm run data:scorecard:lac` with `COLLEGE_SCORECARD_API_KEY`, `--scorecard-latest-url`, `--scorecard-page-html <official College Scorecard data page HTML> --scorecard-latest-url`, `--scorecard-csv`, `--scorecard-zip`, or `--scorecard-url`, or run `npm run data:ipeds:lac` with an official NCES/IPEDS `ADM` or `DRVADM` CSV/ZIP path or URL, or use official NCES Reported Data Admissions pages with `--reported-html-dir` / `--reported-url-template`. The LAC official-data tools must match schools through `data/liberal_arts_unitids.json`, not loose name matching. Manually review the generated official-rate CSV against UNITIDs, names when available, and admission-rate fields (`latest.admissions.admission_rate.overall` / `ADM_RATE`, `ADMSSN / APPLCN`, derived fields such as `DVADM01`, or Reported Data `Percent admitted`). Then run `npm run data:official:lac:apply -- --dry-run --official <review_csv>` before applying the reviewed rates.
   - If live NCES/Scorecard downloads are blocked, run `npm run data:lac:official-urls -- --year <year>` to generate a UnitID-keyed official URL manifest for manual official-page download, then rerun `npm run data:ipeds:lac -- --reported-html-dir <dir>`.
   - Run `npm run data:official:lac:check` after editing the LAC official-rate scripts or UnitID map.
2. Review `data/official_gate_rules.csv`; official rules require source URLs and unmet official rules block probability.
3. Review `data/international_student_signals.csv`; rows must be undergraduate-only, and missing admit coefficients must be explicit.
4. Review `data/china_undergrad_admissions.csv`; China admitted counts require source notes and cannot imply all-admit share without a denominator.
5. Review `data/academic_benchmarks.csv`; replace inferred proxy rows with official CDS/class profile values whenever available.
6. Update `data/china_high_schools.json` only as a disclosed proxy.
7. Run `node scripts/update-admissions-data.mjs` to regenerate `AdmissionCalculator/Data/AdmissionsNormalizedData.swift`.
8. Run `npm run data:verify` and the unit tests before shipping.

## Validation Standard

The app is acceptable when a user can understand why a school is blocked,
why a probability is low or high, and which data is missing or inferred.
No UI or report may present the estimate as objective certainty.
