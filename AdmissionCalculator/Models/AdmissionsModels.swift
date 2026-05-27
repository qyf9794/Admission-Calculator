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
    case cOrBelow = "C 或以下"

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

struct AcceptanceRate: Identifiable, Hashable, Codable {
    let classYear: Int
    let rate: Double?

    var id: Int { classYear }
}

struct College: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let rank: Int
    let acceptanceRates: [AcceptanceRate]
    let sourceURL: URL
    let dataQuality: Double

    var latestAvailableRate: Double {
        acceptanceRates.sorted { $0.classYear > $1.classYear }.compactMap(\.rate).first ?? 0.12
    }

    var latestAvailableClassYear: Int {
        acceptanceRates.sorted { $0.classYear > $1.classYear }.first(where: { $0.rate != nil })?.classYear ?? 2028
    }

    var tierName: String {
        if rank <= 10 { return "T10" }
        if rank <= 30 { return "T30" }
        if rank <= 50 { return "T50" }
        return "Listed"
    }

    var tierDisplayName: String {
        tierName == "Listed" ? "综合大学 50+" : "综合大学 \(tierName)"
    }

    func matchesPickerQuery(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return true
        }
        let normalized = trimmed.uppercased()
        switch normalized {
        case "T10", "TOP10", "TOP 10":
            return rank <= 10
        case "T30", "TOP30", "TOP 30":
            return rank <= 30
        case "T50", "TOP50", "TOP 50":
            return rank <= 50
        case "LISTED", "50+", "T50+", "TOP50+", "TOP 50+", "综合大学 50+", "NATIONAL UNIVERSITIES 50+", "NU 50+":
            return rank > 50
        default:
            break
        }

        return name.localizedCaseInsensitiveContains(trimmed) ||
            id.localizedCaseInsensitiveContains(trimmed) ||
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
        if matchesPickerQuery(trimmed) || sourceURL.absoluteString.localizedCaseInsensitiveContains(trimmed) {
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
        let score = Double(resources + counseling + top30TrackRecord + transparency) / 20.0
        return (score - 0.55) * 0.18
    }
}

struct StudentProfile: Hashable, Codable {
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
    var requestedLikelyCount: Int
    var requestedTargetCount: Int
    var requestedReachCount: Int

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
        requestedLikelyCount: 3,
        requestedTargetCount: 5,
        requestedReachCount: 4
    )
}

enum ProfileCompletionImpact: String, Hashable, Codable {
    case gate = "硬门槛"
    case probability = "概率计算"
    case confidence = "置信度校准"
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
                detail: "国际生英语硬门槛接受任一语言成绩；缺失时部分学校会被阻断或降低置信度。",
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
                impact: .confidence
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
    let selectionSource: PortfolioSelectionSource
    let selectedBucketCounts: PortfolioBucketCounts
    let selectionWarnings: [String]
    let recommendationWarnings: [String]
    let t10AtLeastOne: Double
    let t30AtLeastOne: Double
    let t50AtLeastOne: Double
    let selectedAtLeastOne: Double
    let profileScore: Double
    let generatedAt: Date

    var calculatedCollegeIDs: Set<String> {
        Set(schoolResults.map(\.college.id))
    }
}
