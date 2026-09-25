import Foundation
import Security
import LocalAuthentication

struct ClaudeUsageSnapshot: Equatable {
    let windows: [CodexQuotaWindow]
    let plan: String?
    let fetchedAt: Date
    var accountEmail: String? = nil

    var sessionWindow: CodexQuotaWindow? { windows.first { $0.id == "five_hour" } }
    var weeklyWindow: CodexQuotaWindow? { windows.first { $0.id == "seven_day" } }
}

enum ClaudeUsageError: LocalizedError {
    case notSignedIn, keychainLocked, expired, unauthorized, unavailable, invalidResponse
    case rateLimited(Date), http(Int)

    var invalidatesSnapshot: Bool {
        switch self {
        case .notSignedIn, .expired, .unauthorized: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return CodexLocalization.text("未找到 Claude Code 订阅登录。请在终端运行 claude auth login。", "No Claude Code subscription sign-in. Run claude auth login in Terminal.")
        case .keychainLocked:
            return CodexLocalization.text("需要钥匙串访问权限，请到组件设置的 Claude Code 区域授权读取登录信息。", "Keychain access is required. Authorize sign-in access in the widget’s Claude Code settings.")
        case .expired, .unauthorized:
            return CodexLocalization.text("Claude Code 登录已过期或无权读取额度。请打开 Claude Code 重新登录后刷新。", "Claude Code sign-in expired or cannot read quota. Sign in again in Claude Code, then refresh.")
        case .unavailable:
            return CodexLocalization.text("此账户没有返回订阅额度；API 计费账户不提供此额度。", "No subscription quota returned. API billing accounts do not expose this quota.")
        case .invalidResponse:
            return CodexLocalization.text("Claude 额度响应格式无法识别。", "Claude quota response was not recognized.")
        case let .rateLimited(date):
            return CodexLocalization.text("Claude 请求限流，\(date.formatted(date: .omitted, time: .shortened))后可重试。", "Claude rate limit: retry after \(date.formatted(date: .omitted, time: .shortened)).")
        case let .http(status):
            return CodexLocalization.text("Claude 额度请求失败（HTTP \(status)）。", "Claude quota request failed (HTTP \(status)).")
        }
    }
}

/// Read-only Claude Code authentication and OAuth quota mapping, based on CodexBar (MIT).
/// Never refreshes/writes credentials, launches conversations, or stores tokens in preferences.
actor ClaudeUsageService {
    private var retryAfter: Date?
    private var profileCache: (token: String, email: String, date: Date)?
    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func fetch(allowKeychainPrompt: Bool = false) async throws -> ClaudeUsageSnapshot {
        if let retryAfter, retryAfter > Date() { throw ClaudeUsageError.rateLimited(retryAfter) }
        let credential = try Self.readCredential(allowPrompt: allowKeychainPrompt)
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 25
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ClaudeUsageError.invalidResponse }
        switch http.statusCode {
        case 200:
            var snapshot = try Self.decode(data, plan: credential.plan)
            snapshot.accountEmail = await fetchEmail(token: credential.token)
            return snapshot
        case 401, 403: throw ClaudeUsageError.unauthorized
        case 429:
            let date = Self.retryDate(http.value(forHTTPHeaderField: "Retry-After"))
            retryAfter = date
            throw ClaudeUsageError.rateLimited(date)
        default: throw ClaudeUsageError.http(http.statusCode)
        }
    }

    private func fetchEmail(token: String) async -> String? {
        if let cache = profileCache, cache.token == token, Date().timeIntervalSince(cache.date) < 3600 {
            return cache.email
        }
        if profileCache?.token != token { profileCache = nil }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 200, let email = Self.decodeEmail(data) {
                profileCache = (token, email, Date())
                return email
            }
        } catch { /* Optional profile failure must not discard a successful quota reading. */ }
        return profileCache?.email
    }

    static func decodeEmail(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let account = root["account"] as? [String: Any] ?? [:]
        for object in [account, root] {
            for key in ["email", "email_address", "emailAddress"] {
                if let email = object[key] as? String, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return email.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    static func retryDate(_ value: String?, now: Date = Date()) -> Date {
        if let value, let seconds = Double(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(max(60, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        if let value, let date = formatter.date(from: value), date > now { return date }
        return now.addingTimeInterval(300)
    }

    static func decode(_ data: Data, plan: String? = nil, now: Date = Date()) throws -> ClaudeUsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageError.invalidResponse
        }
        var windows: [CodexQuotaWindow] = []
        let known = ["five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus", "seven_day_oauth_apps"]
        let keys = known + root.keys.filter { $0.hasPrefix("seven_day_") && !known.contains($0) }.sorted()
        for key in keys {
            guard let entry = root[key] as? [String: Any],
                  let number = entry["utilization"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  number.doubleValue >= 0 else { continue }
            let title: String
            switch key {
            case "five_hour": title = CodexLocalization.text("会话 · 5 小时", "Session · 5 hours")
            case "seven_day": title = CodexLocalization.text("全部模型 · 7 天", "All models · 7 days")
            default: title = key.replacingOccurrences(of: "seven_day_", with: "").replacingOccurrences(of: "_", with: " ").capitalized + " · 7d"
            }
            windows.append(CodexQuotaWindow(id: key, title: title, usedPercent: min(100, number.doubleValue),
                resetAt: parseDate(entry["resets_at"] as? String), durationSeconds: key == "five_hour" ? 18_000 : 604_800))
        }
        // CodexBar deliberately does not filter is_active: valid, enforceable model
        // quotas (including Fable) can report false. Scope and finite percent define a row.
        var seenModelIDs: Set<String> = []
        for entry in root["limits"] as? [[String: Any]] ?? [] {
            guard entry["group"] as? String == "weekly", entry["kind"] as? String == "weekly_scoped",
                  let scope = entry["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let rawName = model["display_name"] as? String,
                  let percent = entry["percent"] as? NSNumber,
                  CFGetTypeID(percent) != CFBooleanGetTypeID(), percent.doubleValue.isFinite,
                  percent.doubleValue >= 0 else { continue }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = (model["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = (modelID?.isEmpty == false ? modelID! : name).lowercased()
            let allModels = identity.replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
            guard !name.isEmpty, name.lowercased() != "all models", allModels != "all-models",
                  !allModels.hasSuffix("-all-models"), seenModelIDs.insert(identity).inserted else { continue }
            if windows.contains(where: { $0.title.lowercased().hasPrefix(name.lowercased() + " ·") }) { continue }
            windows.append(CodexQuotaWindow(id: "scoped_" + identity,
                title: name + CodexLocalization.text(" · 每周", " · weekly"),
                usedPercent: min(100, percent.doubleValue), resetAt: parseDate(entry["resets_at"] as? String), durationSeconds: 604_800))
        }
        guard !windows.isEmpty else { throw ClaudeUsageError.unavailable }
        return ClaudeUsageSnapshot(windows: windows, plan: plan, fetchedAt: now)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    struct Credential {
        let token: String
        let plan: String?
    }

    static func parseCredential(_ data: Data, now: Date = Date()) throws -> Credential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { throw ClaudeUsageError.notSignedIn }
        if let expiry = oauth["expiresAt"] as? Double, expiry.isFinite,
           expiry / 1000 <= now.timeIntervalSince1970 { throw ClaudeUsageError.expired }
        return Credential(token: token, plan: oauth["subscriptionType"] as? String)
    }

    private static func readCredential(allowPrompt: Bool) throws -> Credential {
        let env = ProcessInfo.processInfo.environment
        let configured = env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] ?? env["CLAUDE_CONFIG_DIR"]
        let defaultRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let root = configured.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultRoot
        let file = root.appendingPathComponent(".credentials.json")
        var fileError: Error?
        if let data = try? Data(contentsOf: file) {
            do { return try parseCredential(data) } catch { fileError = error }
        }
        // A custom profile must not silently read another account's default Keychain entry.
        guard root.standardizedFileURL == defaultRoot.standardizedFileURL else {
            throw fileError ?? ClaudeUsageError.notSignedIn
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
                throw ClaudeUsageError.keychainLocked
            }
            throw fileError ?? ClaudeUsageError.notSignedIn
        }
        return try parseCredential(data)
    }
}
