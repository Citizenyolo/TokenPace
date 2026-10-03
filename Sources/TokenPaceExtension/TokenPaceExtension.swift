import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: QuotaData(
            geminiWeeklyRemaining: 0.8651, geminiWeeklyResetTime: "2026-10-01T15:10:55Z",
            gemini5hRemaining: 0.9199, gemini5hResetTime: "2026-09-30T18:09:47Z",
            claudeWeeklyRemaining: 0.7891, claudeWeeklyResetTime: "2026-10-01T15:10:13Z",
            claude5hRemaining: 1.0, claude5hResetTime: "2026-09-30T18:15:26Z"
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var data: QuotaData? = nil
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let fileURL = homeDir.appendingPathComponent("Documents/quota.json")
        
        // Atomically read data using a single FileHandle snapshot
        if let handle = try? FileHandle(forReadingFrom: fileURL) {
            if let saved = try? handle.readToEnd() {
                data = try? JSONDecoder().decode(QuotaData.self, from: saved)
            }
            try? handle.close()
        }
        
        var entries: [SimpleEntry] = []
        let currentDate = Date()
        
        // M5: Ensure stale transition is actually in the timeline even if reset occurs near end
        // Generate an entry every minute for 120 minutes.
        for minuteOffset in 0 ..< 120 {
            if let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate) {
                entries.append(SimpleEntry(date: entryDate, data: data))
            }
        }
        
        // Ensure reset transitions are in the timeline
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let d = data {
            let resetStrings = [d.geminiWeeklyResetTime, d.gemini5hResetTime, d.claudeWeeklyResetTime, d.claude5hResetTime]
            for rString in resetStrings {
                if let rDate = formatter.date(from: rString), rDate > currentDate, rDate <= currentDate.addingTimeInterval(120 * 60) {
                    entries.append(SimpleEntry(date: rDate, data: data))
                }
            }
        }
        
        // Sort entries by date to be safe
        entries.sort { $0.date < $1.date }
        
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let data: QuotaData?
}

struct PacingIndicator: View {
    let cachedPercentage: Double
    let resetTimeString: String
    let currentDate: Date
    let cycleDurationSeconds: TimeInterval
    
    var indicatorText: (String, Color)? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let cycleEnd = formatter.date(from: resetTimeString) else { return nil }
        
        if currentDate >= cycleEnd {
            return nil // Data is stale; do not imply pacing from expired data
        }
        
        let cycleStart = cycleEnd.addingTimeInterval(-cycleDurationSeconds)
        let timeElapsed = currentDate.timeIntervalSince(cycleStart)
        
        let actualPct = cachedPercentage
        
        let idealPct: Double
        if timeElapsed >= cycleDurationSeconds || timeElapsed <= 0 {
            idealPct = 1.0
        } else {
            idealPct = 1.0 - (timeElapsed / cycleDurationSeconds)
        }
        
        let deviation = actualPct - idealPct
        let deviationInt = Int(round(deviation * 100))
        
        let color: Color
        if deviationInt > 2 {
            color = .green
        } else if deviationInt < -2 {
            color = .red
        } else {
            color = .blue
        }
        
        let sign = deviationInt > 0 ? "+" : ""
        return ("\(sign)\(deviationInt)%", color)
    }

    var body: some View {
        if let info = indicatorText {
            Text(info.0).foregroundColor(info.1).bold()
        } else {
            EmptyView()
        }
    }
}

struct TokenPaceEntryView : View {
    var entry: Provider.Entry
    
    // M1 Fix: strictly conservative reset text. Never fabricate availability.
    func formatRefreshText(from dateString: String, currentDate: Date) -> (String, Color) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let targetDate = formatter.date(from: dateString) else {
            return ("Unknown reset time", .secondary)
        }
        
        let timeInterval = targetDate.timeIntervalSince(currentDate)
        
        if timeInterval <= 0 {
            return ("Data stale", .secondary)
        }
        
        let totalHours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        
        if totalHours >= 24 {
            let days = totalHours / 24
            let remainingHours = totalHours % 24
            let dayString = days == 1 ? "day" : "days"
            
            if remainingHours > 0 {
                return ("Resets in \(days) \(dayString) \(remainingHours)h \(minutes)m", .green)
            } else {
                return ("Resets in \(days) \(dayString) \(minutes)m", .green)
            }
        } else if totalHours > 0 {
            return ("Resets in \(totalHours)h \(minutes)m", .green)
        } else {
            return ("Resets in \(minutes)m", .green)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let d = entry.data {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GEMINI MODELS").bold()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Five Hour Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(cachedPercentage: d.gemini5hRemaining, resetTimeString: d.gemini5hResetTime, currentDate: entry.date, cycleDurationSeconds: 5 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            QuotaBar(percentage: d.gemini5hRemaining)
                            Text("] ")
                            Text(String(format: "%.0f%%", d.gemini5hRemaining * 100)).foregroundColor(.primary).bold()
                        }
                        let refreshInfo = formatRefreshText(from: d.gemini5hResetTime, currentDate: entry.date)
                        Text("  " + refreshInfo.0).foregroundColor(refreshInfo.1)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Weekly Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(cachedPercentage: d.geminiWeeklyRemaining, resetTimeString: d.geminiWeeklyResetTime, currentDate: entry.date, cycleDurationSeconds: 7 * 24 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            QuotaBar(percentage: d.geminiWeeklyRemaining)
                            Text("] ")
                            Text(String(format: "%.0f%%", d.geminiWeeklyRemaining * 100)).foregroundColor(.primary).bold()
                        }
                        let refreshInfo = formatRefreshText(from: d.geminiWeeklyResetTime, currentDate: entry.date)
                        Text("  " + refreshInfo.0).foregroundColor(refreshInfo.1)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("CLAUDE AND GPT MODELS").bold()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Five Hour Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(cachedPercentage: d.claude5hRemaining, resetTimeString: d.claude5hResetTime, currentDate: entry.date, cycleDurationSeconds: 5 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            QuotaBar(percentage: d.claude5hRemaining)
                            Text("] ")
                            Text(String(format: "%.0f%%", d.claude5hRemaining * 100)).foregroundColor(.primary).bold()
                        }
                        let refreshInfo = formatRefreshText(from: d.claude5hResetTime, currentDate: entry.date)
                        Text("  " + refreshInfo.0).foregroundColor(refreshInfo.1)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Weekly Limit Remaining").bold()
                            Spacer()
                            PacingIndicator(cachedPercentage: d.claudeWeeklyRemaining, resetTimeString: d.claudeWeeklyResetTime, currentDate: entry.date, cycleDurationSeconds: 7 * 24 * 3600)
                        }
                        HStack(spacing: 0) {
                            Text("  [")
                            QuotaBar(percentage: d.claudeWeeklyRemaining)
                            Text("] ")
                            Text(String(format: "%.0f%%", d.claudeWeeklyRemaining * 100)).foregroundColor(.primary).bold()
                        }
                        let refreshInfo = formatRefreshText(from: d.claudeWeeklyResetTime, currentDate: entry.date)
                        Text("  " + refreshInfo.0).foregroundColor(refreshInfo.1)
                    }
                }
            } else {
                Text("No data yet. Waiting for update...")
            }
        }
        .font(.system(size: 14, weight: .regular, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .foregroundColor(.primary)
    }
}

@main
struct TokenPaceExtension: Widget {
    let kind: String = "TokenPaceExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TokenPaceEntryView(entry: entry)
                .containerBackground(Color(NSColor.windowBackgroundColor), for: .widget)
        }
        .configurationDisplayName("TokenPace")
        .description("Displays Agy CLI quota usage.")
        .supportedFamilies([.systemLarge])
    }
}

struct QuotaBar: View {
    let percentage: Double
    let totalBlocks = 25
    
    var body: some View {
        let filled = Int(round(percentage * Double(totalBlocks)))
        let empty = totalBlocks - filled
        let filledStr = String(repeating: "█", count: max(0, filled))
        let emptyStr = String(repeating: "░", count: max(0, empty))
        
        let barColor: Color = {
            if percentage >= 0.50 { return .green }
            else if percentage >= 0.25 { return .yellow }
            else { return .red }
        }()
        
        HStack(spacing: 0) {
            Text(filledStr).foregroundColor(barColor)
            Text(emptyStr).foregroundColor(.gray.opacity(0.5))
        }
    }
}
