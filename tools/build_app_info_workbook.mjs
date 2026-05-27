import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = new URL("../outputs/admission_app_info/", import.meta.url);
const outputPath = new URL("中国学生美本录取概率App信息整理.xlsx", outputDir);

const workbook = Workbook.create();

const sheets = {
  profile: workbook.worksheets.add("学生画像填写内容"),
  probability: workbook.worksheets.add("概率评估表"),
  sources: workbook.worksheets.add("信息来源表"),
  method: workbook.worksheets.add("综合概率计算方法"),
};

function writeSheet(sheet, title, headers, rows, notes = []) {
  sheet.getRange("A1:H1").values = [[title, "", "", "", "", "", "", ""]];
  sheet.getRange("A3").values = [headers];
  if (rows.length) {
    sheet.getRange(`A4:${columnName(headers.length)}${rows.length + 3}`).values = rows;
  }
  if (notes.length) {
    const start = rows.length + 6;
    sheet.getRange(`A${start}`).values = [["备注"]];
    sheet.getRange(`A${start + 1}:A${start + notes.length}`).values = notes.map((note) => [note]);
  }
}

function columnName(index) {
  let name = "";
  while (index > 0) {
    const rem = (index - 1) % 26;
    name = String.fromCharCode(65 + rem) + name;
    index = Math.floor((index - 1) / 26);
  }
  return name;
}

const profileRows = [
  ["基础", "GPA / 校内成绩方式", "gradeScale", "百分制 / 4.0 GPA / 5.0 GPA / 等级制", "必填", "学生输入", "学术基础评分", "决定读取哪个成绩字段"],
  ["基础", "百分制 GPA / 均分", "gpaPercent", "数字 60-100", "条件显示", "学生输入", "学术基础评分", "百分制直接作为内部学术指数"],
  ["基础", "4.0 GPA", "gpaFourPoint", "0.0-4.0", "条件显示", "学生输入", "学术基础评分", "按分段表转换为内部学术指数"],
  ["基础", "5.0 GPA", "gpaFivePoint", "0.0-5.0", "条件显示", "学生输入", "学术基础评分", "按分段表转换为内部学术指数"],
  ["基础", "等级制成绩", "letterGrade", "A+ 到 C 或以下", "条件显示", "学生输入", "学术基础评分", "按等级区间转换为内部学术指数"],
  ["基础", "年级排名百分位", "classRankPercentile", "前 1%-80%", "必填", "学生输入", "学术基础评分", "数值越小越强，模型使用 100 - 百分位"],
  ["基础", "课程体系", "curriculum", "Chinese / AP / IB / A-Level", "必填", "学生输入", "课程匹配、硬门槛", "用于高中课程背景和部分门槛解释"],
  ["基础", "AP 课程门数", "apCourseCount", "0-12", "AP 条件显示", "学生输入", "课程体系成绩评分", "AP 体系下与 AP 平均分共同影响画像分"],
  ["基础", "AP 平均分", "apAverageScore", "1.0-5.0", "AP 条件显示", "学生输入", "课程体系成绩评分", "AP 体系下影响画像分和学术匹配"],
  ["基础", "IB 预估总分", "ibPredictedScore", "24-45", "IB 条件显示", "学生输入", "课程体系成绩评分", "IB 体系下影响画像分和学术匹配"],
  ["基础", "A-Level A* 科目", "aLevelAStarCount", "0-5", "A-Level 条件显示", "学生输入", "课程体系成绩评分", "A-Level 体系下影响画像分和学术匹配"],
  ["基础", "A-Level A 科目", "aLevelACount", "0-5", "A-Level 条件显示", "学生输入", "课程体系成绩评分", "A-Level 体系下影响画像分和学术匹配"],
  ["基础", "A-Level B 科目", "aLevelBCount", "0-5", "A-Level 条件显示", "学生输入", "课程体系成绩评分", "B 等级纳入但弱于 A/A*"],
  ["基础", "中国课程成绩方式", "curriculumGradeScale", "百分制 / 4.0 GPA / 5.0 GPA / 等级制", "Chinese 条件显示", "学生输入", "课程体系成绩评分", "决定读取中国课程核心成绩字段"],
  ["基础", "中国课程核心百分制成绩", "chineseCurriculumScore", "60-100", "Chinese 条件显示", "学生输入", "课程体系成绩评分", "只作为内部指数输入，不代表跨体系等价"],
  ["基础", "中国课程核心 4.0 GPA", "chineseCurriculumGPAFourPoint", "0.0-4.0", "Chinese 条件显示", "学生输入", "课程体系成绩评分", "按分段表转换为内部指数"],
  ["基础", "中国课程核心 5.0 GPA", "chineseCurriculumGPAFivePoint", "0.0-5.0", "Chinese 条件显示", "学生输入", "课程体系成绩评分", "按分段表转换为内部指数"],
  ["基础", "中国课程核心等级", "chineseCurriculumLetterGrade", "A+ 到 C 或以下", "Chinese 条件显示", "学生输入", "课程体系成绩评分", "按等级区间转换为内部指数"],
  ["基础", "目标专业", "major", "CS/Engineering/Business 等", "必填", "学生输入", "专业竞争修正、硬门槛", "STEM/艺术类触发课程或作品集推断门槛"],
  ["基础", "申请轮次", "round", "EA / ED / RD", "必填", "学生输入", "申请策略修正、轮次门槛", "ED/EA 可增加策略信号，具体学校限制走 gate"],
  ["基础", "是否申请资助", "needsAid", "是/否", "必填", "学生输入", "申请策略修正", "need-aware 学校可能降低概率"],
  ["标化", "是否不提交标化", "testOptional", "是/否", "必填", "学生输入", "硬门槛、标化评分", "test-required 学校未提交时直接 0%"],
  ["标化", "SAT", "sat", "900-1600", "条件必填", "学生输入", "硬门槛、标化评分", "required 学校会检查最低等效分"],
  ["标化", "ACT", "act", "18-36", "可选", "学生输入", "硬门槛、标化评分", "可换算为 SAT 等效值"],
  ["语言", "TOEFL", "toefl", "70-120", "条件必填", "学生输入", "英语硬门槛、标化评分", "国际生英语要求缺官方数据时按推断规则处理"],
  ["语言", "IELTS", "ielts", "6.0-9.0", "可选", "学生输入", "英语硬门槛、标化评分", "IELTS 7.0 作为 TOEFL 95 的近似替代"],
  ["学术", "课程难度", "rigor", "1-5", "必填", "学生输入", "课程难度评分、STEM门槛", "STEM 申请若低于推断最低强度会归零"],
  ["软实力", "活动影响力", "activities", "1-5", "必填", "学生输入", "软实力评分", "参考 CollegeVine 多因素画像思路"],
  ["软实力", "科研 / 夏校", "research", "1-5", "必填", "学生输入", "软实力评分", "科研和夏校单独入模"],
  ["软实力", "奖项区分度", "honors", "1-5", "必填", "学生输入", "软实力评分", "按层级和专业相关性由用户估计"],
  ["软实力", "文书成熟度", "essay", "1-5", "必填", "学生输入", "叙事评分", "AI 报告可建议提升，但不能改概率"],
  ["软实力", "推荐信强度", "recommendations", "1-5", "必填", "学生输入", "推荐信评分", "反映材料可信度和支持力度"],
  ["高中背景", "中国高中学校", "highSchoolID", "AdmitRanking 种子名单/其他", "必填", "AdmitRanking 参考 + 用户选择", "高中背景校准", "资源、升学记录、顾问支持、透明度"],
  ["专业材料", "艺术作品集已准备", "hasPortfolio", "是/否", "艺术类必填", "学生输入", "作品集硬门槛", "艺术类未准备作品集时按推断规则归零"],
  ["选校", "自动推荐学校数量", "requestedSchoolCount", "1-30", "必填", "学生输入", "推荐组合", "未手动选校时使用该数量生成组合"],
  ["选校", "手动目标学校", "selectedCollegeIDs", "AdmissionSight 学校 ID 集合", "可选", "用户选择", "逐校概率、组合概率", "手动选择优先于自动推荐"]
];

writeSheet(
  sheets.profile,
  "学生画像填写内容表",
  ["模块", "填写项", "字段名", "取值/格式", "是否必填", "来源", "用于", "说明"],
  profileRows,
  [
    "所有评分均为估算输入，app 必须提示用户结果不是录取承诺。",
    "硬门槛字段优先级高于画像评分；未满足 required 条件时单校概率为 0%。"
  ]
);

const probabilityRows = [
  ["学校基础率", "baseRate", "AdmissionSight 最新非空录取率", "Class of 2029 优先，N/A 用最近非空年份", "学校整体率展示", "AdmissionSight", "不直接等同普通中国申请者先验"],
  ["普通申请池先验", "ordinaryPrior", "整体率 × 国际生校准 × 特殊通道扣除 × 中国录取容量", "logit 前先验", "普通中国国际生先验", "计算引擎", "缺中国申请人数分母时使用容量约束"],
  ["硬门槛结果", "gateResult.passed", "逐校检查 standardized test / English / curriculum / portfolio / round", "失败则 probability = 0", "概率计算前置条件", "Official/CDS/推断规则", "失败原因必须展示"],
  ["失败规则", "failedRules", "未满足的官方或推断硬门槛", "列表", "解释 0% 原因", "Gate rules", "官方规则和推断规则分开标注"],
  ["推断规则", "inferredRules", "缺官方数据时按同类学校推断", "列表", "降低置信度", "同类学校政策推断", "必须显示 inferred"],
  ["画像总分", "profileScore", "学术、排名、课程、标化、活动等加权", "0-100", "调整普通申请池先验", "学生输入", "当前实现使用透明固定权重"],
  ["课程体系成绩", "curriculumPerformance", "AP/IB/A-Level/中国课程成绩按分段表转内部指数", "画像分 + 学术匹配修正", "课程体系强度结果", "学生输入", "与课程难度不同，表示该体系内的实际成绩表现；非真实百分制换算"],
  ["高中背景修正", "highSchoolDelta", "AdmitRanking 风格资源/顾问/升学/透明度", "logit 修正", "中国学校背景校准", "AdmitRanking 参考", "不能单独保证录取"],
  ["专业竞争修正", "majorDelta", "CS/Engineering/Business 等专业竞争", "logit 修正", "按专业调节", "模型规则", "CS/工程更保守"],
  ["轮次修正", "roundDelta", "ED/EA/RD", "logit 修正", "申请策略调节", "学生输入 + 学校规则", "轮次限制仍由 gate 管"],
  ["资助修正", "aidDelta", "是否申请资助", "logit 修正", "need-aware 风险", "学生输入", "v1 用保守负向修正"],
  ["数据质量修正", "uncertaintyPenalty", "学校统计缺口 + gate 推断数量", "logit 负向修正", "置信度和概率保守化", "数据源完整性", "缺官方数据不得假装确定"],
  ["单校概率", "adjustedProbability", "logistic(logit(ordinaryPrior)+各项修正)，再按中国录取容量封顶", "0%-82%，gate失败为0%", "逐校结果", "计算引擎", "展示 bucket 和 warnings"],
  ["结果分档", "bucket", "<15% 争取；15%-35% 目标；>=35% 保底；0% 硬门槛未满足", "中文标签", "结果展示", "计算引擎", "分档不是录取结论"],
  ["T10至少一所", "t10AtLeastOne", "T10 学校结果做相关性折扣组合", "0%-98%", "汇总概率", "计算引擎", "包含 gate 后的非零概率"],
  ["T30至少一所", "t30AtLeastOne", "T30 学校结果做相关性折扣组合", "0%-98%", "汇总概率", "计算引擎", "不是简单独立相乘"],
  ["T50至少一所", "t50AtLeastOne", "T50 学校结果做相关性折扣组合", "0%-98%", "汇总概率", "计算引擎", "当前数据覆盖到 AdmissionSight 表中已录入学校"],
  ["当前组合至少一所", "selectedAtLeastOne", "用户手选或自动推荐组合", "0%-98%", "组合结果", "计算引擎", "展示在结果页顶部"],
  ["置信度", "confidence", "高/中/低", "标签", "解释可信程度", "数据质量 + 画像完整度 + gate 推断", "低置信需提示补数据"],
  ["警告", "warnings", "N/A 年份、推断规则、数据缺口", "列表", "透明披露", "数据校验", "报告必须包含"]
];

writeSheet(
  sheets.probability,
  "概率评估表",
  ["评估项", "字段名", "计算/取值方法", "输出格式", "作用", "来源", "备注"],
  probabilityRows
);

const sourceRows = [
  ["AdmissionSight College Acceptance Rates", "https://admissionsight.com/college-acceptance-rates/", "学校、US News Rank、Class 2029-2024 录取率", "学校统计主表", "v1 唯一学校统计种子", "Class 2029 N/A 时用最近非空年份", "已内置 National Universities 种子数据"],
  ["CollegeVine Admissions Calculator", "https://www.collegevine.com/admissions-calculator", "画像字段、多因素 chancing 思路", "参考", "指导学生画像维度", "不复制专有权重/模型", "用于字段设计和说明风格"],
  ["AdmitRanking 首页/美国方向榜单", "https://admitranking.com/", "中国国际化学校排名、高中资源/升学背景", "参考", "高中背景校准", "不是逐校学生录取率", "v1 内置 Top 中国高中背景样例"],
  ["AdmitRanking 指标说明", "https://admitranking.com/indicator/4708", "升学成果、学术资源、学校声誉、数据透明度", "参考", "高中校准维度设计", "若官方数缺失需标注", "用于四项高中背景输入"],
  ["Official College Admissions Pages", "各学校官网", "标化、英语、课程、作品集、轮次硬性要求", "强约束", "硬门槛检查", "官方 required/minimum 未满足即 0%", "后续需持续补齐每校 URL"],
  ["Common Data Set (CDS)", "各学校 CDS", "国际生比例、测试政策、录取统计", "补充强约束/统计", "硬门槛和置信度", "CDS 字段缺失时降低置信度", "用于官方页面难找时复核"],
  ["Harness", "本仓库 harness.yaml / HARNESS.md", "数据范围、模型约束、AI报告限制、测试标准", "内部约束", "构建和验收", "不能被 UI 或 AI 报告绕过", "已落地"],
  ["用户输入", "App 表单", "学生画像、目标专业、轮次、资助、选校", "运行时输入", "个人概率调整", "主观评分需提示不确定性", "报告只能解释，不改变计算"]
];

writeSheet(
  sheets.sources,
  "信息来源表",
  ["来源", "链接/位置", "提供信息", "类型", "用于", "限制/风险", "当前状态"],
  sourceRows
);

const methodRows = [
  ["1", "数据范围校验", "确认学校在 AdmissionSight National Universities 种子表中", "collegeID in approvedDataset", "不通过则不计算", "防止引入未授权数据"],
  ["2", "硬门槛检查", "检查 required 标化、英语、课程、作品集、轮次", "if failedRules.count > 0 then probability = 0", "输出 0% 和失败原因", "官方规则优先；推断规则必须标注"],
  ["3", "画像分计算", "把学生输入压缩为 0-100 分", "profileScore = Σ(componentScore × weight)", "进入 logit 调整", "当前权重见下方权重表"],
  ["4", "学校先验", "使用最新非空 AdmissionSight 录取率", "baseRate = latestNonNullAcceptanceRate", "单校基础概率", "N/A 年份降低数据质量"],
  ["5", "普通申请池先验", "把基础率按国际生、中国容量和特殊通道扣除校准", "ordinaryPrior = baseRate × multipliers", "避免把整体录取率当普通中国申请者概率", "容量数据缺分母时保守处理"],
  ["6", "Logit 转换", "把普通申请池先验转成可加和空间", "logitPrior = LN(ordinaryPrior/(1-ordinaryPrior))", "便于叠加修正", "避免直接线性加百分比"],
  ["7", "修正项叠加", "画像、高中、专业、轮次、资助、数据缺口、中国趋势", "adjustedLogit = logitPrior + deltas", "个性化概率", "所有 deltas 必须可解释"],
  ["8", "概率还原与封顶", "用 logistic 还原为 0-1 概率，并按中国录取容量 cap", "probability = min(cap, 1/(1+EXP(-adjustedLogit)))", "单校概率", "gate 失败始终覆盖为 0"],
  ["9", "结果分档", "按概率给中文 bucket", "0=硬门槛；<15%=争取；<35%=目标；其他=保底", "结果页展示", "分档只做规划参考"],
  ["10", "组合概率", "按 tier 分组，同层学校依次折扣", "failure *= (1 - probability × 0.72^index)", "至少一所录取概率", "避免简单独立相乘高估"],
  ["11", "报告生成", "AI 基于结构化结果生成策略和建议", "report(input = profile + computedResults + warnings)", "付费报告", "AI 不得改概率、加学校或承诺录取"]
];

writeSheet(
  sheets.method,
  "综合概率计算方法",
  ["步骤", "模块", "说明", "公式/规则", "输出", "注意事项"],
  methodRows
);

const weightStart = methodRows.length + 7;
sheets.method.getRange(`A${weightStart}:F${weightStart}`).values = [["画像分权重表", "", "", "", "", ""]];
sheets.method.getRange(`A${weightStart + 1}:F${weightStart + 1}`).values = [["组件", "权重", "输入字段", "评分方式", "说明", "可调性"]];
sheets.method.getRange(`A${weightStart + 2}:F${weightStart + 12}`).values = [
  ["GPA/校内成绩", 0.18, "gradeScale + GPA fields", "按记录方式分段归一", "学术基础；非百分输入只转内部指数", "可调"],
  ["年级排名", 0.10, "classRankPercentile", "100 - 百分位", "相对竞争环境", "可调"],
  ["课程难度", 0.10, "rigor", "1-5 转 20-100", "课程挑战度", "可调"],
  ["课程体系成绩", 0.08, "AP/IB/A-Level/Chinese scores", "按体系分段转内部指数", "课程体系内成绩表现", "可调"],
  ["标化/语言", 0.11, "SAT/ACT/TOEFL/IELTS", "分段归一", "可比硬指标", "可调"],
  ["高中背景", 0.08, "highSchoolID", "资源/顾问/升学/透明度", "中国校背景", "可调"],
  ["活动", 0.12, "activities", "1-5 转 20-100", "影响力", "可调"],
  ["科研/夏校", 0.07, "research", "1-5 转 20-100", "学术探索", "可调"],
  ["奖项", 0.08, "honors", "1-5 转 20-100", "区分度", "可调"],
  ["文书", 0.04, "essay", "1-5 转 20-100", "叙事成熟度", "可调"],
  ["推荐信", 0.04, "recommendations", "1-5 转 20-100", "第三方背书", "可调"]
];

const formulaStart = weightStart + 14;
sheets.method.getRange(`A${formulaStart}:F${formulaStart}`).values = [["Excel 审计示例", "", "", "", "", ""]];
sheets.method.getRange(`A${formulaStart + 1}:F${formulaStart + 1}`).values = [["变量", "示例值", "公式", "结果", "说明", ""]];
sheets.method.getRange(`A${formulaStart + 2}:F${formulaStart + 8}`).values = [
  ["baseRate", 0.05, "", "", "学校基础率", ""],
  ["profileScore", 82, "", "", "学生画像分", ""],
  ["readinessDelta", "", "=(B" + (formulaStart + 3) + "-72)*0.047", "", "画像修正", ""],
  ["ordinaryPrior", 0.025, "", "", "普通申请池先验", ""],
  ["logitPrior", "", "=LN(B" + (formulaStart + 5) + "/(1-B" + (formulaStart + 5) + "))", "", "普通申请池先验 logit", ""],
  ["adjustedLogit", "", "=C" + (formulaStart + 6) + "+C" + (formulaStart + 4), "", "只演示画像修正", ""],
  ["probability", "", "=1/(1+EXP(-C" + (formulaStart + 7) + "))", "", "单校概率示例", ""]
];
sheets.method.getRange(`D${formulaStart + 4}`).formulas = [[`=(B${formulaStart + 3}-72)*0.047`]];
sheets.method.getRange(`D${formulaStart + 6}`).formulas = [[`=LN(B${formulaStart + 5}/(1-B${formulaStart + 5}))`]];
sheets.method.getRange(`D${formulaStart + 7}`).formulas = [[`=D${formulaStart + 6}+D${formulaStart + 4}`]];
sheets.method.getRange(`D${formulaStart + 8}`).formulas = [[`=1/(1+EXP(-D${formulaStart + 7}))`]];

// Simple formatting kept within broadly supported artifact-tool operations.
for (const sheet of Object.values(sheets)) {
  sheet.getUsedRange().format.wrapText = true;
  sheet.getUsedRange().format.font.name = "Arial";
  sheet.getUsedRange().format.font.size = 10;
  sheet.getRange("A1:H1").format.font.bold = true;
  sheet.getRange("A1:H1").format.font.size = 16;
  sheet.getRange("A3:H3").format.font.bold = true;
  sheet.getRange("A3:H3").format.fill = "#D9EAF7";
}

sheets.method.getRange(`A${weightStart}:F${weightStart}`).format.font.bold = true;
sheets.method.getRange(`A${weightStart + 1}:F${weightStart + 1}`).format.font.bold = true;
sheets.method.getRange(`A${formulaStart}:F${formulaStart}`).format.font.bold = true;
sheets.method.getRange(`A${formulaStart + 1}:F${formulaStart + 1}`).format.font.bold = true;
sheets.method.getRange(`B${formulaStart + 2}:B${formulaStart + 2}`).format.numberFormat = "0.0%";
sheets.method.getRange(`D${formulaStart + 4}:D${formulaStart + 7}`).format.numberFormat = "0.000";

await fs.mkdir(outputDir, { recursive: true });

const checks = [];
checks.push(await workbook.inspect({
  kind: "table",
  range: "学生画像填写内容!A1:H16",
  include: "values,formulas",
  tableMaxRows: 20,
  tableMaxCols: 8,
}));
checks.push(await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 50 },
  summary: "formula error scan",
}));

for (const sheetName of ["学生画像填写内容", "概率评估表", "信息来源表", "综合概率计算方法"]) {
  await workbook.render({ sheetName, range: "A1:H20", scale: 1 });
}

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

console.log(JSON.stringify({
  outputPath: outputPath.pathname,
  checks: checks.map((check) => check.ndjson?.slice(0, 500) ?? ""),
}, null, 2));
