# Major Selectivity Data Audit

Last reviewed: 2026-06-07

## Purpose

This note organizes public base numbers for school-specific strong-major
selectivity, especially cases where the global major adjustment is too coarse.
The reviewed rows now live in `data/major_selectivity_signals.csv` and are
generated into `AdmissionsNormalizedData.swift`.

Current model behavior:

- Computer Science receives one global competition adjustment: `-0.26`.
- Engineering receives one global competition adjustment: `-0.18`.
- Business receives one global competition adjustment: `-0.12`.
- Nursing receives one global competition adjustment: `-0.16`.
- Film / Media / Design receives one global competition adjustment: `-0.08`.
- Architecture receives one global competition adjustment: `-0.06`.
- Aviation receives one global competition adjustment: `-0.10`.
- The model applies a separate bounded "学校强专业" correction only when a
  reviewed row matches the school, major category, and applicant scope.
- Nursing is intentionally a standalone category. It is not merged into broad
  health/pre-med categories because nursing programs can have far lower
  first-year admit rates than other health-related pathways.

## Source Standard

Use a source as a direct school-major signal only when it is:

- Undergraduate first-year scope.
- School, college, or major specific.
- Clear about whether the metric is applications, admits, admit rate, enrolled
  class size, or available seats.
- Official or institutionally published where possible.

If the source gives capacity or enrollment but not admits/applications, use it
only as a proxy and lower confidence. Do not present it as an official admit
rate.

Secondary sources may be used to widen coverage, but they should be tagged
separately:

- `official`: admissions office, institutional research, CDS, UC dashboards, or
  school fact sheets.
- `institution_adjacent`: campus newspaper, school-hosted presentation, or
  data journalism that cites institutional data.
- `reputable_secondary`: education/admissions publications with a data table or
  stated methodology, such as Poets&Quants or College Transitions.
- `consultant_estimate`: admissions-consulting estimates. Use as a search lead
  or weak proxy only.
- `forum_or_unsourced`: do not use for model data.

## Initial Findings

| School | Strong-major area | Public base numbers found | Data strength | Recommended model use |
| --- | --- | --- | --- | --- |
| UIUC | Computer Science | Official 2025 first-year admit rate page reports total admit rate 36.6%, first-choice admit rate 30.2%, Computer Science 7.4%, and Computer Science + X 17.4%. | High | Direct school-major adjustment candidate for pure CS and CS+X. This is the cleanest example found in this pass. |
| UIUC | Engineering | Official 2025 first-year admit rate page reports Grainger College of Engineering 21.2%. | High | Direct college-level adjustment candidate for engineering. |
| UIUC | Business | Official 2025 first-year admit rate page reports Gies College of Business 20.9%. | High | Direct college-level adjustment candidate for business. |
| UCLA | Nursing, film, arts, engineering, CS | Official Fall 2025 first-year profile reports overall admit rate 9.4%; Nursing Prelicensure 0.5%; Film and Television 1.3%; Design Media Arts 3.1%; Mechanical Engineering 3.9%; Computer Engineering 4.7%; Computer Science 7.3%; Computer Science and Engineering 7.2%; Samueli Engineering overall 6.8%. | High | Direct school-major adjustment candidate. UCLA is a strong source because it publishes major-level applicants, admit rates, and GPA ranges. |
| UC Berkeley | Engineering / EECS-adjacent | Berkeley Engineering official brochure reports College of Engineering first-year admit rate 6% for 2023-24; UC Admissions reports Berkeley campus overall admit rate 11.4%. The brochure lists EECS among engineering majors but does not provide an EECS-specific first-year admit rate. | Medium/high | Direct college-level engineering adjustment candidate; do not infer EECS-specific rate from the college-level 6%. |
| University of Washington | CS/CE | UW official first-year numbers report overall 3-year average admit rates of 47% for Washington residents and 39% for non-Washington residents. For Direct to Major CS/CE, the 3-year average admit rate is 30% for Washington residents and 2% for non-Washington residents. | High | Direct school-major adjustment candidate, especially for nonresident/international CS/CE applicants. |
| University of Michigan | Ross/business | Michigan Ross first-year applicant page reports Fall 2025 admitted profile: 13,019 applicants and 924 admitted students, about 7.1% implied admit rate. Ross is a first-year admitting unit. | High | Direct school-business adjustment candidate. Compute rate from same-page applicants/admitted counts and store the source note. |
| Georgia Tech | CS / computational media | Georgia Tech College of Computing reports Fall 2025 cycle data: 13,711 applications for CS/CM combined and 1,547 first-year offers for CS/CM, about 11.3% implied. It also says Computing's admission rate is lower than Georgia Tech's already low overall rate. | Medium/high | Direct-ish CS/CM signal, but because it combines CS and computational media and includes Summer/Fall offers, label scope carefully. |
| Purdue | Competitive majors | Purdue official class profile reports university admit rate 43.4%, College of Engineering 34.7%, College of Science 46%, Daniels School of Business 45.9%, Flight 7.7%, Computer Science 42.9%, Nursing 28.9%. | High | Engineering, Nursing, and Flight may be lower than overall; Computer Science should not receive an extra school-specific penalty from this source because its reported admit rate is close to Purdue overall. |
| USC | Viterbi / Marshall / arts | USC official quick facts say all majors have about the same admit rate, though they vary in size. USC's 2025-26 profile reports overall admission rate 11.2% and academic program distribution, but not lower school-specific admit rates. | High negative evidence | Do not add Viterbi or Marshall as lower-admit-rate special cases without stronger official evidence. Portfolio/audition majors may still have separate requirements, but not a lower-rate override from this source. |
| CMU | School of Computer Science | CMU official CDS/admission-rate materials report Fall 2024 first-year total applicants about 33,941/33,942, admits 3,959, and overall admit rate about 11.66%/11.7%. CMU's SCS fact sheet reports 257 students in the 2024 incoming class. No public SCS first-year admit rate, SCS applicant count, or SCS admit count was found in this pass. | Medium proxy | Do not use as an official SCS admit-rate override. Use as a low-confidence strong-major capacity proxy only if a school-major table is added. |
| CMU | Tepper/business | CMU Tepper fact sheet reports 171 students in the 2024 incoming class. No public undergraduate Tepper applicant/admit denominator was found in this pass. | Low/medium proxy | Capacity proxy only, not an official admit-rate override. |
| NYU | Stern/business | NYU Stern by-the-numbers page reports Class of 2029 program applications 21,900 and available spots 630; older Class of 2028 page reports 19,000 applications and 600 spots. This is not the same as an admit rate because yield is not given. | Medium proxy | Strong business proxy for demand and seat scarcity. Use cautiously; label as capacity/applicant-volume proxy. |
| NYU | Overall university baseline | Existing app seed has NYU overall class rates from AdmissionSight, including 7.70% for Class of 2029 and 8.00% for Class of 2028. | Existing v1 base | Keep as university base rate. Do not infer Stern admit rate directly from 630 spots / 21,900 applications. |

## Secondary-Source Expansion

These sources are not the preferred official path, but they help identify where
school-major corrections are likely needed.

| School | Strong-major area | Secondary data found | Source tier | Recommended use |
| --- | --- | --- | --- | --- |
| Penn | Wharton/business | Poets&Quants reports Wharton acceptance rate 4.5% for the fall 2024 incoming class. College Transitions has also listed Wharton near 7% in an older undergraduate business-rate table. | Reputable secondary | Add to review queue for business direct-admit selectivity. Do not override unless official/school-profile source is found or the P&Q school-survey methodology is accepted. |
| NYU | Stern/business | Washington Square News reports that Stern, CAS, and Rory Meyers Nursing each admitted fewer than 5% of applicants for NYU Class of 2029, citing NYU. Poets&Quants reports Stern 4.8% for fall 2024. | Institution-adjacent / reputable secondary | Stronger than capacity proxy. Treat Stern and Nursing as likely sub-5% selective, but label source tier if used. |
| Cornell | Dyson/business | Poets&Quants reports Dyson 4.9% for fall 2024. College Transitions says Cornell's most selective undergraduate division in Fall 2025 was Dyson at 5.4%, while Nolan Hotel was 22.3%. | Reputable secondary, with possible official IR root | High-priority review queue. Cornell IR may have the underlying college-level data, so this should be verified against Cornell's factbook before model use. |
| CMU | SCS/CS | Oriel estimates CMU SCS under 5% and contrasts it with CMU overall around 11%. Other secondary sources commonly place SCS around 4-7%, but underlying official current-cycle denominator remains hard to locate. | Consultant estimate | Use only as low-confidence proxy or as a cue to search CMU school-level admission PDFs. |
| UC Berkeley | CS/EECS | San Francisco Chronicle, using UC/CSU data, reports Berkeley CS admit rate rose from 3.8% in 2024 to 6.5% in Fall 2025 while campus overall was about 11%. College Transitions previously described Berkeley CS around 4%. | Data journalism / reputable secondary | Good secondary support for a Berkeley CS/EECS correction, but reconcile with UC official discipline dashboard and Berkeley Engineering college-level 6% before use. |
| Georgia Tech | CS | Oriel estimates Georgia Tech Computing/CS in the 7-9% range; Georgia Tech official College of Computing data supports an approximately 11.3% CS/CM combined offer rate for Fall 2025. | Consultant estimate plus official college data | Prefer the official CS/CM combined number; use secondary estimates only to decide whether a tighter CS-only adjustment needs more review. |
| UCLA | Nursing/CS/film/engineering | CollegeWise and San Francisco Chronicle both flag UCLA Nursing and CS/engineering as much lower than campus overall in recent cycles. UCLA official major profile is available, so secondary sources are mainly corroboration. | Reputable secondary / data journalism | Use official UCLA major profile instead of secondary figures. |
| Broad CS pattern | CS vs humanities | Oriel summarizes that CS-specific rates at top programs are often 30-50% lower than university overall where direct/college admission applies. | Consultant estimate | Use as qualitative report language only, not as a numeric adjustment. |

## Candidate Data Shape

If we add school-specific major selectivity, use a separate reviewed source file
rather than embedding special cases in `ChanceEngine.swift`.

Suggested file: `data/major_selectivity_signals.csv`

Suggested columns:

```text
college_id,major_category,program_label,entry_year,class_year,metric_scope,applicant_scope,applicants,admits,admit_rate,enrolled_or_spots,overall_admit_rate,selectivity_ratio,is_direct_admit_rate,is_undergrad_first_year,source_tier,source_url,source_note,data_quality
```

Important notes:

- `admit_rate` should be filled only when the source directly reports or allows
  applications/admitted calculation at the same scope.
- `entry_year` is the Fall entry year and is required.
- `class_year` is the graduating class year, such as Class of 2029. Leave it
  blank for multi-year averages or sources that do not identify a class year.
- `selectivity_ratio` can compare program admit rate with the current school
  overall base rate, but it should be bounded in model math.
- `enrolled_or_spots` should not be converted into an admit rate unless yield or
  admitted count is also known.
- `source_tier` should separate official rows from institution-adjacent,
  reputable secondary, consultant-estimate, and rejected forum rows.
- `applicant_scope` should distinguish all-applicant rows from nonresident or
  international-only rows such as UW CS/CE.
- UI text should say "this program/college has a smaller admitted share than
  the university overall" rather than "your chance is exactly the program admit
  rate."

## Modeling Recommendation

Add school-major logic in two layers:

1. Keep the existing global major adjustment as the default.
2. When reviewed school-major data exists, apply a bounded school-specific
   correction on top of or in place of part of the global major adjustment.

For direct admit-rate sources like UIUC:

- Compare program admit rate to the school overall rate.
- Convert that ratio to a capped logit correction.
- Cap direct school-major correction so it cannot dominate hard gates, academic
  fit, and China/international capacity logic.

For proxy-only sources like CMU SCS or NYU Stern:

- Use a smaller cap.
- Lower confidence/source quality.
- Disclose that the source is capacity or applicant-volume based, not an
  official program admit rate.

## Immediate Conclusion

Yes, strong-major data can be incorporated, but the quality varies sharply by
school:

- UCLA, UIUC, UW CS/CE, Michigan Ross, Berkeley Engineering, and selected
  Purdue/Georgia Tech rows are ready or near-ready for reviewed direct data rows
  because they publish official college, program, or applicant/admit counts.
- CMU SCS and NYU Stern clearly need stronger treatment than a generic CS or
  business adjustment, but current public data found in this pass supports only
  proxy-based corrections unless more official applicant/admit denominators are
  found.
- USC is useful negative evidence: official materials say majors have about the
  same admit rate, so Viterbi/Marshall should not be penalized just because they
  are perceived as popular.
- UC Information Center provides an official discipline dashboard for all UC
  campuses, but it warns that broad discipline grouping can hide major-level
  competition and should be used as a guide, not as a predictor.
- Secondary sources meaningfully expand the candidate list for business and CS:
  Wharton, Stern, Dyson, CMU SCS, and Berkeley CS/EECS should be reviewed next.
  Their source tier must remain visible so the app does not present estimates as
  official probabilities.

## Sources Reviewed

- UIUC Undergraduate Admissions, 2025 first-year admit rates:
  https://www.admissions.illinois.edu/apply/freshman/admit-rate
- UCLA Undergraduate Admission, Fall 2025 first-year profile by major:
  https://admission.ucla.edu/apply/first-year/first-year-profile/2025/major
- UC Berkeley Engineering, 2025 undergraduate facts brochure:
  https://engineering.berkeley.edu/wp-content/uploads/2025/02/2025-Undergrad-Facts-Brochure_web.pdf
- UC Admissions, UC Berkeley first-year admit data:
  https://admission.universityofcalifornia.edu/campuses-majors/berkeley/first-year-admit-data.html
- UC Information Center, freshman admission by discipline:
  https://www.universityofcalifornia.edu/about-us/information-center/freshman-admission-discipline
- University of Washington Office of Admissions, first-year students by the numbers:
  https://admit.washington.edu/apply/first-year/by-the-numbers/
- Michigan Ross, first-year BBA applicants:
  https://michiganross.umich.edu/undergraduate/bba/admissions/first-year-applicants
- Georgia Tech College of Computing, 2025 enrollment roundup:
  https://www.cc.gatech.edu/news/2025-enrollment-roundup-undergraduate-enrollment-in-computing-remains-popular
- Purdue University, class profile:
  https://admissions.purdue.edu/become-student/class-profile/
- USC Office of Admission, first-year student profile:
  https://admission.usc.edu/wp-content/uploads/first-year-student-profile.pdf
- USC Admission, first-year quick facts:
  https://applyto.usc.edu/www/documents/AV_FactsOneSheeter%281%29.pdf
- CMU Institutional Research, Fall 2024 first-year admission rates:
  https://www.cmu.edu/ira/undergraduate-admission/pdfs/2024-pdfs/f24-first-year-cohort-admission-rates-10dec2024.pdf
- CMU Common Data Set 2024-2025, first-time first-year admission:
  https://www.cmu.edu/ira/CDS/pdf/cds_2024-25/cds-2024-c-first-time-first-year-freshman-admission-26jun2025.pdf
- CMU Undergraduate Admission downloads and SCS/Tepper fact sheets:
  https://www.cmu.edu/admission/downloads
- CMU School of Computer Science undergraduate admission page:
  https://www.cmu.edu/admission/majors-programs/school-of-computer-science
- NYU Stern by the Numbers:
  https://www.stern.nyu.edu/programs-admissions/undergraduate/why-stern/numbers

## Secondary Sources Reviewed

- Poets&Quants For Undergrads, acceptance and graduation rates at undergraduate
  business schools:
  https://poetsandquantsforundergrads.com/admissions/acceptance-graduation-rates-at-the-best-undergraduate-business-schools/
- College Transitions, undergraduate business school acceptance rates:
  https://www.collegetransitions.com/blog/business-school-acceptance-rates-undergraduate/
- College Transitions, Cornell inside the numbers:
  https://www.collegetransitions.com/blog/cornell-university-inside-the-numbers/
- Washington Square News, NYU Class of 2029 admissions:
  https://nyunews.com/news/2025/03/27/nyu-admission-rate-class-of-2029/
- San Francisco Chronicle, UC/CSU acceptance rates by major:
  https://www.sfchronicle.com/projects/2026/uc-acceptance-rate-gpa-by-major/
- College Transitions, UC and CSU selectivity:
  https://www.collegetransitions.com/blog/easiest-uc-to-get-into-hardest-csu/
- Oriel Admissions, CS-specific acceptance-rate guide:
  https://orieladmissions.com/best-colleges-for-computer-science/
- Oriel Admissions, acceptance rates by major:
  https://orieladmissions.com/college-acceptance-rates-by-major/
