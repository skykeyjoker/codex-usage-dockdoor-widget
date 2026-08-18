import Combine
import DockDoorWidgetSDK
import Foundation

private final class CodexLocalScanProgressRelay: @unchecked Sendable {
    weak var monitor: CodexUsageMonitor?

    @MainActor
    init(monitor: CodexUsageMonitor) {
        self.monitor = monitor
    }

    func send(_ progress: CodexLocalScanCoverage) {
        Task { @MainActor in
            self.monitor?.localScanProgress = progress
        }
    }
}

@MainActor
final class CodexUsageMonitor: ObservableObject {
    @Published private(set) var usage: CodexUsageSnapshot?
    @Published private(set) var recentUsage: CodexRecentUsageSnapshot?
    @Published private(set) var recentConversations: CodexConversationSnapshot?
    @Published private(set) var serviceStatus: OpenAIStatusSnapshot?
    @Published private(set) var accountInsights: CodexAccountInsightsSnapshot?
    @Published private(set) var quotaPace: CodexQuotaPaceSnapshot?
    @Published private(set) var releaseUpdate: CodexReleaseUpdateSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingConversations = false
    @Published private(set) var isCheckingReleaseUpdate = false
    @Published private(set) var usageError: String?
    @Published private(set) var tokenUsageError: String?
    @Published private(set) var accountInsightsError: String?
    @Published private(set) var statusError: String?
    @Published private(set) var releaseUpdateError: String?
    @Published private(set) var settingsRevision = 0
    @Published private(set) var resolvedQuotaUsageSource: CodexQuotaUsageSource?
    @Published fileprivate(set) var localScanProgress: CodexLocalScanCoverage?

    let widgetId: String

    private let service: CodexUsageService
    private let localUsageScanner: CodexLocalUsageScanner
    private let conversationScanner: CodexConversationScanner
    private let accountInsightsService: CodexAccountInsightsService
    private let quotaPaceStore: CodexQuotaPaceStore
    private let releaseUpdateService: CodexReleaseUpdateService
    private var refreshLoop: Task<Void, Never>?
    private var refreshOperation: Task<Void, Never>?
    private var conversationRefreshOperation: Task<Void, Never>?
    private var releaseUpdateOperation: Task<Void, Never>?
    private var defaultsObserver: AnyCancellable?
    private var hasStarted = false
    private var scheduledInterval: CodexRefreshInterval
    private var scheduledQuotaUsageSource: CodexQuotaUsageSource
    private var scheduledReleaseUpdateMonitoring: Bool

    init(
        widgetId: String,
        service: CodexUsageService = CodexUsageService(),
        localUsageScanner: CodexLocalUsageScanner = CodexLocalUsageScanner(),
        conversationScanner: CodexConversationScanner = CodexConversationScanner(),
        accountInsightsService: CodexAccountInsightsService = CodexAccountInsightsService(),
        quotaPaceStore: CodexQuotaPaceStore = CodexQuotaPaceStore(),
        releaseUpdateService: CodexReleaseUpdateService = CodexReleaseUpdateService()
    ) {
        self.widgetId = widgetId
        self.service = service
        self.localUsageScanner = localUsageScanner
        self.conversationScanner = conversationScanner
        self.accountInsightsService = accountInsightsService
        self.quotaPaceStore = quotaPaceStore
        self.releaseUpdateService = releaseUpdateService
        scheduledInterval = Self.readRefreshInterval(widgetId: widgetId)
        scheduledQuotaUsageSource = Self.readQuotaUsageSource(widgetId: widgetId)
        scheduledReleaseUpdateMonitoring = Self.readReleaseUpdateMonitoring(widgetId: widgetId)
        usage = Self.readCache(CodexUsageSnapshot.self, key: Self.usageCacheKey(widgetId))
        recentUsage = Self.readCache(CodexRecentUsageSnapshot.self, key: Self.tokenUsageCacheKey(widgetId))
        serviceStatus = Self.readCache(OpenAIStatusSnapshot.self, key: Self.statusCacheKey(widgetId))
        accountInsights = Self.readCache(
            CodexAccountInsightsSnapshot.self,
            key: Self.accountInsightsCacheKey(widgetId)
        )
        quotaPace = Self.readCache(CodexQuotaPaceSnapshot.self, key: Self.quotaPaceCacheKey(widgetId))
        releaseUpdate = Self.readCache(
            CodexReleaseUpdateSnapshot.self,
            key: Self.releaseUpdateCacheKey(widgetId)
        )
        resolvedQuotaUsageSource = UserDefaults.standard.string(
            forKey: Self.resolvedSourceCacheKey(widgetId)
        ).flatMap(CodexQuotaUsageSource.init(rawValue:))

        defaultsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        .receive(on: RunLoop.main)
        .sink { @MainActor [weak self] _ in
            self?.configurationDidChange()
        }
    }

    deinit {
        refreshLoop?.cancel()
        refreshOperation?.cancel()
        conversationRefreshOperation?.cancel()
        releaseUpdateOperation?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refresh()
        scheduleRefreshLoop()
    }

    func refresh() {
        refreshOperation?.cancel()
        isRefreshing = true
        isRefreshingConversations = true
        refreshOperation = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        checkReleaseUpdate()
    }

    func refreshConversations() {
        conversationRefreshOperation?.cancel()
        isRefreshingConversations = true
        let scanner = conversationScanner
        conversationRefreshOperation = Task { [weak self] in
            let snapshot = await scanner.scan()
            guard let self, !Task.isCancelled else { return }
            recentConversations = snapshot
            isRefreshingConversations = false
        }
    }

    func syncConfiguration() {
        let interval = Self.readRefreshInterval(widgetId: widgetId)
        if interval != scheduledInterval {
            scheduledInterval = interval
            scheduleRefreshLoop()
        }
        let source = Self.readQuotaUsageSource(widgetId: widgetId)
        if source != scheduledQuotaUsageSource {
            scheduledQuotaUsageSource = source
            if hasStarted { refresh() }
        }
        syncReleaseUpdateMonitoring()
    }

    func window(for limit: CodexDisplayLimit) -> CodexQuotaWindow? {
        switch limit {
        case .weekly: return usage?.weeklyWindow ?? usage?.monthlyWindow
        case .session: return usage?.sessionWindow ?? usage?.weeklyWindow ?? usage?.monthlyWindow
        case .monthly: return usage?.monthlyWindow ?? usage?.weeklyWindow
        }
    }

    func writeSetting(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: Self.settingKey(key, widgetId))
        configurationDidChange()
    }

    func writeSetting(_ value: Bool, key: String) {
        UserDefaults.standard.set(value, forKey: Self.settingKey(key, widgetId))
        configurationDidChange()
    }

    func checkReleaseUpdate(force: Bool = false) {
        guard force || scheduledReleaseUpdateMonitoring else { return }
        guard force || !isCheckingReleaseUpdate else { return }

        let now = Date()
        if !force {
            let lastAttempt = UserDefaults.standard.double(
                forKey: Self.releaseUpdateAttemptKey(widgetId)
            )
            if lastAttempt > 0 {
                let elapsed = now.timeIntervalSince1970 - lastAttempt
                let minimumInterval: TimeInterval = releaseUpdate == nil ? 3_600 : 43_200
                guard elapsed >= minimumInterval else { return }
            }
        }

        releaseUpdateOperation?.cancel()
        isCheckingReleaseUpdate = true
        UserDefaults.standard.set(
            now.timeIntervalSince1970,
            forKey: Self.releaseUpdateAttemptKey(widgetId)
        )
        let service = releaseUpdateService
        releaseUpdateOperation = Task { [weak self] in
            do {
                let snapshot = try await service.fetchLatest()
                guard let self, !Task.isCancelled else { return }
                releaseUpdate = snapshot
                releaseUpdateError = nil
                Self.cache(snapshot, key: Self.releaseUpdateCacheKey(widgetId))
                isCheckingReleaseUpdate = false
            } catch {
                guard let self, !Task.isCancelled else { return }
                releaseUpdateError = error.localizedDescription
                isCheckingReleaseUpdate = false
            }
        }
    }

    #if CODEX_USAGE_TESTING
    func setTestingData(
        usage: CodexUsageSnapshot?,
        status: OpenAIStatusSnapshot?,
        recentUsage: CodexRecentUsageSnapshot? = nil,
        recentConversations: CodexConversationSnapshot? = nil,
        accountInsights: CodexAccountInsightsSnapshot? = nil,
        quotaPace: CodexQuotaPaceSnapshot? = nil,
        releaseUpdate: CodexReleaseUpdateSnapshot? = nil
    ) {
        self.usage = usage
        serviceStatus = status
        self.recentUsage = recentUsage
        self.recentConversations = recentConversations
        self.accountInsights = accountInsights
        self.quotaPace = quotaPace
        self.releaseUpdate = releaseUpdate
        resolvedQuotaUsageSource = .oauth
        isRefreshing = false
        hasStarted = true
    }
    #endif

    private func performRefresh() async {
        let quotaSource = scheduledQuotaUsageSource
        async let usageResult = Self.capture { try await self.service.fetchUsage(source: quotaSource) }
        let scanner = localUsageScanner
        let progressRelay = CodexLocalScanProgressRelay(monitor: self)
        let progressHandler: @Sendable (CodexLocalScanCoverage) -> Void = { progress in
            progressRelay.send(progress)
        }
        async let tokenUsageResult = Self.capture {
            try await scanner.scan(progress: progressHandler)
        }
        async let conversationSnapshot = self.conversationScanner.scan()
        async let statusResult = Self.capture { try await self.service.fetchStatus() }
        async let accountInsightsResult = Self.capture {
            try await self.accountInsightsService.fetch()
        }

        switch await usageResult {
        case let .success(result):
            usage = result.snapshot
            let pace = quotaPaceStore.record(usage: result.snapshot, widgetId: widgetId)
            quotaPace = pace
            resolvedQuotaUsageSource = result.resolvedSource
            usageError = nil
            Self.cache(result.snapshot, key: Self.usageCacheKey(widgetId))
            Self.cache(pace, key: Self.quotaPaceCacheKey(widgetId))
            UserDefaults.standard.set(
                result.resolvedSource.rawValue,
                forKey: Self.resolvedSourceCacheKey(widgetId)
            )
        case let .failure(error):
            if !Task.isCancelled { usageError = error.localizedDescription }
        }

        switch await tokenUsageResult {
        case let .success(snapshot):
            recentUsage = snapshot
            localScanProgress = snapshot.scanCoverage
            tokenUsageError = nil
            Self.cache(snapshot, key: Self.tokenUsageCacheKey(widgetId))
        case let .failure(error):
            if !Task.isCancelled { tokenUsageError = error.localizedDescription }
        }

        switch await statusResult {
        case let .success(snapshot):
            serviceStatus = snapshot
            statusError = nil
            Self.cache(snapshot, key: Self.statusCacheKey(widgetId))
        case let .failure(error):
            if !Task.isCancelled { statusError = error.localizedDescription }
        }

        switch await accountInsightsResult {
        case let .success(snapshot):
            accountInsights = snapshot
            accountInsightsError = nil
            Self.cache(snapshot, key: Self.accountInsightsCacheKey(widgetId))
        case let .failure(error):
            if !Task.isCancelled { accountInsightsError = error.localizedDescription }
        }
        recentConversations = await conversationSnapshot
        isRefreshingConversations = false
        isRefreshing = false
    }

    private func configurationDidChange() {
        settingsRevision &+= 1
        let interval = Self.readRefreshInterval(widgetId: widgetId)
        if interval != scheduledInterval {
            scheduledInterval = interval
            scheduleRefreshLoop()
        }
        let source = Self.readQuotaUsageSource(widgetId: widgetId)
        if source != scheduledQuotaUsageSource {
            scheduledQuotaUsageSource = source
            if hasStarted { refresh() }
        }
        syncReleaseUpdateMonitoring()
    }

    private func syncReleaseUpdateMonitoring() {
        let enabled = Self.readReleaseUpdateMonitoring(widgetId: widgetId)
        guard enabled != scheduledReleaseUpdateMonitoring else { return }
        scheduledReleaseUpdateMonitoring = enabled
        if enabled {
            if hasStarted { checkReleaseUpdate(force: true) }
        } else {
            releaseUpdateOperation?.cancel()
            releaseUpdateOperation = nil
            isCheckingReleaseUpdate = false
        }
    }

    private func scheduleRefreshLoop() {
        refreshLoop?.cancel()
        guard hasStarted else { return }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(self.scheduledInterval.rawValue) * 1_000_000_000
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    private nonisolated static func capture<T>(
        _ operation: @escaping () async throws -> T
    ) async -> Result<T, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }

    private static func readRefreshInterval(widgetId: String) -> CodexRefreshInterval {
        CodexRefreshInterval.resolve(title: WidgetDefaults.string(
            key: "refreshInterval",
            widgetId: widgetId,
            default: CodexRefreshInterval.fiveMinutes.title
        ))
    }

    private static func readQuotaUsageSource(widgetId: String) -> CodexQuotaUsageSource {
        CodexQuotaUsageSource.resolve(title: WidgetDefaults.string(
            key: "quotaUsageSource",
            widgetId: widgetId,
            default: CodexQuotaUsageSource.automatic.title
        ))
    }

    private static func readReleaseUpdateMonitoring(widgetId: String) -> Bool {
        WidgetDefaults.bool(
            key: "checkReleaseUpdates",
            widgetId: widgetId,
            default: true
        )
    }

    private static func cache<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func readCache<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func settingKey(_ key: String, _ widgetId: String) -> String {
        "widget.\(widgetId).\(key)"
    }

    private static func usageCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedUsage"
    }

    private static func statusCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedStatus"
    }

    private static func tokenUsageCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedRecentTokenUsage"
    }

    private static func quotaPaceCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedQuotaPace"
    }

    private static func accountInsightsCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedAccountInsights"
    }

    private static func releaseUpdateCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedReleaseUpdate"
    }

    private static func releaseUpdateAttemptKey(_ widgetId: String) -> String {
        "widget.\(widgetId).lastReleaseUpdateAttempt"
    }

    private static func resolvedSourceCacheKey(_ widgetId: String) -> String {
        "widget.\(widgetId).cachedResolvedQuotaUsageSource"
    }
}
