import AVFoundation
import ComposableArchitecture
import EuclidCore
import AppKit

private let appLogger = EuclidLog.app
private let cacheLogger = EuclidLog.caches

@MainActor
class EuclidAppDelegate: NSObject, NSApplicationDelegate {
	var statusItem: NSStatusItem!
	private var launchedAtLogin = false
	private let windowCoordinator = EuclidWindowCoordinator()

	@Dependency(\.soundEffects) var soundEffect
	@Dependency(\.recording) var recording
	@Dependency(\.permissions) var permissions
	@Shared(.euclidSettings) var euclidSettings: EuclidSettings

	func applicationDidFinishLaunching(_: Notification) {
		DiagnosticsLogging.bootstrapIfNeeded()
		// Ensure Parakeet/FluidAudio caches live under Application Support, not ~/.cache
		configureLocalCaches()
		if isTesting {
			appLogger.debug("Running in testing mode")
			return
		}

		Task {
			await soundEffect.preloadSounds()
			await soundEffect.setEnabled(euclidSettings.soundEffectsEnabled)
		}
		launchedAtLogin = wasLaunchedAtLogin()
		appLogger.info("Application did finish launching")
		appLogger.notice("launchedAtLogin = \(self.launchedAtLogin)")

		// Set activation policy first
		updateAppMode()

		// Add notification observer
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleAppModeUpdate),
			name: .updateAppMode,
			object: nil
		)

		// Start long-running app effects (global hotkeys, permissions, etc.)
		startLifecycleTasksIfNeeded()

		// Then present main views
		windowCoordinator.presentMainView(store: EuclidApp.appStore)

		guard shouldOpenForegroundUIOnLaunch else {
			appLogger.notice("Suppressing foreground windows for login launch")
			return
		}

		if needsPermissionSetup() {
			appLogger.notice("Permissions incomplete — showing setup panel")
			windowCoordinator.presentSetupPanel(store: EuclidApp.appStore) { [weak self] in
				self?.presentSettingsView()
			}
		} else {
			presentSettingsView()
		}
		NSApp.activate(ignoringOtherApps: true)
	}

	private var shouldOpenForegroundUIOnLaunch: Bool {
		!(launchedAtLogin && !euclidSettings.showDockIcon)
	}

	private func wasLaunchedAtLogin() -> Bool {
		guard let event = NSAppleEventManager.shared().currentAppleEvent else {
			return false
		}

		return event.eventID == AEEventID(kAEOpenApplication)
			&& event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == AEEventClass(keyAELaunchedAsLogInItem)
	}

	private func startLifecycleTasksIfNeeded() {
		Task { @MainActor in
			await EuclidApp.appStore.send(.task).finish()
		}
	}

	/// Sets XDG_CACHE_HOME so FluidAudio stores models under our app's
	/// Application Support folder, keeping everything in one place.
	private func configureLocalCaches() {
		do {
			let cache = try URL.euclidApplicationSupport.appendingPathComponent("cache", isDirectory: true)
			try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
			setenv("XDG_CACHE_HOME", cache.path, 1)
			cacheLogger.info("XDG_CACHE_HOME set to \(cache.path)")
		} catch {
			cacheLogger.error("Failed to configure local caches: \(error.localizedDescription)")
		}
	}

	func presentMainView() {
		windowCoordinator.presentMainView(store: EuclidApp.appStore)
	}

	func presentSettingsView() {
		presentSettingsView(initialTab: .settings)
	}

	func presentFilesView() {
		presentSettingsView(initialTab: .files)
	}

	func presentSettingsView(initialTab: AppFeature.ActiveTab) {
		Task { @MainActor in
			switch initialTab {
			case .files:
				EuclidApp.appStore.send(.showFiles)
			default:
				EuclidApp.appStore.send(.setActiveTab(initialTab))
			}

			windowCoordinator.presentSettingsView(store: EuclidApp.appStore)
		}
	}

	@objc private func handleAppModeUpdate() {
		Task {
			updateAppMode()
		}
	}

	@MainActor
	private func updateAppMode() {
		appLogger.debug("showDockIcon = \(self.euclidSettings.showDockIcon)")
		if self.euclidSettings.showDockIcon {
			NSApp.setActivationPolicy(.regular)
		} else {
			NSApp.setActivationPolicy(.accessory)
		}
	}

	/// Synchronous check of whether any required permission is missing.
	private func needsPermissionSetup() -> Bool {
		let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
		let accGranted = permissions.accessibilityStatus() == .granted
		let inputGranted = permissions.inputMonitoringStatus() == .granted
		return !micGranted || !accGranted || !inputGranted
	}

	func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
		if needsPermissionSetup() && !windowCoordinator.isSetupVisible {
			windowCoordinator.presentSetupPanel(store: EuclidApp.appStore) { [weak self] in
				self?.presentSettingsView()
			}
		} else {
			presentSettingsView()
		}
		return true
	}

	func applicationWillTerminate(_: Notification) {
		Task {
			await recording.cleanup()
		}
	}
}
