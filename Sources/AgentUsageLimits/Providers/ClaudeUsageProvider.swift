import Foundation
import AppKit
import Darwin

/// Provider for Anthropic Claude (Claude Desktop / Claude Code / Claude CLI)
/// Implements live OAuth API usage probing and CLI fallback with automatic token refresh.
public final class ClaudeUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "claude"
    public let displayName: String = "Claude"
    public let iconSymbol: String = "claude.sun"
    
    /// Short sliding window duration in hours (Claude typical limit is 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    // API Endpoints
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    
    // OAuth client configuration for Claude Code
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let scopes = "user:profile user:inference user:sessions:claude_code"
    
    // Rate limit window caching
    private var rateLimitRetryAt: Date?
    private let rateLimitLock = NSLock()
    
    // Credentials caching with TTL
    private var cachedCredentials: ClaudeCredentialResult?
    private var credentialCacheDate: Date?
    private let credentialLock = NSLock()
    private static let credentialTTL: TimeInterval = 5 * 60 // 5 minutes
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    // MARK: - Activity Detection (GUI + CLI)
    
    /// Checks whether Claude is currently active (App UI or CLI processes running)
    public var isActive: Bool {
        return isGUIRunning || isCLIRunning
    }
    
    public var isTokenAvailable: Bool {
        return loadCredentials() != nil
    }
    
    /// 1. Checks if Claude Desktop App UI is running
    public var isGUIRunning: Bool {
        let isAppRunning = NSWorkspace.shared.runningApplications.contains { app in
            let bundleId = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            let execName = app.executableURL?.lastPathComponent.lowercased() ?? ""
            return bundleId.contains("com.anthropic.claude") ||
                   name == "claude" ||
                   execName == "claude"
        }
        return isAppRunning
    }
    
    /// 2. Checks if Claude CLI / background agent processes are running
    public var isCLIRunning: Bool {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytesUsed = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let count = Int(bytesUsed) / MemoryLayout<pid_t>.size
        guard count > 0 else { return false }
        
        let targetCLIProcesses: Set<String> = [
            "claude",
            "claude-code"
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
    
    // MARK: - Quota Fetching
    
    public func fetchUsage() async throws -> ProviderUsage {
        let now = Date()
        let active = self.isActive
        
        guard active else {
            return buildInactiveUsage(now: now)
        }
        
        // 1. Try OAuth usage API (official Anthropic endpoint)
        if let apiQuota = await fetchAPIUsage() {
            return buildProviderUsage(from: apiQuota, isActive: true, now: now)
        }
        
        // 2. Try Claude Desktop App live telemetry history
        if let desktopQuota = loadFromDesktopHistory(now: now) {
            return buildProviderUsage(from: desktopQuota, isActive: true, now: now)
        }
        
        // 3. Try CLI `/usage` fallback if available
        if let cliQuota = await probeCLIUsage() {
            return buildProviderUsage(from: cliQuota, isActive: true, now: now)
        }
        
        // Fallback: Empty active quota if unable to parse live data
        return buildEmptyActiveUsage(now: now)
    }
    
    // MARK: - Claude Desktop Live Telemetry Probing
    
    private func loadFromDesktopHistory(now: Date) -> ParsedClaudeQuota? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/Library/Application Support/Claude/plan-usage-history.json"
        
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = json["samples"] as? [[String: Any]],
              let latest = samples.last,
              let u = latest["u"] as? [String: Any] else {
            return nil
        }
        
        let fhUsed = Double(u["fh"] as? Int ?? 0)
        let sdUsed = Double(u["sd"] as? Int ?? 0)
        
        // Find when current 5h window started by looking back for the start of positive usage
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        var sessionStartTime: Date? = nil
        
        for s in samples.reversed() {
            guard let tMs = s["t"] as? Double else { continue }
            let tDate = Date(timeIntervalSince1970: tMs / 1000)
            guard tDate > fiveHoursAgo else { break }
            
            let uSample = s["u"] as? [String: Any]
            let fh = uSample?["fh"] as? Int ?? 0
            if fh > 0 {
                sessionStartTime = tDate
            } else {
                break
            }
        }
        
        var shortResetDate: Date? = nil
        if let sessionStart = sessionStartTime {
            let candidate = sessionStart.addingTimeInterval(5 * 3600)
            if candidate > now {
                shortResetDate = candidate
            }
        }
        
        // Find when current 7d weekly window started
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86400)
        var weeklyStartTime: Date? = nil
        
        for s in samples.reversed() {
            guard let tMs = s["t"] as? Double else { continue }
            let tDate = Date(timeIntervalSince1970: tMs / 1000)
            guard tDate > sevenDaysAgo else { break }
            
            let uSample = s["u"] as? [String: Any]
            let sd = uSample?["sd"] as? Int ?? 0
            if sd > 0 {
                weeklyStartTime = tDate
            } else {
                break
            }
        }
        
        var weeklyResetDate: Date? = nil
        if let weeklyStart = weeklyStartTime {
            let candidate = weeklyStart.addingTimeInterval(7 * 86400)
            if candidate > now {
                weeklyResetDate = candidate
            }
        }
        
        return ParsedClaudeQuota(
            shortUsedPercent: max(0.0, min(100.0, fhUsed)),
            shortResetDate: shortResetDate,
            weeklyUsedPercent: max(0.0, min(100.0, sdUsed)),
            weeklyResetDate: weeklyResetDate
        )
    }
    
    // MARK: - API Usage Probing
    
    private struct ParsedClaudeQuota {
        let shortUsedPercent: Double
        let shortResetDate: Date?
        let weeklyUsedPercent: Double
        let weeklyResetDate: Date?
    }
    
    private func isRateLimited() -> Bool {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        if let retryAt = rateLimitRetryAt {
            if retryAt > Date() {
                return true
            }
            rateLimitRetryAt = nil
        }
        return false
    }
    
    private func setRateLimit(retryAfter: TimeInterval) {
        rateLimitLock.lock()
        defer { rateLimitLock.unlock() }
        rateLimitRetryAt = Date().addingTimeInterval(retryAfter)
    }
    
    private func fetchAPIUsage() async -> ParsedClaudeQuota? {
        // Honor rate limit backoff if present
        if isRateLimited() {
            return nil
        }
        
        guard var credentials = loadCachedOrFreshCredentials() else {
            return nil
        }
        
        // Refresh token if needed
        if needsRefresh(credentials.oauth) && credentials.oauth.refreshToken != nil {
            if let refreshed = await refreshToken(credentials) {
                credentials = refreshed
            }
        }
        
        // Make usage API request
        let result = await executeUsageRequest(accessToken: credentials.oauth.accessToken)
        
        switch result {
        case .success(let quota):
            return quota
            
        case .authError:
            // Token might be invalidated, attempt one refresh
            if credentials.oauth.refreshToken != nil,
               let refreshed = await refreshToken(credentials) {
                if case .success(let quota) = await executeUsageRequest(accessToken: refreshed.oauth.accessToken) {
                    return quota
                }
            }
            clearCredentialCache()
            return nil
            
        case .rateLimited(let retryAfter):
            setRateLimit(retryAfter: retryAfter)
            return nil
            
        case .failure:
            return nil
        }
    }
    
    private enum APIResult {
        case success(ParsedClaudeQuota)
        case authError
        case rateLimited(TimeInterval)
        case failure
    }
    
    private func executeUsageRequest(accessToken: String) async -> APIResult {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("agent-usage-limits", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12.0
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .failure
        }
        
        if http.statusCode == 401 || http.statusCode == 403 {
            return .authError
        }
        
        if http.statusCode == 429 {
            let retryAfter = parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")) ?? 300
            return .rateLimited(retryAfter)
        }
        
        guard (200..<300).contains(http.statusCode) else {
            return .failure
        }
        
        if let quota = parseAPIResponse(data) {
            return .success(quota)
        }
        
        return .failure
    }
    
    private func parseAPIResponse(_ data: Data) -> ParsedClaudeQuota? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // 1. Session / Short-term limit: five_hour
        let fiveHour = json["five_hour"] as? [String: Any]
        let fiveHourRaw = (fiveHour?["utilization"] as? NSNumber)?.doubleValue
        let fiveHourUsed = normalizePercent(fiveHourRaw)
        let fiveHourReset = (fiveHour?["resets_at"] as? String).flatMap(parseISODate)
        
        // 2. Weekly limit: seven_day (or fallback to sonnet/opus/generic limits)
        var weeklyUsed: Double = 0.0
        var weeklyReset: Date? = nil
        
        if let sevenDay = json["seven_day"] as? [String: Any] {
            weeklyUsed = normalizePercent((sevenDay["utilization"] as? NSNumber)?.doubleValue)
            weeklyReset = (sevenDay["resets_at"] as? String).flatMap(parseISODate)
        } else if let sonnet = json["seven_day_sonnet"] as? [String: Any] {
            weeklyUsed = normalizePercent((sonnet["utilization"] as? NSNumber)?.doubleValue)
            weeklyReset = (sonnet["resets_at"] as? String).flatMap(parseISODate)
        } else if let opus = json["seven_day_opus"] as? [String: Any] {
            weeklyUsed = normalizePercent((opus["utilization"] as? NSNumber)?.doubleValue)
            weeklyReset = (opus["resets_at"] as? String).flatMap(parseISODate)
        } else if let limits = json["limits"] as? [[String: Any]] {
            for limit in limits {
                let kind = (limit["kind"] as? String)?.lowercased() ?? ""
                if kind.contains("weekly") || kind.contains("seven_day") {
                    let raw = (limit["percent"] as? NSNumber)?.doubleValue ?? (limit["utilization"] as? NSNumber)?.doubleValue
                    weeklyUsed = normalizePercent(raw)
                    weeklyReset = (limit["resets_at"] as? String).flatMap(parseISODate)
                    break
                }
            }
        }
        
        return ParsedClaudeQuota(
            shortUsedPercent: fiveHourUsed,
            shortResetDate: fiveHourReset,
            weeklyUsedPercent: weeklyUsed,
            weeklyResetDate: weeklyReset
        )
    }
    
    private func normalizePercent(_ value: Double?) -> Double {
        guard let value = value else { return 0.0 }
        // If API returns fraction between 0.0 and 1.0 (e.g. 0.20 for 20%), convert to 0..100
        if value > 0.0 && value <= 1.0 {
            return value * 100.0
        }
        return max(0.0, min(100.0, value))
    }
    
    // MARK: - Token Refresh
    
    private func refreshToken(_ credentials: ClaudeCredentialResult) async -> ClaudeCredentialResult? {
        guard let refreshToken = credentials.oauth.refreshToken else { return nil }
        
        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0
        
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": Self.scopes
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String, !newAccessToken.isEmpty else {
            return nil
        }
        
        var updated = credentials
        updated.oauth.accessToken = newAccessToken
        if let newRefresh = json["refresh_token"] as? String {
            updated.oauth.refreshToken = newRefresh
        }
        if let expiresIn = json["expires_in"] as? Double {
            updated.oauth.expiresAt = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000
        }
        
        saveCredentials(updated)
        cacheCredentials(updated)
        return updated
    }
    
    private func needsRefresh(_ oauth: ClaudeOAuthCredentials) -> Bool {
        guard let expiresAt = oauth.expiresAt else { return false }
        let nowMs = Date().timeIntervalSince1970 * 1000
        return nowMs + (5 * 60 * 1000) >= expiresAt
    }
    
    // MARK: - Credentials Management
    
    private struct ClaudeOAuthCredentials: Equatable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Double?
        var subscriptionType: String?
    }
    
    private enum CredentialSource {
        case file(String)
        case keychain(String)
        case environment
    }
    
    private struct ClaudeCredentialResult {
        var oauth: ClaudeOAuthCredentials
        let source: CredentialSource
        var fullData: [String: Any]
    }
    
    private func loadCachedOrFreshCredentials() -> ClaudeCredentialResult? {
        credentialLock.lock()
        if let cached = cachedCredentials,
           let cacheDate = credentialCacheDate,
           Date().timeIntervalSince(cacheDate) < Self.credentialTTL {
            credentialLock.unlock()
            return cached
        }
        credentialLock.unlock()
        
        guard let fresh = loadCredentials() else { return nil }
        cacheCredentials(fresh)
        return fresh
    }
    
    private func cacheCredentials(_ creds: ClaudeCredentialResult) {
        credentialLock.lock()
        cachedCredentials = creds
        credentialCacheDate = Date()
        credentialLock.unlock()
    }
    
    private func clearCredentialCache() {
        credentialLock.lock()
        cachedCredentials = nil
        credentialCacheDate = nil
        credentialLock.unlock()
    }
    
    private func loadCredentials() -> ClaudeCredentialResult? {
        // 1. Try files (~/.claude/.credentials.json, ~/.claude.json)
        if let fileResult = loadFromFile() {
            return fileResult
        }
        
        // 2. Try Keychain services
        if let keychainResult = loadFromKeychain() {
            return keychainResult
        }
        
        // 3. Fallback to environment variable
        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envToken.isEmpty {
            let oauth = ClaudeOAuthCredentials(accessToken: envToken, refreshToken: nil, expiresAt: nil, subscriptionType: nil)
            return ClaudeCredentialResult(oauth: oauth, source: .environment, fullData: [:])
        }
        
        return nil
    }
    
    private func loadFromFile() -> ClaudeCredentialResult? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "\(home)/.claude/.credentials.json",
            "\(home)/.claude.json"
        ]
        
        for path in candidatePaths {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            // Check claudeAiOauth
            if let oauthDict = json["claudeAiOauth"] as? [String: Any],
               let rawToken = oauthDict["accessToken"] as? String {
                let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    let oauth = ClaudeOAuthCredentials(
                        accessToken: token,
                        refreshToken: oauthDict["refreshToken"] as? String,
                        expiresAt: oauthDict["expiresAt"] as? Double,
                        subscriptionType: oauthDict["subscriptionType"] as? String
                    )
                    return ClaudeCredentialResult(oauth: oauth, source: .file(path), fullData: json)
                }
            }
            
            // Check oauth or root accessToken
            let oauthDict = (json["oauth"] as? [String: Any]) ?? json
            if let rawToken = (oauthDict["accessToken"] as? String) ?? (oauthDict["access_token"] as? String) {
                let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    let oauth = ClaudeOAuthCredentials(
                        accessToken: token,
                        refreshToken: (oauthDict["refreshToken"] as? String) ?? (oauthDict["refresh_token"] as? String),
                        expiresAt: (oauthDict["expiresAt"] as? Double) ?? (oauthDict["expires_at"] as? Double),
                        subscriptionType: (oauthDict["subscriptionType"] as? String) ?? (oauthDict["subscription_type"] as? String)
                    )
                    return ClaudeCredentialResult(oauth: oauth, source: .file(path), fullData: json)
                }
            }
        }
        
        return nil
    }
    
    private func loadFromKeychain() -> ClaudeCredentialResult? {
        let services = [
            "Claude Code-credentials",
            "Claude Code",
            "Claude",
            "com.anthropic.claude"
        ]
        
        for service in services {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", service, "-w"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { continue }
                
                guard let rawString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawString.isEmpty else { continue }
                
                let jsonData: Data?
                if rawString.hasPrefix("{") {
                    jsonData = rawString.data(using: .utf8)
                } else if let hexData = hexDecoded(rawString) {
                    jsonData = hexData
                } else {
                    jsonData = rawString.data(using: .utf8)
                }
                
                guard let validData = jsonData,
                      let json = try? JSONSerialization.jsonObject(with: validData) as? [String: Any] else {
                    if rawString.hasPrefix("sk-ant-") {
                        let oauth = ClaudeOAuthCredentials(accessToken: rawString, refreshToken: nil, expiresAt: nil, subscriptionType: nil)
                        return ClaudeCredentialResult(oauth: oauth, source: .keychain(service), fullData: [:])
                    }
                    continue
                }
                
                let oauthDict = (json["claudeAiOauth"] as? [String: Any]) ?? (json["oauth"] as? [String: Any]) ?? json
                guard let rawAccessToken = (oauthDict["accessToken"] as? String) ?? (oauthDict["access_token"] as? String) else {
                    continue
                }
                
                let token = rawAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else { continue }
                
                let oauth = ClaudeOAuthCredentials(
                    accessToken: token,
                    refreshToken: (oauthDict["refreshToken"] as? String) ?? (oauthDict["refresh_token"] as? String),
                    expiresAt: (oauthDict["expiresAt"] as? Double) ?? (oauthDict["expires_at"] as? Double),
                    subscriptionType: (oauthDict["subscriptionType"] as? String) ?? (oauthDict["subscription_type"] as? String)
                )
                
                return ClaudeCredentialResult(oauth: oauth, source: .keychain(service), fullData: json)
            } catch {
                continue
            }
        }
        
        return nil
    }
    
    private func saveCredentials(_ result: ClaudeCredentialResult) {
        var updatedData = result.fullData
        var oauthDict = (result.fullData["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauthDict["accessToken"] = result.oauth.accessToken
        if let refresh = result.oauth.refreshToken { oauthDict["refreshToken"] = refresh }
        if let expires = result.oauth.expiresAt { oauthDict["expiresAt"] = expires }
        if let sub = result.oauth.subscriptionType { oauthDict["subscriptionType"] = sub }
        updatedData["claudeAiOauth"] = oauthDict
        
        switch result.source {
        case .file(let path):
            if let data = try? JSONSerialization.data(withJSONObject: updatedData, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        case .keychain(let service):
            if let data = try? JSONSerialization.data(withJSONObject: updatedData, options: []),
               let jsonString = String(data: data, encoding: .utf8) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                process.arguments = ["add-generic-password", "-U", "-s", service, "-a", NSUserName(), "-w", jsonString]
                try? process.run()
                process.waitUntilExit()
            }
        case .environment:
            break
        }
    }
    
    // MARK: - CLI Fallback Probing
    
    private func probeCLIUsage() async -> ParsedClaudeQuota? {
        let binaryPath = findClaudeBinary()
        guard let binary = binaryPath else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["/usage", "--allowed-tools", ""]
        
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDE_CODE_OAUTH_TOKEN")
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return parseCLIOutput(text)
        } catch {
            return nil
        }
    }
    
    private func findClaudeBinary() -> String? {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.nvm/versions/node/current/bin/claude"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["claude"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        try? whichProcess.run()
        whichProcess.waitUntilExit()
        
        if whichProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let found = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !found.isEmpty {
                return found
            }
        }
        return nil
    }
    
    private func parseCLIOutput(_ text: String) -> ParsedClaudeQuota? {
        let clean = text.replacingOccurrences(of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#, with: "", options: .regularExpression)
        
        let sessionInfo = parseUsageSection(label: "Current session", text: clean)
        let weeklyInfo = parseUsageSection(label: "Current week", text: clean)
        
        guard let sessionUsed = sessionInfo.usedPercent else {
            return nil
        }
        
        return ParsedClaudeQuota(
            shortUsedPercent: sessionUsed,
            shortResetDate: sessionInfo.resetDate,
            weeklyUsedPercent: weeklyInfo.usedPercent ?? 0.0,
            weeklyResetDate: weeklyInfo.resetDate
        )
    }
    
    private func parseUsageSection(label: String, text: String) -> (usedPercent: Double?, resetDate: Date?) {
        guard let labelRange = text.range(of: label, options: [.caseInsensitive]) else {
            return (nil, nil)
        }
        let section = String(text[labelRange.lowerBound...])
        
        // Find next section boundary if any
        let nextSectionPattern = #"\n\s*(?:Current\s+session|Current\s+week|What's\s+contributing)"#
        let boundedSection: String
        if let nextMatch = section.range(of: nextSectionPattern, options: [.regularExpression], range: section.index(after: section.startIndex)..<section.endIndex) {
            boundedSection = String(section[..<nextMatch.lowerBound])
        } else {
            boundedSection = section
        }
        
        // Extract percentage: e.g. "61% used" or "39% remaining"
        var usedPercent: Double? = nil
        let pctPattern = #"(\d+(?:\.\d+)?)\s*%\s*(used|remaining|left)?"#
        if let regex = try? NSRegularExpression(pattern: pctPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: boundedSection, options: [], range: NSRange(boundedSection.startIndex..<boundedSection.endIndex, in: boundedSection)),
           let numRange = Range(match.range(at: 1), in: boundedSection) {
            let num = Double(boundedSection[numRange]) ?? 0.0
            if match.numberOfRanges > 2, let typeRange = Range(match.range(at: 2), in: boundedSection) {
                let type = boundedSection[typeRange].lowercased()
                if type == "remaining" || type == "left" {
                    usedPercent = max(0.0, min(100.0, 100.0 - num))
                } else {
                    usedPercent = max(0.0, min(100.0, num))
                }
            } else {
                usedPercent = max(0.0, min(100.0, num))
            }
        }
        
        let resetDate = parseResetDate(from: boundedSection)
        return (usedPercent, resetDate)
    }
    
    private func parseResetDate(from text: String) -> Date? {
        // 1. Try relative duration first: "in 2h 15m", "in 30m", "in 2d"
        if let relativeDate = parseRelativeDuration(from: text) {
            return relativeDate
        }
        // 2. Try absolute date/time with timezone: "Resets 1:09am (America/Chicago)"
        return parseAbsoluteDate(from: text)
    }
    
    private func parseRelativeDuration(from text: String) -> Date? {
        var totalSeconds: TimeInterval = 0
        
        if let dayMatch = text.range(of: #"(\d+)\s*d(?:ays?)?"#, options: .regularExpression),
           let days = Double(text[dayMatch].filter(\.isNumber)) {
            totalSeconds += days * 86400
        }
        if let hourMatch = text.range(of: #"(\d+)\s*h(?:ours?|r)?"#, options: .regularExpression),
           let hours = Double(text[hourMatch].filter(\.isNumber)) {
            totalSeconds += hours * 3600
        }
        if let minMatch = text.range(of: #"(\d+)\s*m(?:in(?:utes?)?)?"#, options: .regularExpression),
           let minutes = Double(text[minMatch].filter(\.isNumber)) {
            totalSeconds += minutes * 60
        }
        
        return totalSeconds > 0 ? Date().addingTimeInterval(totalSeconds) : nil
    }
    
    private func parseAbsoluteDate(from text: String) -> Date? {
        let timeZone = extractTimeZone(from: text)
        var cleaned = text
        
        if let lastResets = cleaned.range(of: "resets", options: [.caseInsensitive, .backwards]) {
            cleaned = String(cleaned[lastResets.upperBound...])
        }
        cleaned = cleaned
            .replacingOccurrences(of: #"\s*\([^)]+\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+at\s+"#, with: ", ", options: .regularExpression)
        
        let formats = [
            "MMM d, yyyy, h:mma",
            "MMM d, yyyy, ha",
            "MMM d, yyyy",
            "MMM d, h:mma",
            "MMM d, ha",
            "h:mma",
            "ha",
            "MMM d"
        ]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? .current
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return resolveToFutureDate(date, format: format, timeZone: formatter.timeZone)
            }
        }
        
        return nil
    }
    
    private func extractTimeZone(from text: String) -> TimeZone? {
        guard let match = text.range(of: #"\(([^)]+)\)"#, options: [.regularExpression, .backwards]) else {
            return nil
        }
        let content = String(text[match]).dropFirst().dropLast()
        return TimeZone(identifier: String(content).trimmingCharacters(in: .whitespaces))
    }
    
    private func resolveToFutureDate(_ parsedDate: Date, format: String, timeZone: TimeZone) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let now = Date()
        
        if format.contains("yyyy") {
            return parsedDate
        }
        
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsedDate)
        let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
        
        components.year = nowComponents.year
        if !format.contains("MMM") {
            components.month = nowComponents.month
            components.day = nowComponents.day
        }
        
        guard let candidate = calendar.date(from: components) else { return parsedDate }
        if candidate < now {
            if !format.contains("MMM") {
                return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            } else {
                return calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate
            }
        }
        return candidate
    }
    
    // MARK: - Helpers
    
    private func buildProviderUsage(from quota: ParsedClaudeQuota, isActive: Bool, now: Date) -> ProviderUsage {
        let shortWindow = QuotaWindow(
            name: "\(Int(shortWindowDurationHours))-hour limit",
            windowDurationHours: shortWindowDurationHours,
            usedPercent: quota.shortUsedPercent,
            resetDate: quota.shortResetDate
        )
        
        let weeklyWindow = QuotaWindow(
            name: "Weekly",
            windowDurationHours: 168.0,
            usedPercent: quota.weeklyUsedPercent,
            resetDate: quota.weeklyResetDate
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
    
    private func buildInactiveUsage(now: Date) -> ProviderUsage {
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
    
    private func buildEmptyActiveUsage(now: Date) -> ProviderUsage {
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
            isActive: true,
            shortWindow: shortWindow,
            weeklyWindow: weeklyWindow,
            showWeeklyInMenuBar: true,
            lastUpdated: now
        )
    }
    
    private func parseISODate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) { return date }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        return nil
    }
    
    private func parseRetryAfter(_ header: String?) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespacesAndNewlines),
              let seconds = TimeInterval(header), seconds > 0 else {
            return nil
        }
        return seconds
    }
    
    private func hexDecoded(_ hex: String) -> Data? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count % 2 == 0, trimmed.allSatisfy({ $0.isHexDigit }) else { return nil }
        
        var data = Data(capacity: trimmed.count / 2)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let nextIndex = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }
}
