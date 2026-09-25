import AppKit
import SwiftUI

/// Report screen limits only. DockDoor's PanelCoordinator owns the popup and its
/// separate glass-background window, including their placement and animation.
/// Mutating either window here creates competing owners and stale background frames.
struct CodexPanelWindowSizing: NSViewRepresentable {
    static let animationDuration: TimeInterval = 0.24
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let onAvailableSize: (CGSize) -> Void

    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ view: SizingView, context: Context) {
        view.targetSize = CGSize(width: contentWidth, height: contentHeight)
        view.onAvailableSize = onAvailableSize
        view.scheduleUpdate()
    }

    final class SizingView: NSView {
        var targetSize = CGSize(width: 360, height: 572)
        var onAvailableSize: ((CGSize) -> Void)?
        private var updatePending = false
        private var observers: [NSObjectProtocol] = []
        private var lastDiagnosticAt = Date.distantPast
        private var diagnosticTask: Task<Void, Never>?

        deinit {
            diagnosticTask?.cancel()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            diagnosticTask?.cancel()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            if let window {
                for name in [NSWindow.didChangeScreenNotification, NSWindow.didResizeNotification,
                             NSWindow.didChangeOcclusionStateNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scheduleUpdate() }
                    })
                }
            }
            scheduleUpdate()
            if UserDefaults.standard.bool(forKey: "widget.codex-usage-monitor.layoutDiagnostics") {
                diagnosticTask = Task { @MainActor [weak self] in
                    for _ in 0..<60 {
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                        guard let self, let window = self.window, window.isVisible,
                              let contentView = window.contentView else { return }
                        self.recordDiagnostics(window: window, contentView: contentView)
                    }
                }
            }
        }

        func scheduleUpdate() {
            guard !updatePending else { return }
            updatePending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updatePending = false
                self.reportAvailableSize()
            }
        }

        private func reportAvailableSize() {
            guard let window, let contentView = window.contentView, let screen = window.screen else { return }
            let visible = screen.visibleFrame
            let contentRect = window.contentRect(forFrameRect: window.frame)
            let frameWidth = window.frame.width - contentRect.width
            let frameHeight = window.frame.height - contentRect.height
            var availableHeight = visible.height - 24 - frameHeight
            // Widget stacks have their own anchor, independent of macOS Dock orientation.
            // Leave space above that actual anchor so the host needs no outer scroller.
            if window.isVisible,
               window.frame.minY >= visible.minY, window.frame.minY < visible.maxY {
                availableHeight = min(availableHeight, visible.maxY - window.frame.minY - 12 - frameHeight)
            }
            onAvailableSize?(CGSize(width: max(360, visible.width - 32 - frameWidth),
                                    height: max(120, availableHeight)))
            recordDiagnostics(window: window, contentView: contentView)
        }

        private func recordDiagnostics(window: NSWindow, contentView: NSView) {
            guard UserDefaults.standard.bool(forKey: "widget.codex-usage-monitor.layoutDiagnostics"),
                  Date().timeIntervalSince(lastDiagnosticAt) > 0.20 else { return }
            lastDiagnosticAt = Date()
            func rect(_ value: NSRect) -> [Double] { [value.minX, value.minY, value.width, value.height] }
            func size(_ value: NSSize) -> [Double] { [value.width, value.height] }
            var ancestors: [[String: Any]] = []
            var node: NSView? = self
            while let view = node {
                ancestors.append(["class": String(describing: type(of: view)), "frame": rect(view.frame),
                    "bounds": rect(view.bounds), "windowRect": rect(view.convert(view.bounds, to: nil)),
                    "autoresizing": view.autoresizingMask.rawValue,
                    "constraints": view.constraints.filter { [.height, .width, .top, .bottom].contains($0.firstAttribute) }
                        .map { ["attribute": $0.firstAttribute.rawValue, "constant": $0.constant, "priority": $0.priority.rawValue] }])
                node = view.superview
            }
            let record: [String: Any] = ["time": Date().timeIntervalSince1970, "window": String(describing: type(of: window)),
                "windowNumber": window.windowNumber, "instance": String(describing: ObjectIdentifier(self)),
                "canonicalContentRect": rect(window.contentRect(forFrameRect: window.frame)),
                "visibleWindows": NSApp.windows.filter(\.isVisible).map { ["number": $0.windowNumber, "class": String(describing: type(of: $0)), "frame": rect($0.frame)] },
                "frame": rect(window.frame), "contentFrame": rect(contentView.frame),
                "contentBounds": rect(contentView.bounds), "contentLayoutRect": rect(window.contentLayoutRect),
                "target": size(targetSize), "lastTarget": size(targetSize), "animating": false,
                "screen": rect(window.screen?.visibleFrame ?? .zero), "minSize": size(window.minSize),
                "contentMinSize": size(window.contentMinSize), "ancestors": ancestors]
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("DockDoorPro/CodexUsageMonitor")
            let file = root.appendingPathComponent("panel-layout-diagnostics.jsonl")
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                let length = try handle.seekToEnd()
                if length > 2_000_000 { try handle.truncate(atOffset: 0); try handle.seek(toOffset: 0) }
                try handle.write(contentsOf: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
                try handle.write(contentsOf: Data([10]))
            } catch { }
        }

    }
}
