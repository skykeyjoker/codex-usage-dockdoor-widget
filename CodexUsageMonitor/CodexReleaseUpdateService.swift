import Foundation

struct CodexReleaseUpdateSnapshot: Codable, Equatable, Sendable {
    let latestVersion: String
    let releaseName: String
    let releaseURLString: String
    let publishedAt: Date?
    let checkedAt: Date

    var isUpdateAvailable: Bool {
        CodexReleaseUpdateService.isVersion(
            latestVersion,
            newerThan: CodexReleaseUpdateService.currentVersion
        )
    }

    var releaseURL: URL? {
        URL(string: releaseURLString)
    }
}

struct CodexReleaseUpdateService: Sendable {
    static let currentVersion = "2.0.0"
    static let repositoryURL = "https://github.com/skykeyjoker/codex-usage-dockdoor-widget"
    static let latestReleaseURL = repositoryURL + "/releases/latest"

    private static let endpoint = URL(
        string: "https://api.github.com/repos/skykeyjoker/codex-usage-dockdoor-widget/releases/latest"
    )!

    func fetchLatest(now: Date = Date()) async throws -> CodexReleaseUpdateSnapshot {
        do {
            return try await fetchLatestFromAPI(now: now)
        } catch {
            return try await fetchLatestFromRedirect(now: now)
        }
    }

    private func fetchLatestFromAPI(now: Date) async throws -> CodexReleaseUpdateSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(
            "CodexUsageDockDoorWidget/\(Self.currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.httpStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let release = try? decoder.decode(GitHubRelease.self, from: data),
              !release.draft,
              !release.prerelease,
              !release.tagName.isEmpty,
              !release.htmlURL.isEmpty
        else {
            throw UpdateError.invalidPayload
        }

        return CodexReleaseUpdateSnapshot(
            latestVersion: Self.normalizedVersion(release.tagName),
            releaseName: release.name?.isEmpty == false ? release.name! : release.tagName,
            releaseURLString: release.htmlURL,
            publishedAt: release.publishedAt,
            checkedAt: now
        )
    }

    private func fetchLatestFromRedirect(now: Date) async throws -> CodexReleaseUpdateSnapshot {
        guard let url = URL(string: Self.latestReleaseURL) else {
            throw UpdateError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "CodexUsageDockDoorWidget/\(Self.currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let finalURL = httpResponse.url,
              let tagIndex = finalURL.pathComponents.firstIndex(of: "tag"),
              finalURL.pathComponents.indices.contains(tagIndex + 1)
        else {
            throw UpdateError.invalidResponse
        }

        let tag = finalURL.pathComponents[tagIndex + 1]
        let version = Self.normalizedVersion(tag)
        guard !version.isEmpty else { throw UpdateError.invalidPayload }
        return CodexReleaseUpdateSnapshot(
            latestVersion: version,
            releaseName: "Codex Usage \(version)",
            releaseURLString: finalURL.absoluteString,
            publishedAt: nil,
            checkedAt: now
        )
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateComponents = versionComponents(candidate)
        let currentComponents = versionComponents(current)
        guard !candidateComponents.isEmpty, !currentComponents.isEmpty else { return false }

        for index in 0..<max(candidateComponents.count, currentComponents.count) {
            let candidateValue = index < candidateComponents.count ? candidateComponents[index] : 0
            let currentValue = index < currentComponents.count ? currentComponents[index] : 0
            if candidateValue != currentValue {
                return candidateValue > currentValue
            }
        }
        return false
    }

    static func normalizedVersion(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value.removeFirst()
        }
        return value.split(separator: "-", maxSplits: 1).first.map(String.init) ?? value
    }

    private static func versionComponents(_ rawValue: String) -> [Int] {
        normalizedVersion(rawValue).split(separator: ".").compactMap { component in
            let digits = component.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: String
        let publishedAt: Date?
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case draft
            case prerelease
        }
    }

    private enum UpdateError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return CodexLocalization.text(
                    "GitHub 返回了无效响应",
                    "GitHub returned an invalid response"
                )
            case let .httpStatus(status):
                return CodexLocalization.text(
                    "GitHub 请求失败（HTTP \(status)）",
                    "GitHub request failed (HTTP \(status))"
                )
            case .invalidPayload:
                return CodexLocalization.text(
                    "无法解析 GitHub Release",
                    "Unable to parse the GitHub release"
                )
            }
        }
    }
}
