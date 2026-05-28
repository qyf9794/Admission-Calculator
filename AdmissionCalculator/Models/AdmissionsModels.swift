import Foundation

enum CurriculumType: String, CaseIterable, Identifiable, Codable {
    case chinese = "Chinese"
    case ap = "AP"
    case ib = "IB"
    case alevel = "A-Level"

    var id: String { rawValue }
}

enum GradeScale: String, CaseIterable, Identifiable, Codable {
    case percent = "百分制"
    case fourPoint = "4.0 GPA"
    case fivePoint = "5.0 GPA"
    case letter = "等级制"

    var id: String { rawValue }
}

enum LetterGradeBand: String, CaseIterable, Identifiable, Codable {
    case aPlus = "A+"
    case a = "A"
    case aMinus = "A-"
    case bPlus = "B+"
    case b = "B"
    case bMinus = "B-"
    case cPlus = "C+"
    case c = "C"
    case d = "D"
    case f = "F"
    case cOrBelow = "C 或以下"

    static var allCases: [LetterGradeBand] {
        [.aPlus, .a, .aMinus, .bPlus, .b, .bMinus, .cPlus, .c, .d, .f]
    }

    var id: String { rawValue }
}

enum ApplicationRound: String, CaseIterable, Identifiable, Codable {
    case earlyAction = "EA"
    case earlyDecision = "ED"
    case regularDecision = "RD"

    var id: String { rawValue }
}

enum MajorCategory: String, CaseIterable, Identifiable, Codable {
    case computerScience = "Computer Science"
    case engineering = "Engineering"
    case business = "Business"
    case economics = "Economics"
    case naturalScience = "Natural Science"
    case socialScience = "Social Science"
    case humanities = "Humanities"
    case arts = "Arts"

    var id: String { rawValue }

    var isSTEM: Bool {
        switch self {
        case .computerScience, .engineering, .naturalScience:
            return true
        case .business, .economics, .socialScience, .humanities, .arts:
            return false
        }
    }
}

enum ApplicantStatus: String, CaseIterable, Identifiable, Codable {
    case chineseInternational = "中国籍国际生"
    case otherInternational = "其他国际生"
    case usCitizenAbroad = "美籍/绿卡，海外高中"
    case usCitizenDomestic = "美籍/绿卡，美国高中"

    var id: String { rawValue }

    var isInternational: Bool {
        switch self {
        case .chineseInternational, .otherInternational:
            return true
        case .usCitizenAbroad, .usCitizenDomestic:
            return false
        }
    }

    var usesChinaProxy: Bool {
        self == .chineseInternational
    }

    var requiresEnglishProof: Bool {
        switch self {
        case .chineseInternational, .otherInternational:
            return true
        case .usCitizenAbroad, .usCitizenDomestic:
            return false
        }
    }
}

enum ConfidenceLabel: String, Codable {
    case high = "高"
    case medium = "中"
    case low = "低"
}

enum RecommendationBucket: String, Codable {
    case reach = "争取"
    case target = "目标"
    case likely = "保底"
    case blocked = "硬门槛未满足"
}

enum PortfolioSelectionSource: String, Codable {
    case none = "尚未选择"
    case manual = "手动选择"
    case automatic = "自动推荐"

    func afterProfileEdit(selectedCollegeIDs: Set<String>) -> PortfolioSelectionSource {
        guard self == .automatic else {
            return self
        }
        return selectedCollegeIDs.isEmpty ? .none : .manual
    }
}

enum GateRuleType: String, Codable {
    case standardizedTest = "标化"
    case english = "英语"
    case curriculum = "课程"
    case portfolio = "作品集"
    case round = "轮次"
}

enum CollegeCategory: String, Codable {
    case nationalUniversity = "综合大学"
    case liberalArtsCollege = "文理学院"
}

struct AcceptanceRate: Identifiable, Hashable, Codable {
    let classYear: Int
    let rate: Double?

    var id: Int { classYear }
}

struct College: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let category: CollegeCategory
    let rank: Int
    let acceptanceRates: [AcceptanceRate]
    let sourceURL: URL
    let sourceNote: String
    let dataQuality: Double

    var latestAvailableRate: Double {
        acceptanceRates.sorted { $0.classYear > $1.classYear }.compactMap(\.rate).first ?? 0.12
    }

    var latestAvailableClassYear: Int {
        acceptanceRates.sorted { $0.classYear > $1.classYear }.first(where: { $0.rate != nil })?.classYear ?? 2028
    }

    var tierName: String {
        let rankTier: String
        if rank <= 10 {
            rankTier = "T10"
        } else if rank <= 30 {
            rankTier = "T30"
        } else if category == .nationalUniversity && rank <= 50 {
            rankTier = "T50"
        } else {
            rankTier = "Listed"
        }
        return "\(category.rawValue)-\(rankTier)"
    }

    var tierDisplayName: String {
        switch category {
        case .nationalUniversity:
            if rank <= 10 { return "综合大学 T10" }
            if rank <= 30 { return "综合大学 T30" }
            if rank <= 50 { return "综合大学 T50" }
            return "综合大学 50+"
        case .liberalArtsCollege:
            if rank <= 10 { return "文理学院 T10" }
            if rank <= 30 { return "文理学院 T30" }
            return "文理学院 30+"
        }
    }

    func matchesPickerQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        let normalized = trimmed.uppercased()
        switch normalized {
        case "T10", "TOP10", "TOP 10", "综合大学 T10", "NATIONAL UNIVERSITIES T10", "NU T10":
            return category == .nationalUniversity && rank <= 10
        case "T30", "TOP30", "TOP 30", "综合大学 T30", "NATIONAL UNIVERSITIES T30", "NU T30":
            return category == .nationalUniversity && rank <= 30
        case "T50", "TOP50", "TOP 50", "综合大学 T50", "NATIONAL UNIVERSITIES T50", "NU T50":
            return category == .nationalUniversity && rank <= 50
        case "LISTED", "50+", "T50+", "TOP50+", "TOP 50+", "综合大学 50+", "NATIONAL UNIVERSITIES 50+", "NU 50+":
            return category == .nationalUniversity && rank > 50
        case "LAC", "文理学院", "LIBERAL ARTS", "LIBERAL ARTS COLLEGE":
            return category == .liberalArtsCollege
        case "LAC T10", "LA T10", "文理T10", "文理学院 T10", "LIBERAL ARTS T10":
            return category == .liberalArtsCollege && rank <= 10
        case "LAC T30", "LA T30", "文理T30", "文理学院 T30", "LIBERAL ARTS T30":
            return category == .liberalArtsCollege && rank <= 30
        default:
            break
        }

        return name.localizedCaseInsensitiveContains(trimmed) ||
            id.localizedCaseInsensitiveContains(trimmed) ||
            category.rawValue.localizedCaseInsensitiveContains(trimmed) ||
            tierDisplayName.localizedCaseInsensitiveContains(trimmed) ||
            "#\(rank)".localizedCaseInsensitiveContains(trimmed) ||
            String(rank).localizedCaseInsensitiveContains(trimmed)
    }

    func matchesSourceAuditQuery(
        _ query: String,
        internationalSignal: InternationalSignal?,
        chinaSignal: ChinaUndergradAdmissionSignal?,
        academicBenchmark: AcademicBenchmark?,
        gateRules: [CollegeGateRule]
    ) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        if matchesPickerQuery(trimmed) ||
            sourceURL.absoluteString.localizedCaseInsensitiveContains(trimmed) ||
            sourceNote.localizedCaseInsensitiveContains(trimmed) {
            return true
        }

        let fields = sourceAuditSearchFields(
            internationalSignal: internationalSignal,
            chinaSignal: chinaSignal,
            academicBenchmark: academicBenchmark,
            gateRules: gateRules
        )
        return fields.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private func sourceAuditSearchFields(
        internationalSignal: InternationalSignal?,
        chinaSignal: ChinaUndergradAdmissionSignal?,
        academicBenchmark: AcademicBenchmark?,
        gateRules: [CollegeGateRule]
    ) -> [String] {
        var fields: [String] = []
        fields.append(sourceNote)
        if let internationalSignal {
            fields.append(internationalSignal.dataScope)
            fields.append(internationalSignal.sourceNote)
            fields.append(internationalSignal.internationalAidPolicy.rawValue)
            fields.append(contentsOf: internationalSignal.sourceFields)
            if let sourceURL = internationalSignal.sourceURL {
                fields.append(sourceURL.absoluteString)
            }
        }
        if let chinaSignal {
            fields.append(chinaSignal.dataScope)
            fields.append(chinaSignal.sourceNote)
        }
        if let academicBenchmark {
            fields.append(academicBenchmark.sourceNote)
            fields.append(contentsOf: academicBenchmark.sourceFields)
            if let sourceURL = academicBenchmark.sourceURL {
                fields.append(sourceURL.absoluteString)
            }
        }
        for rule in gateRules {
            fields.append(rule.title)
            fields.append(rule.detail)
            fields.append(rule.type.rawValue)
            fields.append(rule.isOfficial ? "official" : "inferred")
            fields.append(rule.isOfficial ? "官方" : "推断")
            fields.append(contentsOf: rule.allowedRounds.map(\.rawValue))
            if let sourceURL = rule.sourceURL {
                fields.append(sourceURL.absoluteString)
            }
        }
        return fields
    }
}

enum InternationalAidPolicy: String, Codable {
    case needBlind = "need_blind"
    case needAware = "need_aware"
    case limited = "limited"
    case unknown = "unknown"
}

struct InternationalSignal: Identifiable, Hashable, Codable {
    let collegeID: String
    let undergradNonresidentShare: Double?
    let internationalAdmittedCount: Int?
    let totalAdmittedCount: Int?
    let internationalAdmitCoefficient: Double?
    let internationalAidPolicy: InternationalAidPolicy
    let isUndergradOnly: Bool
    let dataScope: String
    let sourceFields: [String]
    let sourceURL: URL?
    let sourceNote: String
    let dataQuality: Double

    var id: String { collegeID }
}

struct ChinaUndergradAdmissionSignal: Identifiable, Hashable, Codable {
    let collegeID: String
    let early2028: Int?
    let rd2028: Int?
    let total2028: Int?
    let early2029: Int?
    let rd2029: Int?
    let total2029: Int?
    let early2030: Int?
    let rd2030: Int?
    let total2030: Int?
    let chinaShareOfAllAdmits: Double?
    let dataScope: String
    let sourceNote: String
    let dataQuality: Double

    var id: String { collegeID }
}

struct AcademicBenchmark: Identifiable, Hashable, Codable {
    let collegeID: String
    let gpaPercentBenchmark: Double?
    let classRankPercentileBenchmark: Double?
    let satBenchmark: Int?
    let actBenchmark: Int?
    let rigorBenchmark: Int?
    let isInferred: Bool
    let sourceFields: [String]
    let sourceURL: URL?
    let sourceNote: String
    let dataQuality: Double

    var id: String { collegeID }
}

struct CollegeGateRule: Identifiable, Hashable, Codable {
    let id: String
    let collegeID: String
    let type: GateRuleType
    let title: String
    let detail: String
    let isOfficial: Bool
    let sourceURL: URL?
    let minimumSAT: Int?
    let minimumTOEFL: Int?
    let requiredRound: ApplicationRound?
    let allowedRounds: [ApplicationRound]
    let earlyActionAdjustment: Double?
    let earlyDecisionAdjustment: Double?
    let affectedMajor: MajorCategory?
    let minimumStrengthBand: Int?
}

struct DataSourceRecord: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let url: URL
    let role: String
    let refreshMode: String
    let confidence: String
    let note: String

    func matchesSourceQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }

        return name.localizedCaseInsensitiveContains(trimmed) ||
            role.localizedCaseInsensitiveContains(trimmed) ||
            refreshMode.localizedCaseInsensitiveContains(trimmed) ||
            confidence.localizedCaseInsensitiveContains(trimmed) ||
            note.localizedCaseInsensitiveContains(trimmed) ||
            url.absoluteString.localizedCaseInsensitiveContains(trimmed)
    }
}

struct HighSchoolContext: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let city: String
    let admitRankingBand: Int
    let resources: Int
    let counseling: Int
    let top30TrackRecord: Int
    let transparency: Int

    var calibration: Double {
        let weightedScore = (
            Double(top30TrackRecord) * 0.50 +
            Double(resources) * 0.25 +
            Double(counseling) * 0.15 +
            Double(transparency) * 0.10
        ) / 5.0
        let bandOffset: Double
        let bandCap: Double
        switch admitRankingBand {
        case 1:
            bandOffset = 0.010
            bandCap = 0.075
        case 2:
            bandOffset = 0.002
            bandCap = 0.045
        case 3:
            bandOffset = -0.006
            bandCap = 0.025
        case 4:
            bandOffset = -0.014
            bandCap = 0.010
        default:
            bandOffset = -0.022
            bandCap = 0.0
        }
        let rawAdjustment = (weightedScore - 0.60) * 0.16 + bandOffset
        return min(bandCap, max(-0.040, rawAdjustment))
    }
}

struct StudentProfile: Hashable, Codable {
    static let maximumALevelSubjectCount = 5

    var applicantStatus: ApplicantStatus
    var gradeScale: GradeScale
    var gpaPercent: Double
    var gpaFourPoint: Double
    var gpaFivePoint: Double
    var letterGrade: LetterGradeBand
    var classRankPercentile: Double
    var curriculum: CurriculumType
    var rigor: Int
    var curriculumGradeScale: GradeScale
    var apCourseCount: Int
    var apAverageScore: Double
    var ibPredictedScore: Int
    var aLevelAStarCount: Int
    var aLevelACount: Int
    var aLevelBCount: Int
    var chineseCurriculumScore: Double
    var chineseCurriculumGPAFourPoint: Double
    var chineseCurriculumGPAFivePoint: Double
    var chineseCurriculumLetterGrade: LetterGradeBand
    var sat: Int?
    var act: Int?
    var toefl: Int?
    var ielts: Double?
    var testOptional: Bool
    var activities: Int
    var research: Int
    var honors: Int
    var essay: Int
    var recommendations: Int
    var highSchoolID: String
    var major: MajorCategory
    var round: ApplicationRound
    var needsAid: Bool
    var hasPortfolio: Bool
    var includeLiberalArtsColleges: Bool
    var requestedSchoolCount: Int

    static let sample = StudentProfile(
        applicantStatus: .chineseInternational,
        gradeScale: .percent,
        gpaPercent: 92,
        gpaFourPoint: 3.7,
        gpaFivePoint: 4.5,
        letterGrade: .aMinus,
        classRankPercentile: 12,
        curriculum: .ap,
        rigor: 4,
        curriculumGradeScale: .percent,
        apCourseCount: 6,
        apAverageScore: 4.5,
        ibPredictedScore: 40,
        aLevelAStarCount: 2,
        aLevelACount: 2,
        aLevelBCount: 0,
        chineseCurriculumScore: 92,
        chineseCurriculumGPAFourPoint: 3.7,
        chineseCurriculumGPAFivePoint: 4.5,
        chineseCurriculumLetterGrade: .aMinus,
        sat: 1510,
        act: nil,
        toefl: 108,
        ielts: nil,
        testOptional: false,
        activities: 4,
        research: 3,
        honors: 4,
        essay: 3,
        recommendations: 4,
        highSchoolID: "unknown",
        major: .computerScience,
        round: .regularDecision,
        needsAid: false,
        hasPortfolio: false,
        includeLiberalArtsColleges: true,
        requestedSchoolCount: 12
    )

    var aLevelSubjectCount: Int {
        aLevelAStarCount + aLevelACount + aLevelBCount
    }

    var cappedALevelGradeCounts: (aStar: Int, a: Int, b: Int) {
        var remaining = Self.maximumALevelSubjectCount
        let aStar = min(max(0, aLevelAStarCount), remaining)
        remaining -= aStar
        let a = min(max(0, aLevelACount), remaining)
        remaining -= a
        let b = min(max(0, aLevelBCount), remaining)
        return (aStar, a, b)
    }

    mutating func clampALevelSubjectCounts() {
        let capped = cappedALevelGradeCounts
        aLevelAStarCount = capped.aStar
        aLevelACount = capped.a
        aLevelBCount = capped.b
    }
}

enum ProfileCompletionImpact: String, Hashable, Codable {
    case gate = "硬门槛"
    case probability = "概率计算"
    case confidence = "资料完整度"
    case portfolio = "选校策略"
}

struct ProfileCompletionPrompt: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let impact: ProfileCompletionImpact
}

extension StudentProfile {
    func completionPrompts(selectedCollegeIDs: Set<String>) -> [ProfileCompletionPrompt] {
        var prompts: [ProfileCompletionPrompt] = []

        if selectedCollegeIDs.isEmpty {
            prompts.append(ProfileCompletionPrompt(
                id: "selected-schools",
                title: "选择学校组合",
                detail: "手动选择学校，或点击自动推荐组合后再计算；空组合不会隐式生成推荐。",
                systemImage: "building.columns",
                impact: .portfolio
            ))
        }

        if applicantStatus.requiresEnglishProof && toefl == nil && ielts == nil {
            prompts.append(ProfileCompletionPrompt(
                id: "english-proof",
                title: "补充 TOEFL 或 IELTS",
                detail: "国际生英语硬门槛接受任一语言成绩；缺失时部分学校会被阻断。",
                systemImage: "textformat.abc",
                impact: .gate
            ))
        }

        if !testOptional && sat == nil && act == nil {
            prompts.append(ProfileCompletionPrompt(
                id: "standardized-test",
                title: "补充 SAT/ACT 或选择不提交",
                detail: "若计划提交标化，请填写 SAT 或 ACT；若不提交，请开启 Test Optional，系统会忽略残留分数。",
                systemImage: "checklist.checked",
                impact: .gate
            ))
        }

        if highSchoolID == "unknown" {
            prompts.append(ProfileCompletionPrompt(
                id: "high-school-context",
                title: "确认高中背景",
                detail: "当前使用其他/手动评估学校的保守代理；真实学校资源和升学记录会影响校准。",
                systemImage: "graduationcap",
                impact: .probability
            ))
        }

        if major == .arts && !hasPortfolio {
            prompts.append(ProfileCompletionPrompt(
                id: "arts-portfolio",
                title: "补充艺术作品集状态",
                detail: "艺术方向缺少作品集会触发作品集门槛，概率可能直接归零。",
                systemImage: "paintpalette",
                impact: .gate
            ))
        }

        if curriculum == .ap && apCourseCount == 0 {
            prompts.append(ProfileCompletionPrompt(
                id: "ap-evidence",
                title: "补充 AP 课程证据",
                detail: "AP 门数为 0 时，AP 平均分不会计入课程体系成绩。",
                systemImage: "books.vertical",
                impact: .probability
            ))
        }

        if curriculum == .alevel && aLevelAStarCount + aLevelACount + aLevelBCount == 0 {
            prompts.append(ProfileCompletionPrompt(
                id: "alevel-evidence",
                title: "补充 A-Level 科目",
                detail: "A-Level 科目数为 0 会按缺少课程证据保守处理。",
                systemImage: "list.bullet.clipboard",
                impact: .probability
            ))
        }

        if curriculum == .alevel && aLevelSubjectCount > StudentProfile.maximumALevelSubjectCount {
            prompts.append(ProfileCompletionPrompt(
                id: "alevel-subject-cap",
                title: "修正 A-Level 科目数",
                detail: "A-Level A*/A/B 科目合计最多 \(StudentProfile.maximumALevelSubjectCount) 门，超出部分不会提高课程体系成绩。",
                systemImage: "exclamationmark.triangle",
                impact: .probability
            ))
        }

        if needsAid && applicantStatus.isInternational {
            prompts.append(ProfileCompletionPrompt(
                id: "aid-detail",
                title: "确认国际生资助策略",
                detail: "当前只记录是否申请资助；若目标校 need-aware 或资源有限，建议单独核对资助需求强度。",
                systemImage: "dollarsign.circle",
                impact: .probability
            ))
        }

        return prompts
    }
}

struct GateResult: Hashable {
    let passed: Bool
    let failedRules: [CollegeGateRule]
    let inferredRules: [CollegeGateRule]
    let confidenceImpact: Double
}

struct ChanceFactor: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: Double
    let detail: String
}

struct ChanceResult: Identifiable, Hashable {
    var id: String { college.id }

    let college: College
    let baseRate: Double
    let adjustedProbability: Double
    let confidence: ConfidenceLabel
    let bucket: RecommendationBucket
    let factors: [ChanceFactor]
    let warnings: [String]
    let gateResult: GateResult
}

struct RecommendationStep: Hashable {
    let order: Int
    let result: ChanceResult
    let rankScore: Double
    let confidenceMultiplier: Double
    let baseExpectedValue: Double
    let sameTierDiscount: Double
    let marginalExpectedValue: Double
}

struct PortfolioBucketCounts: Hashable {
    let likely: Int
    let target: Int
    let reach: Int
    let blocked: Int

    var total: Int {
        likely + target + reach + blocked
    }
}

struct PortfolioResult: Hashable {
    let profileSnapshot: StudentProfile
    let selectedCollegeIDs: Set<String>
    let schoolResults: [ChanceResult]
    let recommendedSchools: [College]
    let recommendationSteps: [RecommendationStep]
    let selectionSource: PortfolioSelectionSource
    let selectedBucketCounts: PortfolioBucketCounts
    let selectionWarnings: [String]
    let recommendationWarnings: [String]
    let t10AtLeastOne: Double
    let t11T30AtLeastOne: Double
    let t30AtLeastOne: Double
    let t50AtLeastOne: Double
    let liberalArtsT10AtLeastOne: Double
    let liberalArtsT30AtLeastOne: Double
    let selectedAtLeastOne: Double
    let profileScore: Double
    let recommendationExpectedValueTotal: Double
    let generatedAt: Date

    var calculatedCollegeIDs: Set<String> {
        Set(schoolResults.map(\.college.id))
    }
}
