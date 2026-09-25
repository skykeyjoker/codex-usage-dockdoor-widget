import Foundation

/// Shared identifiers for local history and official service status.
enum UsageProvider: String, CaseIterable, Identifiable, Sendable {
    case codex, claude, cursor
    var id: String { rawValue }
    var title: String { switch self { case .codex: return "Codex"; case .claude: return "Claude"; case .cursor: return "Cursor" } }
    var brand: CodexProviderBrand { switch self { case .codex: return .codex; case .claude: return .claude; case .cursor: return .cursor } }
    var statusURL: URL {
        URL(string: self == .codex ? "https://status.openai.com" : self == .claude ? "https://status.claude.com" : "https://status.cursor.com")!
    }
}

struct ProviderServiceStatus: Codable {
    let indicator: OpenAIServiceIndicator
    let components: [OpenAIStatusComponent]
    let incidents: [Incident]
    let fetchedAt: Date
    /// Never hide an affected or unknown service inside the collapsed list.
    var previewComponents: [OpenAIStatusComponent] {
        let affected = components.filter { $0.indicator != .operational }
        let normal = components.filter { $0.indicator == .operational }
        return affected + normal.prefix(max(0, 6 - affected.count))
    }

    static func openAI(_ snapshot: OpenAIStatusSnapshot, visibleGroups: Set<String>) -> ProviderServiceStatus {
        let groups = snapshot.groups.filter { visibleGroups.contains($0.name) }.sorted {
            ($0.name == "Codex" ? 0 : 1) < ($1.name == "Codex" ? 0 : 1)
        }
        let components = groups.flatMap { group in
            group.components.map { component in
                OpenAIStatusComponent(id: group.id + ":" + component.id,
                    name: group.name + " · " + component.name, indicator: component.indicator)
            }
        }
        return ProviderServiceStatus(indicator: snapshot.overallIndicator, components: components,
            incidents: [], fetchedAt: snapshot.fetchedAt)
    }

    struct Incident: Codable, Identifiable {
        let id: String
        let name: String
        let status: String
    }
}

actor ProviderStatusService {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    func fetch(_ provider: UsageProvider) async throws -> ProviderServiceStatus {
        let url = provider.statusURL.appendingPathComponent("api/v2/summary.json")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decode(data)
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> ProviderServiceStatus {
        struct Payload: Decodable {
            struct Status: Decodable { let indicator: String }
            struct Component: Decodable { let id: String; let name: String; let status: String; let group: Bool?; let position: Int? }
            let status: Status
            let components: [Component]
            let incidents: [ProviderServiceStatus.Incident]?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let components = payload.components.filter { $0.group != true }.sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            .map { OpenAIStatusComponent(id: $0.id, name: $0.name, indicator: .init(status: $0.status)) }
        // Preserve unknown values instead of silently reporting a healthy provider.
        return ProviderServiceStatus(indicator: .init(overallIndicator: payload.status.indicator), components: components,
            incidents: (payload.incidents ?? []).filter { $0.status != "resolved" && $0.status != "postmortem" }, fetchedAt: now)
    }
}
