import Foundation
import AppKit
import Darwin

/// Provider for Google Antigravity (AGY Agent / Gemini quotas)
/// Replicates the official Google Cloud Code quota API & Local Language Server probe
/// as used by Antigravity.
public final class AntigravityUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "antigravity"
    public let displayName: String = "Antigravity"
    public let iconSymbol: String = "antigravity.wave"
    
    /// Short sliding window duration in hours (default 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    // MARK: - Activity Detection (GUI + CLI)
    
    /// Checks whether Antigravity is currently active (Desktop App UI or CLI processes running)
    public var isActive: Bool {
        return isGUIRunning || isCLIRunning
    }
    
    public var isTokenAvailable: Bool {
        return loadKeychainToken() != nil || loadFileToken() != nil
    }
    
    /// 1. Checks if Antigravity Desktop App UI is running
    public var isGUIRunning: Bool {
        let isAppRunning = NSWorkspace.shared.runningApplications.contains { app in
            let bundleId = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            let execName = app.executableURL?.lastPathComponent.lowercased() ?? ""
            return bundleId.contains("antigravity") ||
                   bundleId.contains("com.google.antigravity") ||
                   name.contains("antigravity") ||
                   execName.contains("antigravity")
        }
        return isAppRunning
    }
    
    /// 2. Checks if Antigravity CLI / background agent processes are running
    public var isCLIRunning: Bool {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytesUsed = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let count = Int(bytesUsed) / MemoryLayout<pid_t>.size
        guard count > 0 else { return false }
        
        let targetCLIProcesses: Set<String> = [
            "agy",
            "antigravity",
            "antigravity-cli",
            "gemini-cli",
            "language_server",
            "agentapi",
            "antigravity helper"
        ]
        
        for i in 0..<count {
            let pid = pids[i]
            if pid <= 0 { continue }
            var nameBuffer = [CChar](repeating: 0, count: 1024)
            let nameLen = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            if nameLen > 0 {
                let procName = nameBuffer.withUnsafeBufferPointer { ptr in
                    String(cString: ptr.baseAddress!)
                }.lowercased()
                for target in targetCLIProcesses {
                    if procName == target || procName.contains(target) {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    // MARK: - Quota Fetching (Cloud Code + Local Server)
    
    public func fetchUsage() async throws -> ProviderUsage {
        let now = Date()
        let active = self.isActive
        
        guard active else {
            let shortWindow = QuotaWindow(
                name: "\(Int(shortWindowDurationHours))-hour limit",
                windowDurationHours: shortWindowDurationHours,
                usedPercent: 0,
                resetDate: nil
            )
            let weeklyWindow = QuotaWindow(
                name: "Weekly",
                windowDurationHours: 168.0,
                usedPercent: 0,
                resetDate: nil
            )
            return ProviderUsage(
                providerId: id,
                displayName: displayName,
                iconSymbol: iconSymbol,
                isActive: false,
                shortWindow: shortWindow,
                weeklyWindow: weeklyWindow,
                showWeeklyInMenuBar: true,
                lastUpdated: now
            )
        }
        
        // 1. Try local language server probe if app is running
        if let localQuota = await probeLocalLanguageServer() {
            return buildProviderUsage(from: localQuota, isActive: true, now: now)
        }
        
        // 2. Try Google Cloud Code endpoints with OAuth token from Keychain / file
        if let token = await loadOAuthToken() {
            if let cloudQuota = await fetchCloudCodeQuota(token: token) {
                return buildProviderUsage(from: cloudQuota, isActive: true, now: now)
            }
        }
        
        // Fallback: Default / empty if completely offline and unauthenticated
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: 0,
            resetDate: nil
        )
        let weeklyWindow = QuotaWindow(
            name: "Weekly",
            windowDurationHours: 168.0,
            usedPercent: 0,
            resetDate: nil
        )
        
        return ProviderUsage(
            providerId: id,
            displayName: displayName,
            iconSymbol: iconSymbol,
            isActive: false,
            shortWindow: shortWindow,
            weeklyWindow: weeklyWindow,
            showWeeklyInMenuBar: true,
            lastUpdated: now
        )
    }
    
    // MARK: - Local Language Server Probe
    
    private struct LocalProcessInfo {
        let pid: Int
        let csrfToken: String
        let port: Int?
    }
    
    private func detectLocalProcess() -> LocalProcessInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-lf", "language_server"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("Antigravity") || trimmed.contains("language_server") else { continue }
            
            // Extract PID
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard let firstPart = parts.first, let pid = Int(firstPart) else { continue }
            
            // Extract CSRF token (--csrf_token=xyz or --csrf_token xyz)
            guard let csrf = extractRegex(pattern: #"--csrf_token[=\s]([a-zA-Z0-9_-]+)"#, in: trimmed) else { continue }
            let portStr = extractRegex(pattern: #"--extension_server_port[=\s](\d+)"#, in: trimmed)
            let port = portStr.flatMap { Int($0) }
            
            return LocalProcessInfo(pid: pid, csrfToken: csrf, port: port)
        }
        return nil
    }
    
    private func discoverListeningPorts(pid: Int) -> [Int] {
        let lsofPath = ["/usr/sbin/lsof", "/usr/bin/lsof"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "/usr/sbin/lsof"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var ports: Set<Int> = []
        regex.enumerateMatches(in: output, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let r = Range(match.range(at: 1), in: output),
                  let val = Int(output[r]) else { return }
            ports.insert(val)
        }
        return ports.sorted()
    }
    
    private func probeLocalLanguageServer() async -> ParsedQuotaSummary? {
        guard let procInfo = detectLocalProcess() else { return nil }
        var ports = discoverListeningPorts(pid: procInfo.pid)
        if let p = procInfo.port, !ports.contains(p) {
            ports.insert(p, at: 0)
        }
        guard !ports.isEmpty else { return nil }
        
        let paths = [
            "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
            "/exa.language_server_pb.LanguageServerService/GetUserStatus"
        ]
        
        for port in ports {
            for path in paths {
                guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 3.0
                request.httpBody = Data("{}".utf8)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue(procInfo.csrfToken, forHTTPHeaderField: "X-Csrf-Token")
                request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
                
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    if let parsed = parseQuotaResponse(data) {
                        return parsed
                    }
                }
            }
        }
        return nil
    }
    
    // MARK: - Cloud Code API
    
    private func fetchCloudCodeQuota(token: String) async -> ParsedQuotaSummary? {
        let baseURLs = [
            "https://cloudcode-pa.googleapis.com",
            "https://daily-cloudcode-pa.googleapis.com"
        ]
        let path = "/v1internal:retrieveUserQuotaSummary"
        
        for base in baseURLs {
            guard let url = URL(string: base + path) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10.0
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
            
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if let parsed = parseQuotaResponse(data) {
                    return parsed
                }
            }
        }
        return nil
    }
    
    // MARK: - OAuth Token Loading
    
    private func loadOAuthToken() async -> String? {
        return loadKeychainToken() ?? loadFileToken()
    }
    
    private func loadFileToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbackPaths = [
            "\(home)/.gemini/jetski-standalone-oauth-token",
            "\(home)/.gemini/antigravity/oauth_token.json"
        ]
        
        for path in fallbackPaths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let source = (json["token"] as? [String: Any]) ?? json
                if let token = (source["access_token"] as? String) ?? (source["accessToken"] as? String), !token.isEmpty {
                    return token
                }
            }
        }
        return nil
    }
    
    private func loadKeychainToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard var text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        
        if text.hasPrefix("go-keyring-base64:") {
            let base64Str = String(text.dropFirst("go-keyring-base64:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = Data(base64Encoded: base64Str), let decoded = String(data: d, encoding: .utf8) {
                text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        guard let jsonData = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
        
        let source = (json["token"] as? [String: Any]) ?? json
        return (source["access_token"] as? String) ?? (source["accessToken"] as? String)
    }
    
    // MARK: - Quota Parsing & Assembly
    
    private struct ParsedQuotaSummary {
        let shortUsedPercent: Double
        let shortResetDate: Date?
        let weeklyUsedPercent: Double
        let weeklyResetDate: Date?
    }
    
    private func parseQuotaResponse(_ data: Data) -> ParsedQuotaSummary? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        
        let root = (json["response"] as? [String: Any]) ?? json
        guard let groups = root["groups"] as? [[String: Any]] else {
            // Check fallback for clientModelConfigs in GetUserStatus
            return parseFallbackUserStatus(root)
        }
        
        var bucketMap: [String: [String: Any]] = [:]
        for group in groups {
            if let buckets = group["buckets"] as? [[String: Any]] {
                for bucket in buckets {
                    if let bucketId = bucket["bucketId"] as? String {
                        bucketMap[bucketId] = bucket
                    }
                }
            }
        }
        
        // Match gemini-5h and gemini-weekly exclusively
        let shortBucket = bucketMap["gemini-5h"]
        let weeklyBucket = bucketMap["gemini-weekly"]
        
        let shortRemainingFraction = (shortBucket?["remainingFraction"] as? NSNumber)?.doubleValue ?? 1.0
        let weeklyRemainingFraction = (weeklyBucket?["remainingFraction"] as? NSNumber)?.doubleValue ?? 1.0
        
        let shortResetDate = (shortBucket?["resetTime"] as? String).flatMap(parseDate)
        let weeklyResetDate = (weeklyBucket?["resetTime"] as? String).flatMap(parseDate)
        
        let shortUsedPercent = max(0.0, min(100.0, (1.0 - shortRemainingFraction) * 100.0))
        let weeklyUsedPercent = max(0.0, min(100.0, (1.0 - weeklyRemainingFraction) * 100.0))
        
        return ParsedQuotaSummary(
            shortUsedPercent: shortUsedPercent,
            shortResetDate: shortResetDate,
            weeklyUsedPercent: weeklyUsedPercent,
            weeklyResetDate: weeklyResetDate
        )
    }
    
    private func parseFallbackUserStatus(_ json: [String: Any]) -> ParsedQuotaSummary? {
        guard let userStatus = json["userStatus"] as? [String: Any],
              let cascade = userStatus["cascadeModelConfigData"] as? [String: Any],
              let configs = cascade["clientModelConfigs"] as? [[String: Any]] else {
            return nil
        }
        
        for config in configs {
            if let quotaInfo = config["quotaInfo"] as? [String: Any],
               let remainingFraction = (quotaInfo["remainingFraction"] as? NSNumber)?.doubleValue {
                let resetTime = (quotaInfo["resetTime"] as? String).flatMap(parseDate)
                let used = max(0.0, min(100.0, (1.0 - remainingFraction) * 100.0))
                return ParsedQuotaSummary(
                    shortUsedPercent: used,
                    shortResetDate: resetTime,
                    weeklyUsedPercent: used,
                    weeklyResetDate: resetTime
                )
            }
        }
        return nil
    }
    
    private func buildProviderUsage(from summary: ParsedQuotaSummary, isActive: Bool, now: Date) -> ProviderUsage {
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: summary.shortUsedPercent,
            resetDate: summary.shortResetDate
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly",
            windowDurationHours: 168.0,
            usedPercent: summary.weeklyUsedPercent,
            resetDate: summary.weeklyResetDate
        )
        
        return ProviderUsage(
            providerId: id,
            displayName: displayName,
            iconSymbol: iconSymbol,
            isActive: isActive,
            shortWindow: shortWindow,
            weeklyWindow: weeklyWindow,
            showWeeklyInMenuBar: true,
            lastUpdated: now
        )
    }
    
    private func parseDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) { return date }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        if let seconds = Double(value) { return Date(timeIntervalSince1970: seconds) }
        return nil
    }
    
    private func extractRegex(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}


