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
        var pids = [pid_t](repeating: 0, count: 8192)
        let bytesUsed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
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
        
        // Guard against stale telemetry: Claude Desktop pauses background updates
        // if the tray icon has not been opened recently. Reject samples older than 45 minutes.
        if let sampleMs = latest["t"] as? Double {
            let sampleDate = Date(timeIntervalSince1970: sampleMs / 1000)
            let maxAge: TimeInterval = 45 * 60 // 45 minutes
            if now.timeIntervalSince(sampleDate) > maxAge {
                return nil
            }
        }
        
        let fhUsed = (u["fh"] as? NSNumber)?.doubleValue ?? Double(u["fh"] as? Int ?? 0)
        let sdUsed = (u["sd"] as? NSNumber)?.doubleValue ?? Double(u["sd"] as? Int ?? 0)
        
        // 1. Calculate 5-hour short window reset
        var shortResetDate: Date? = nil
        if fhUsed > 0 {
            let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
            var sessionStartTime: Date? = nil
            var prevSampleTime = (latest["t"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? now
            var prevSampleFH = fhUsed
            
            for s in samples.dropLast().reversed() {
                guard let tMs = s["t"] as? Double else { continue }
                let tDate = Date(timeIntervalSince1970: tMs / 1000)
                let uDict = s["u"] as? [String: Any]
                let fh = (uDict?["fh"] as? NSNumber)?.doubleValue ?? Double(uDict?["fh"] as? Int ?? 0)
                
                // Break if: gap > 5h, or fh == 0 (idle period before this session),
                // or sudden reset drop (previous window cleared)
                if prevSampleTime.timeIntervalSince(tDate) > (5 * 3600) || fh == 0 || fh < prevSampleFH * 0.3 {
                    sessionStartTime = prevSampleTime
                    break
                }
                
                sessionStartTime = tDate
                prevSampleTime = tDate
                prevSampleFH = fh
                
                if tDate < fiveHoursAgo {
                    break
                }
            }
            
            let effectiveStart = sessionStartTime ?? prevSampleTime
            let candidate = effectiveStart.addingTimeInterval(5 * 3600)
            if candidate > now {
                shortResetDate = candidate
            } else {
                // If the session has been continuously active for >= 5h, next slot rolls forward
                shortResetDate = now.addingTimeInterval(1800)
            }
        }
        
        // 2. Calculate 7-day weekly window reset
        // Claude weekly rate limits reset globally every Sunday at 05:00 UTC (07:00 AM CEST in Spain)
        var weeklyResetDate: Date? = nil
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var comps = DateComponents()
        comps.weekday = 1 // Sunday
        comps.hour = 5
        comps.minute = 0
        comps.second = 0
        weeklyResetDate = calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
        
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
        request.setValue("claude-code/0.2.29 (Darwin; arm64)", forHTTPHeaderField: "User-Agent")
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
        
        // 2. Weekly limit: inspect all candidate weekly windows (seven_day_sonnet, seven_day, seven_day_opus)
        // Select the most restrictive active limit (highest utilization) and valid reset date
        var bestWeeklyUsed: Double = 0.0
        var bestWeeklyReset: Date? = nil
        var foundWeekly = false
        
        let candidateKeys = ["seven_day_sonnet", "seven_day", "seven_day_opus"]
        for key in candidateKeys {
            guard let bucket = json[key] as? [String: Any] else { continue }
            let rawUtil = (bucket["utilization"] as? NSNumber)?.doubleValue
            let reset = (bucket["resets_at"] as? String).flatMap(parseISODate)
            
            if let util = rawUtil {
                let normalized = normalizePercent(util)
                if !foundWeekly || normalized > bestWeeklyUsed {
                    bestWeeklyUsed = normalized
                    bestWeeklyReset = reset ?? bestWeeklyReset
                    foundWeekly = true
                } else if bestWeeklyReset == nil, let reset = reset {
                    bestWeeklyReset = reset
                }
            } else if reset != nil && bestWeeklyReset == nil {
                bestWeeklyReset = reset
            }
        }
        
        // Fallback: check generic limits array if candidate keys didn't yield anything
        if !foundWeekly, let limits = json["limits"] as? [[String: Any]] {
            for limit in limits {
                let kind = (limit["kind"] as? String)?.lowercased() ?? ""
                if kind.contains("weekly") || kind.contains("seven_day") {
                    let raw = (limit["percent"] as? NSNumber)?.doubleValue ?? (limit["utilization"] as? NSNumber)?.doubleValue
                    if let raw = raw {
                        bestWeeklyUsed = normalizePercent(raw)
                        bestWeeklyReset = (limit["resets_at"] as? String).flatMap(parseISODate)
                        foundWeekly = true
                        break
                    }
                }
            }
        }
        
        return ParsedClaudeQuota(
            shortUsedPercent: fiveHourUsed,
            shortResetDate: fiveHourReset,
            weeklyUsedPercent: bestWeeklyUsed,
            weeklyResetDate: bestWeeklyReset
        )
    }
    
    private func normalizePercent(_ value: Double?) -> Double {
        guard let value = value, value.isFinite else { return 0.0 }
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
        
        // 3. Fallback to environment variable in current process
        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envToken.isEmpty {
            let oauth = ClaudeOAuthCredentials(accessToken: envToken, refreshToken: nil, expiresAt: nil, subscriptionType: nil)
            return ClaudeCredentialResult(oauth: oauth, source: .environment, fullData: [:])
        }
        
        // 4. Extract token from active Claude Code / Desktop agent processes
        if let processResult = loadFromRunningProcesses() {
            return processResult
        }
        
        return nil
    }
    
    private func loadFromRunningProcesses() -> ClaudeCredentialResult? {
        var pids = [pid_t](repeating: 0, count: 8192)
        let bytesUsed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let count = Int(bytesUsed) / MemoryLayout<pid_t>.size
        guard count > 0 else { return nil }
        
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
                
                let matches = targetCLIProcesses.contains { procName == $0 || procName.contains($0) }
                if matches {
                    if let token = extractOAuthTokenFromProcess(pid: pid) {
                        let oauth = ClaudeOAuthCredentials(accessToken: token, refreshToken: nil, expiresAt: nil, subscriptionType: nil)
                        return ClaudeCredentialResult(oauth: oauth, source: .environment, fullData: [:])
                    }
                }
            }
        }
        return nil
    }
    
    private func extractOAuthTokenFromProcess(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size <= 0 {
            return nil
        }
        
        var buffer = [CChar](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return nil
        }
        
        return buffer.withUnsafeBufferPointer { ptr -> String? in
            guard let base = ptr.baseAddress else { return nil }
            let argc = Int(base.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee })
            var offset = MemoryLayout<Int32>.size
            
            // Skip executable path
            while offset < size && ptr[offset] != 0 { offset += 1 }
            // Skip null padding
            while offset < size && ptr[offset] == 0 { offset += 1 }
            
            // Skip argv entries
            for _ in 0..<argc {
                while offset < size && ptr[offset] != 0 { offset += 1 }
                while offset < size && ptr[offset] == 0 { offset += 1 }
            }
            
            // Search environment variables
            let tokenPrefix = "CLAUDE_CODE_OAUTH_TOKEN="
            while offset < size {
                let start = offset
                while offset < size && ptr[offset] != 0 { offset += 1 }
                if offset > start {
                    let bytes = Array(ptr[start..<offset]) + [0]
                    if let entry = String(cString: bytes) as String?,
                       entry.hasPrefix(tokenPrefix) {
                        let token = String(entry.dropFirst(tokenPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !token.isEmpty {
                            return token
                        }
                    }
                }
                offset += 1
            }
            return nil
        }
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
            process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
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
                process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                process.arguments = ["add-generic-password", "-U", "-s", service, "-a", NSUserName(), "-w", jsonString]
                try? process.run()
                process.waitUntilExit()
            }
        case .environment:
            break
        }
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
