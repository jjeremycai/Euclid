import AppKit
import ComposableArchitecture
import SwiftUI

/// A floating panel that presents the initial permission setup flow.
/// Positioned below the menu bar, styled as a dark dropdown.
final class SetupPanel {
    private var panel: NSPanel?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(store: StoreOf<AppFeature>, onSetupComplete: @escaping () -> Void = {}) {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let setupView = SetupPanelView(
            store: store,
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onSetupComplete: { [weak self] in
                self?.dismiss()
                onSetupComplete()
            }
        )
        .padding(4)

        let hostingView = NSHostingView(rootView: setupView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position below the menu bar, centered horizontally
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y
            let panelSize = hostingView.fittingSize

            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.maxY - menuBarHeight - panelSize.height - 8
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
