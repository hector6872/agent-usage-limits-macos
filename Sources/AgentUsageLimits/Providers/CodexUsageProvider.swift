import Foundation
import AppKit
import Darwin

/// Provider for Codex / OpenAI CLI & Desktop
/// Implements live OAuth API usage probing and CLI fallback with automatic token refresh.
public final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: String = "codex"
    public let displayName: String = "Codex"
    public let iconSymbol: String = "codex.chevron"
    
    /// Short sliding window duration in hours (Codex primary window is typically 5.0h)
    public let shortWindowDurationHours: Double
    public var isEnabled: Bool = true
    
    // API Endpoints
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    
    // OAuth client configuration for Codex
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    
    // Rate limit window caching
    private var rateLimitRetryAt: Date?
    private let rateLimitLock = NSLock()
    
    // Credentials caching with TTL
    private var cachedCredentials: CodexCredentialResult?
    private var credentialCacheDate: Date?
    private let credentialLock = NSLock()
    private static let credentialTTL: TimeInterval = 5 * 60 // 5 minutes
    
    public init(shortWindowDurationHours: Double = 5.0, isEnabled: Bool = true) {
        self.shortWindowDurationHours = shortWindowDurationHours
        self.isEnabled = isEnabled
    }
    
    // MARK: - Activity Detection (GUI + CLI)
    
    /// Checks whether Codex is currently active (App UI or CLI processes running)
    public var isActive: Bool {
        return isGUIRunning || isCLIRunning
    }
    
    public var isTokenAvailable: Bool {
        return loadCredentials() != nil
    }
    
    /// 1. Checks if Codex Desktop App UI is running
    public var isGUIRunning: Bool {
        let isAppRunning = NSWorkspace.shared.runningApplications.contains { app in
            let bundleId = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName?.lowercased() ?? ""
            let execName = app.executableURL?.lastPathComponent.lowercased() ?? ""
            return bundleId.contains("com.openai.codex") ||
                   name == "codex" ||
                   execName == "codex"
        }
        return isAppRunning
    }
    
    /// 2. Checks if Codex CLI / background agent processes are running
    public var isCLIRunning: Bool {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytesUsed = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let count = Int(bytesUsed) / MemoryLayout<pid_t>.size
        guard count > 0 else { return false }
        
        let targetCLIProcesses: Set<String> = [
            "codex",
            "codex-cli",
            "codex-app-server"
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
        
        // 1. Try OAuth usage API
        if let apiQuota = await fetchAPIUsage() {
            return buildProviderUsage(from: apiQuota, isActive: true, now: now)
        }
        
        // 2. Try CLI `/usage` fallback if available
        if let cliQuota = await probeCLIUsage() {
            return buildProviderUsage(from: cliQuota, isActive: true, now: now)
        }
        
        // Fallback: Empty active quota if unable to parse live data
        return buildEmptyActiveUsage(now: now)
    }
    
    // MARK: - API Usage Probing
    
    private struct ParsedCodexQuota {
        let shortUsedPercent: Double
        let shortResetDate: Date?
        let weeklyUsedPercent: Double
        let weeklyResetDate: Date?
        let planType: String?
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
    
    private func fetchAPIUsage() async -> ParsedCodexQuota? {
        if isRateLimited() {
            return nil
        }
        
        guard var credentials = loadCachedOrFreshCredentials() else {
            return nil
        }
        
        // Proactive token refresh if needed
        if needsRefresh(lastRefresh: credentials.lastRefresh), credentials.refreshToken != nil {
            if let refreshed = await refreshToken(credentials) {
                credentials = refreshed
            }
        }
        
        let result = await executeUsageRequest(accessToken: credentials.accessToken, accountId: credentials.accountId)
        
        switch result {
        case .success(let quota):
            return quota
            
        case .authError:
            // Token may have expired, attempt one refresh
            if credentials.refreshToken != nil,
               let refreshed = await refreshToken(credentials) {
                if case .success(let quota) = await executeUsageRequest(accessToken: refreshed.accessToken, accountId: refreshed.accountId) {
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
        case success(ParsedCodexQuota)
        case authError
        case rateLimited(TimeInterval)
        case failure
    }
    
    private func executeUsageRequest(accessToken: String, accountId: String?) async -> APIResult {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenUsage", forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
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
        
        if let quota = parseAPIResponse(data: data, httpResponse: http) {
            return .success(quota)
        }
        
        return .failure
    }
    
    private func parseAPIResponse(data: Data, httpResponse: HTTPURLResponse) -> ParsedCodexQuota? {
        let responseDict = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let nowSeconds = Date().timeIntervalSince1970
        
        let rateLimit = responseDict["rate_limit"] as? [String: Any]
        let primaryWindow = rateLimit?["primary_window"] as? [String: Any]
        let secondaryWindow = rateLimit?["secondary_window"] as? [String: Any]
        
        // Try headers first, then fall back to body JSON
        let headerPrimary = readHeaderDouble(httpResponse, key: "x-codex-primary-used-percent")
        let headerSecondary = readHeaderDouble(httpResponse, key: "x-codex-secondary-used-percent")
        
        let bodyPrimaryUsed = (primaryWindow?["used_percent"] as? NSNumber)?.doubleValue
        let bodySecondaryUsed = (secondaryWindow?["used_percent"] as? NSNumber)?.doubleValue
        
        let primaryUsed = normalizePercent(headerPrimary ?? bodyPrimaryUsed ?? 0.0)
        let secondaryUsed = normalizePercent(headerSecondary ?? bodySecondaryUsed ?? 0.0)
        
        let primaryReset = resetsAtDate(nowSeconds: nowSeconds, window: primaryWindow)
        let secondaryReset = resetsAtDate(nowSeconds: nowSeconds, window: secondaryWindow)
        
        let planType = responseDict["plan_type"] as? String
        
        return ParsedCodexQuota(
            shortUsedPercent: primaryUsed,
            shortResetDate: primaryReset,
            weeklyUsedPercent: secondaryUsed,
            weeklyResetDate: secondaryReset,
            planType: planType
        )
    }
    
    private func readHeaderDouble(_ response: HTTPURLResponse, key: String) -> Double? {
        guard let value = response.value(forHTTPHeaderField: key),
              let n = Double(value), n.isFinite else {
            return nil
        }
        return n
    }
    
    private func resetsAtDate(nowSeconds: TimeInterval, window: [String: Any]?) -> Date? {
        guard let window else { return nil }
        if let resetAt = (window["reset_at"] as? NSNumber)?.doubleValue {
            return Date(timeIntervalSince1970: resetAt)
        }
        if let resetAfterSeconds = (window["reset_after_seconds"] as? NSNumber)?.doubleValue {
            return Date(timeIntervalSince1970: nowSeconds + resetAfterSeconds)
        }
        return nil
    }
    
    private func normalizePercent(_ value: Double) -> Double {
        if value > 0.0 && value <= 1.0 {
            return value * 100.0
        }
        return max(0.0, min(100.0, value))
    }
    
    // MARK: - Token Refresh
    
    private func refreshToken(_ credentials: CodexCredentialResult) async -> CodexCredentialResult? {
        guard let refreshToken = credentials.refreshToken else { return nil }
        
        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0
        
        let bodyString = "grant_type=refresh_token"
            + "&client_id=" + (Self.clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Self.clientID)
            + "&refresh_token=" + (refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)
        
        request.httpBody = bodyString.data(using: .utf8)
        
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
        updated.accessToken = newAccessToken
        if let newRefresh = json["refresh_token"] as? String {
            updated.refreshToken = newRefresh
        }
        if let idToken = json["id_token"] as? String {
            var fullData = updated.fullData
            if var tokens = fullData["tokens"] as? [String: Any] {
                tokens["id_token"] = idToken
                fullData["tokens"] = tokens
                updated.fullData = fullData
            }
        }
        updated.lastRefresh = ISO8601DateFormatter().string(from: Date())
        
        saveCredentials(updated)
        cacheCredentials(updated)
        return updated
    }
    
    private func needsRefresh(lastRefresh: String?) -> Bool {
        guard let lastRefresh, let refreshDate = ISO8601DateFormatter().date(from: lastRefresh) else {
            return false
        }
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3600)
        return refreshDate < eightDaysAgo
    }
    
    // MARK: - Credentials Management
    
    private struct CodexCredentialResult {
        var accessToken: String
        var refreshToken: String?
        var accountId: String?
        var lastRefresh: String?
        var filePath: String?
        var fullData: [String: Any]
    }
    
    private func loadCachedOrFreshCredentials() -> CodexCredentialResult? {
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
    
    private func cacheCredentials(_ creds: CodexCredentialResult) {
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
    
    private func loadCredentials() -> CodexCredentialResult? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "\(home)/.codex/auth.json",
            "\(home)/.config/codex/auth.json",
            "\(home)/.codex.json"
        ]
        
        for path in candidatePaths {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            // Nested structure: {"tokens": {"access_token": "...", "refresh_token": "...", "account_id": "..."}}
            if let tokens = json["tokens"] as? [String: Any],
               let rawToken = (tokens["access_token"] as? String) ?? (tokens["accessToken"] as? String) {
                let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    let refreshToken = (tokens["refresh_token"] as? String) ?? (tokens["refreshToken"] as? String)
                    let accountId = (tokens["account_id"] as? String) ?? (tokens["accountId"] as? String)
                    let lastRefresh = json["last_refresh"] as? String
                    return CodexCredentialResult(
                        accessToken: token,
                        refreshToken: refreshToken,
                        accountId: accountId,
                        lastRefresh: lastRefresh,
                        filePath: path,
                        fullData: json
                    )
                }
            }
            
            // Flat structure: {"access_token": "...", "refresh_token": "...", "account_id": "..."}
            if let rawToken = (json["access_token"] as? String) ?? (json["accessToken"] as? String) {
                let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty {
                    let refreshToken = (json["refresh_token"] as? String) ?? (json["refreshToken"] as? String)
                    let accountId = (json["account_id"] as? String) ?? (json["accountId"] as? String)
                    let lastRefresh = json["last_refresh"] as? String
                    return CodexCredentialResult(
                        accessToken: token,
                        refreshToken: refreshToken,
                        accountId: accountId,
                        lastRefresh: lastRefresh,
                        filePath: path,
                        fullData: json
                    )
                }
            }
        }
        
        // Environment fallback
        let env = ProcessInfo.processInfo.environment
        if let envToken = (env["CODEX_AUTH_TOKEN"] ?? env["OPENAI_OAUTH_TOKEN"] ?? env["CODEX_API_KEY"] ?? env["OPENAI_API_KEY"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envToken.isEmpty {
            return CodexCredentialResult(
                accessToken: envToken,
                refreshToken: nil,
                accountId: env["CHATGPT_ACCOUNT_ID"],
                lastRefresh: nil,
                filePath: nil,
                fullData: [:]
            )
        }
        
        return nil
    }
    
    private func saveCredentials(_ result: CodexCredentialResult) {
        guard let path = result.filePath else { return }
        var updatedData = result.fullData
        
        if var tokens = updatedData["tokens"] as? [String: Any] {
            tokens["access_token"] = result.accessToken
            if let refresh = result.refreshToken { tokens["refresh_token"] = refresh }
            if let account = result.accountId { tokens["account_id"] = account }
            updatedData["tokens"] = tokens
        } else {
            updatedData["access_token"] = result.accessToken
            if let refresh = result.refreshToken { updatedData["refresh_token"] = refresh }
            if let account = result.accountId { updatedData["account_id"] = account }
        }
        if let lastRefresh = result.lastRefresh {
            updatedData["last_refresh"] = lastRefresh
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: updatedData, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
    
    // MARK: - CLI Fallback Probing
    
    private func probeCLIUsage() async -> ParsedCodexQuota? {
        let binaryPath = findCodexBinary()
        guard let binary = binaryPath else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["usage"]
        
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
    
    private func findCodexBinary() -> String? {
        let candidates = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/codex",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.nvm/versions/node/current/bin/codex"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["codex"]
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
    
    private func parseCLIOutput(_ text: String) -> ParsedCodexQuota? {
        let clean = text.replacingOccurrences(of: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#, with: "", options: .regularExpression)
        
        let primaryInfo = parseUsageSection(label: "Primary", text: clean)
        let secondaryInfo = parseUsageSection(label: "Secondary", text: clean)
        
        guard let primaryUsed = primaryInfo.usedPercent else {
            return nil
        }
        
        return ParsedCodexQuota(
            shortUsedPercent: primaryUsed,
            shortResetDate: primaryInfo.resetDate,
            weeklyUsedPercent: secondaryInfo.usedPercent ?? 0.0,
            weeklyResetDate: secondaryInfo.resetDate,
            planType: nil
        )
    }
    
    private func parseUsageSection(label: String, text: String) -> (usedPercent: Double?, resetDate: Date?) {
        guard let labelRange = text.range(of: label, options: [.caseInsensitive]) else {
            return (nil, nil)
        }
        let section = String(text[labelRange.lowerBound...])
        
        var usedPercent: Double? = nil
        let pctPattern = #"(\d+(?:\.\d+)?)\s*%\s*(used|remaining|left)?"#
        if let regex = try? NSRegularExpression(pattern: pctPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: section, options: [], range: NSRange(section.startIndex..<section.endIndex, in: section)),
           let numRange = Range(match.range(at: 1), in: section) {
            let num = Double(section[numRange]) ?? 0.0
            if match.numberOfRanges > 2, let typeRange = Range(match.range(at: 2), in: section) {
                let type = section[typeRange].lowercased()
                if type == "remaining" || type == "left" {
                    usedPercent = max(0.0, min(100.0, 100.0 - num))
                } else {
                    usedPercent = max(0.0, min(100.0, num))
                }
            } else {
                usedPercent = max(0.0, min(100.0, num))
            }
        }
        
        let resetDate = parseResetInterval(text: section).map { Date().addingTimeInterval($0) }
        return (usedPercent, resetDate)
    }
    
    private func parseResetInterval(text: String) -> TimeInterval? {
        let pattern = #"resets?\s+(?:in\s+)?([\\w\\s]+?)(?:\\n|\\)|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        
        let segment = String(text[range]).lowercased()
        var total: TimeInterval = 0
        
        if let dMatch = segment.range(of: #"(\d+)\s*d"#, options: .regularExpression),
           let d = Double(segment[dMatch].filter(\.isNumber)) {
            total += d * 86400
        }
        if let hMatch = segment.range(of: #"(\d+)\s*h"#, options: .regularExpression),
           let h = Double(segment[hMatch].filter(\.isNumber)) {
            total += h * 3600
        }
        if let mMatch = segment.range(of: #"(\d+)\s*m"#, options: .regularExpression),
           let m = Double(segment[mMatch].filter(\.isNumber)) {
            total += m * 60
        }
        
        return total > 0 ? total : nil
    }
    
    // MARK: - Helpers
    
    private func buildProviderUsage(from quota: ParsedCodexQuota, isActive: Bool, now: Date) -> ProviderUsage {
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
    
    private func parseRetryAfter(_ header: String?) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespacesAndNewlines),
              let seconds = TimeInterval(header), seconds > 0 else {
            return nil
        }
        return seconds
    }
}
