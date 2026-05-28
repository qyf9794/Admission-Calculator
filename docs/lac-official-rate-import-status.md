# 文理学院官方录取率导入状态

当前状态：`data/liberal_arts_colleges.csv` 已用 College Scorecard 官方 API 返回的 30 所文理学院基础录取率替换原图片表整体录取率。用户提供的 `IMG_0742.JPG` 表格继续作为 v1 文理学院名单与排名范围来源；每行基础率来源已改为 UnitID 匹配后的官方 Scorecard 学校页。

## 本次已应用的官方替换

- 2026-05-28 运行 `npm run data:scorecard:lac -- --api-key DEMO_KEY --output /tmp/scorecard_lac_review_retry.csv` 成功生成 30 行 College Scorecard review CSV。
- 生成文件按 `data/liberal_arts_unitids.json` 中的六位 UnitID 精确匹配学校，并返回 Scorecard 官方学校名、官方学校页 URL、`latest.admissions.admission_rate.overall / ADM_RATE` 基础率和 student size。
- 运行 `npm run data:official:lac:apply -- --dry-run --official /tmp/scorecard_lac_review_retry.csv` 通过 UnitID、官方名称、source URL 和录取率范围校验，显示 28 个 `rate_2029` 值会变化。
- 运行 `npm run data:official:lac:apply -- --official /tmp/scorecard_lac_review_retry.csv` 后，30 所文理学院基础率已应用为官方 Scorecard 值，`data_quality` 提升到 `0.9`，source note 明确保留 `IMG_0742.JPG` 仅用于名单/排名范围。

## 已验证能力

- `data/liberal_arts_unitids.json` 覆盖 30 所文理学院，并作为官方数据匹配键。
- `npm run data:scorecard:lac` 可从 College Scorecard API、官方本地 CSV/ZIP 或官方 URL 生成 review CSV；若使用官方 raw data ZIP，解析器会优先选择最新 `MERGEDYYYY_YY_PP.csv`，并把选中的 CSV 文件名写入每行 `source_note`。`apply` 后的 LAC seed 也会保留该说明，避免误读旧年度 CSV 后难以人工复核。
- `npm run data:scorecard:lac -- --scorecard-latest-url` 可从官方 College Scorecard 数据页发现当前 institution-level 下载 URL，再按官方 URL 下载解析；若官网页面在当前网络被 CloudFront 阻断，可先在浏览器保存官方页面 HTML，再用 `--scorecard-page-html <path> --scorecard-latest-url` 只做官方下载 URL 发现。发现路径只接受 `collegescorecard.ed.gov/data/` 页面，并且发现结果必须是官方 institution-level CSV/ZIP。
- `npm run data:ipeds:lac` 可从 NCES/IPEDS ADM、DRVADM、本地 Reported Data HTML 或官方 Reported Data URL 生成 review CSV。
- `npm run data:official:lac:apply -- --dry-run --official <review_csv>` 会在替换前校验 UnitID、学校名、排名、官方返回/解析出的学校名、录取率范围和官方来源 URL。
- `npm run data:official:lac:apply -- --dry-run --official <review_csv>` 还会校验每行 `source_url` 与该行 UnitID/官方组件一致：Scorecard 学校 URL 必须指向同一 UnitID；NCES Reported Data URL 必须指向同一 UnitID 且使用 admissions component `surveyNumber=12`。
- `scripts/update-admissions-data.mjs` 会在 seed 生成阶段再次校验已应用的 LAC 来源：Scorecard 学校 URL 必须精确匹配 reviewed UnitID；NCES Reported Data URL 必须精确匹配 reviewed UnitID 且使用 admissions component `surveyNumber=12`；官方 seed source note 必须披露对应 UnitID；仍来自用户图片表的行不得把 `data_quality` 提升到官方级别。
- `npm run data:official:lac:check` 已覆盖 Scorecard、IPEDS ADM、IPEDS DRVADM、NCES Reported Data HTML 的成功路径、Scorecard raw data ZIP 最新年度选择与 apply 后来源说明保留、未知本地 Scorecard/IPEDS CSV 或 ZIP 文件名拒绝、UnitID/页面错配失败路径、人工 review CSV 中官方名称错配、官方来源 URL 指错学校或指错组件的失败路径，以及直接手动改 `data/liberal_arts_colleges.csv` 后试图绕过 official apply 校验的失败路径。
- `npm run data:lac:official-urls` 可生成 `data/lac_official_url_manifest.csv`，列出每所文理学院的 UnitID、College Scorecard 学校页、NCES Reported Data Admissions 页面和本地 HTML 文件名，方便人工下载官方页面后走 `--reported-html-dir`；`npm run data:lac:official-urls:check` 会检查该清单是否与当前 LAC seed 和 UnitID map 同步。
- URL 下载模式会拒绝非 HTTPS 或非官方域名：Scorecard 仅允许官方 College Scorecard 下载域，且 URL 必须指向 institution CSV/ZIP 或 raw data ZIP；IPEDS 仅允许 `nces.ed.gov`。本地 Scorecard CSV 文件名和 ZIP 内 CSV 文件名都必须是官方 institution CSV 文件名或 raw data `MERGEDYYYY_YY_PP.csv` 文件名；本地 IPEDS CSV/ZIP 文件名必须是官方 `ADMYYYY*` 或 `DRVADMYYYY*` 文件名。即使某个未知 CSV 具备 `UNITID/ADM_RATE/DVADM01` 等相似字段也会被拒绝。本地文件必须使用显式本地 CSV/ZIP/HTML 参数，不允许用 `file://` 伪装成 URL 下载。本地文件模式只应用于人工确认过的官方下载文件。
- 官方 Scorecard 数据页发现模式会优先选择 `Most-Recent-Cohorts-Institution*.csv/zip`，不会把 Field of Study 文件或 raw data ZIP 自动当作 institution-level 基础率来源；raw data ZIP 仍可通过显式 `--scorecard-zip` 或 `--scorecard-url` 走人工确认路径。

## 当前外部阻塞证据

- College Scorecard 官方下载页显示数据最近更新于 2026-03-23，且“Most Recent Institution-Level Data”下载链接已使用 `ed-public-download.scorecard.network` 域名；项目工具链已将该官网列出的新下载域纳入官方 Scorecard 下载白名单，并提供官方页面自动发现 institution-level 下载 URL 的入口。
- 2026-05-28 复测 `npm run data:scorecard:lac -- --check-scorecard-latest-url` 时，官方数据页 `https://collegescorecard.ed.gov/data/` 在本机网络返回 CloudFront HTTP `403`，因此当前环境无法直接通过网页发现最新 institution-level URL；若用户能在浏览器保存官方数据页 HTML，工具仍可通过 `--scorecard-page-html <path> --scorecard-latest-url` 从官方页面内容中发现链接。
- 2026-05-28 复测公开目录入口：`catalog.data.gov/api/3/action/package_search` 与 `catalog.data.gov/api/action/package_search` 对 College Scorecard 查询均返回 `Not Found`；`data.ed.gov/api/3/action/package_search` 在本机网络返回 CloudFront `403`。这些目录入口当前不能作为可自动化的权威下载路径。
- 2026-05-28 复测官方技术文档 PDF `https://collegescorecard.ed.gov/files/InstitutionDataDocumentation.pdf` 也返回 CloudFront `403`；浏览器或其他网络可访问时仍可人工下载文档，但本机无法把它作为自动发现下载 URL 的来源。
- 2026-05-28 复核官方文档入口：College Scorecard API 文档仍要求通过 data.gov API key 访问；NCES/IPEDS 官方 Data Center 仍以 DataFiles/Reported Data 下载与页面查询为主，检索结果明确列出 2024 `ADM2024` Admissions and Test Scores 与 `DRVADM2024` Selectivity and admissions yield 文件。College Scorecard 机构级技术文档检索结果显示 2025-09 版本，仍说明机构级数据元素主要来自或派生自 IPEDS。未发现可替代现有 `ADM/DRVADM/Reported Data HTML` 路径的稳定批量 JSON API。因此当前工具链继续保留“官方文件或页面 HTML -> review CSV -> dry-run -> apply”的审阅式替换流程。
- 2026-05-28 复核 College Scorecard API 文档：官方接口支持 value-list 参数，可用逗号分隔的一组 `id` 精确匹配多所学校；默认限流为每 IP 每小时 1000 次。当前 `fetch-scorecard-lac-rates.mjs` 已按最多 100 个 UNITID 一批构造 `id=<unitid,...>` 请求，因此 30 所 LAC 只需要一次 API 调用；当前阻塞来自 `DEMO_KEY` / 当前 IP 限流，而不是逐校请求过多。
- 2026-05-28 本轮复测 `npm run data:scorecard:lac -- --check-scorecard-latest-url` 仍返回 CloudFront `403`；`npm run data:scorecard:lac -- --api-key DEMO_KEY --output /tmp/scorecard_lac_review_retry.csv` 成功返回 30 行并已按 dry-run/apply 流程应用；`npm run data:ipeds:lac -- --reported-url-template ...` 仍因 NCES HTTPS `ECONNRESET` 无法直接下载官方 Reported Data 页面。
- 2026-05-27 直接探测 `https://ed-public-download.scorecard.network/downloads/Most-Recent-Cohorts-Institution_03232026.zip` 返回 CloudFront HTTP `403`；即使加入浏览器 User-Agent 和 `https://collegescorecard.ed.gov/data/` Referer，仍返回 `403` 和 919 字节 HTML 错误页。说明该官方批量文件当前不能由本机网络直接抓取，但若用户能在浏览器或其他网络下载该 ZIP，仍可通过 `--scorecard-zip <path>` 走本地官方文件导入。
- 2026-05-28 复核 data.gov 官方目录资源 `Most Recent Institution Level Data`：目录页仍展示 2023-04-19 数据和 `https://ed-public-download.app.cloud.gov/downloads/Most-Recent-Cohorts-Institution_04192023.zip`。项目 URL 校验接受该官方旧域名，但该链接实测返回 HTTP `404 unknown_route`，且即使可下载也不是当前最新 2026 Scorecard 批次，因此不得用作当前 LAC 基础率替换。
- College Scorecard API 曾在 2026-05-27 使用 `DEMO_KEY` 返回 `429 OVER_RATE_LIMIT`；2026-05-28 复测已恢复可用并完成本次官方替换。后续刷新仍建议使用非限流 data.gov API key，避免共享 demo key 再次达到限流。
- NCES ADM/DRVADM 官方 ZIP 与 Reported Data 官方页面在本机网络下无法完成 TLS 握手。对 ADM2024、DRVADM2024 和 Williams College UnitID `168342` 的测试表现为：
  - Node fetch: `ECONNRESET`
  - Python urllib: `SSL: UNEXPECTED_EOF_WHILE_READING`
  - wget/OpenSSL: `unexpected eof while reading`
  - 2026-05-27 复测 curl: `LibreSSL SSL_connect: SSL_ERROR_SYSCALL in connection to nces.ed.gov:443`

## 后续官方刷新路径

当前 LAC 基础率已应用官方 Scorecard 值。后续要刷新到更新批次时，可任选其一：

- 非限流 `COLLEGE_SCORECARD_API_KEY`，然后运行 `npm run data:scorecard:lac` 并先 dry-run 再 apply。
- 官方下载的 `Most-Recent-Cohorts-Institution.csv` 或 ZIP，然后运行 `npm run data:scorecard:lac -- --scorecard-csv/--scorecard-zip <path>`。
- 官方 Scorecard 下载 URL 可用时，运行 `npm run data:scorecard:lac -- --scorecard-url https://ed-public-download.scorecard.network/downloads/<official-file>.zip`。
- 官方 Scorecard 数据页可访问时，运行 `npm run data:scorecard:lac -- --check-scorecard-latest-url` 先确认发现到的 institution-level URL，再运行 `npm run data:scorecard:lac -- --scorecard-latest-url`；若页面被当前网络阻断，可在浏览器保存官方页面 HTML 后运行 `npm run data:scorecard:lac -- --scorecard-page-html <html> --scorecard-latest-url`。
- 官方下载的 NCES/IPEDS `ADM2024` 或 `DRVADM2024` CSV/ZIP，然后运行 `npm run data:ipeds:lac -- --adm-csv/--adm-zip/--ipeds-csv/--ipeds-zip <path>`。
- 官方 NCES Reported Data Admissions HTML 页面目录，然后运行 `npm run data:ipeds:lac -- --reported-html-dir <dir> --year <year>`。
  - 可先运行 `npm run data:lac:official-urls -- --year <year>` 生成 URL 与文件名清单，再将官方 HTML 按清单保存为 `<unitid>.html`；生成清单和导入 HTML 目录时必须使用同一个 `<year>`。

不要把第三方镜像、顾问网站或未经 UnitID 校验的网页数据直接应用为权威替换数据。
