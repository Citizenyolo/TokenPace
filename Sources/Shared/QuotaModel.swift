import Foundation

enum SharedFormatters {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct QuotaData: Codable, Equatable {
    var geminiWeeklyRemaining: Double
    var geminiWeeklyResetTime: String
    var gemini5hRemaining: Double
    var gemini5hResetTime: String
    
    var claudeWeeklyRemaining: Double
    var claudeWeeklyResetTime: String
    var claude5hRemaining: Double
    var claude5hResetTime: String
}

// Data models corresponding to `agy --output-format json -p "/usage"`
struct UsageResponse: Codable {
    let command: UsageCommand
}

struct UsageCommand: Codable {
    let data: UsageData
}

struct UsageData: Codable {
    let groups: [UsageGroup]
}

struct UsageGroup: Codable {
    let name: String
    let buckets: [UsageBucket]
}

struct UsageBucket: Codable {
    let id: String
    let remaining_fraction: Double?
    let reset_time: String?
}
