import Foundation

struct QuotaFetcher {
    static func fetchQuota() -> QuotaData? {
        let task = Process()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        task.executableURL = URL(fileURLWithPath: "\(home)/.local/bin/agy")
        task.arguments = ["--output-format", "json", "-p", "/usage"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // discard stderr
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let decoder = JSONDecoder()
            let usageResponse = try decoder.decode(UsageResponse.self, from: data)
            
            var result = QuotaData(
                geminiWeeklyRemaining: 0, geminiWeeklyResetTime: "",
                gemini5hRemaining: 0, gemini5hResetTime: "",
                claudeWeeklyRemaining: 0, claudeWeeklyResetTime: "",
                claude5hRemaining: 0, claude5hResetTime: ""
            )
            
            for group in usageResponse.command.data.groups {
                if group.name == "Gemini Models" {
                    for bucket in group.buckets {
                        if bucket.id == "gemini-weekly" {
                            result.geminiWeeklyRemaining = bucket.remaining_fraction ?? 0
                            result.geminiWeeklyResetTime = bucket.reset_time ?? ""
                        } else if bucket.id == "gemini-5h" {
                            result.gemini5hRemaining = bucket.remaining_fraction ?? 0
                            result.gemini5hResetTime = bucket.reset_time ?? ""
                        }
                    }
                } else if group.name == "Claude and GPT models" {
                    for bucket in group.buckets {
                        if bucket.id == "3p-weekly" {
                            result.claudeWeeklyRemaining = bucket.remaining_fraction ?? 0
                            result.claudeWeeklyResetTime = bucket.reset_time ?? ""
                        } else if bucket.id == "3p-5h" {
                            result.claude5hRemaining = bucket.remaining_fraction ?? 0
                            result.claude5hResetTime = bucket.reset_time ?? ""
                        }
                    }
                }
            }
            
            return result
            
        } catch {
            print("Failed to run agy or decode json: \(error)")
            return nil
        }
    }
}
