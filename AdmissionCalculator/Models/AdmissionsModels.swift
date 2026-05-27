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
    var requestedSchoolCount: Int
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
        highSchoolID: "bnu_experimental",
        major: .computerScience,
        round: .regularDecision,
        needsAid: false,
        hasPortfolio: false,
        requestedSchoolCount: 12,
        requestedLikelyCount: 3,
        requestedTargetCount: 5,
        requestedReachCount: 4
    )
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
    let schoolResults: [ChanceResult]
    let recommendedSchools: [College]
    let selectedBucketCounts: PortfolioBucketCounts
    let recommendationWarnings: [String]
    let t10AtLeastOne: Double
    let t30AtLeastOne: Double
    let t50AtLeastOne: Double
    let selectedAtLeastOne: Double
    let profileScore: Double
    let generatedAt: Date
}
