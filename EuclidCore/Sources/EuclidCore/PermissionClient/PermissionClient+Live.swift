@preconcurrency import AppKit
import AVFoundation
import CoreGraphics
import Dependencies
import Foundation
import IOKit
import IOKit.hidsystem

private let logger = EuclidLog.permissions

extension PermissionClient: DependencyKey {
  public static var liveValue: Self {
    let live = PermissionClientLive()
    return Self(
      microphoneStatus: { await live.microphoneStatus() },
      accessibilityStatus: { live.accessibilityStatus() },
      inputMonitoringStatus: { live.inputMonitoringStatus() },
      requestMicrophone: { await live.requestMicrophone() },
      requestAccessibility: { await live.requestAccessibility() },
      requestInputMonitoring: { await live.requestInputMonitoring() },
      openMicrophoneSettings: { await live.openMicrophoneSettings() },
      openAccessibilitySettings: { await live.openAccessibilitySettings() },
      openInputMonitoringSettings: { await live.openInputMonitoringSettings() },
      observeAppActivation: { live.observeAppActivation() }
    )
  }
}

/// Live implementation of the PermissionClient.
///
/// This actor manages permission checking, requesting, and app activation monitoring.
/// It uses NotificationCenter to observe app lifecycle events and provides an AsyncStream
/// for reactive permission updates.
actor PermissionClientLive {
  private let (activationStream, activationContinuation) = AsyncStream<AppActivation>.makeStream()
  private nonisolated(unsafe) var observations: [Any] = []

  init() {
    logger.debug("Initializing PermissionClient, setting up app activation observers")
    // Subscribe to app activation notifications
    let didBecomeActiveObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      logger.debug("App became active")
      Task {
        self?.activationContinuation.yield(.didBecomeActive)
      }
    }

    let willResignActiveObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      logger.debug("App will resign active")
      Task {
        self?.activationContinuation.yield(.willResignActive)
      }
    }

    observations = [didBecomeActiveObserver, willResignActiveObserver]
  }

  deinit {
    observations.forEach { NotificationCenter.default.removeObserver($0) }
  }

  // MARK: - Microphone Permissions

  func microphoneStatus() async -> PermissionStatus {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    let result: PermissionStatus
    switch status {
    case .authorized:
      result = .granted
    case .denied, .restricted:
      result = .denied
    case .notDetermined:
      result = .notDetermined
    @unknown default:
      result = .denied
    }
    logger.info("Microphone status: \(String(describing: result))")
    return result
  }

  func requestMicrophone() async -> Bool {
    logger.info("Requesting microphone permission...")
    let granted = await withCheckedContinuation { continuation in
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        continuation.resume(returning: granted)
      }
    }
    logger.info("Microphone permission granted: \(granted)")
    return granted
  }

  func openMicrophoneSettings() async {
    logger.info("Opening microphone settings in System Preferences...")
    await MainActor.run {
      _ = NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
      )
    }
  }

  // MARK: - Accessibility Permissions

  nonisolated func accessibilityStatus() -> PermissionStatus {
    // Check without prompting (kAXTrustedCheckOptionPrompt: false)
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    let result = AXIsProcessTrustedWithOptions(options) ? PermissionStatus.granted : .denied
    logger.info("Accessibility status: \(String(describing: result))")
    return result
  }

  nonisolated func inputMonitoringStatus() -> PermissionStatus {
    let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    let result = mapIOHIDAccess(access)
    logger.info("Input monitoring status: \(String(describing: result)) (IOHIDAccess: \(String(describing: access)))")
    return result
  }

  func requestAccessibility() async {
    logger.info("Requesting accessibility permission...")
    // Let macOS present the trust prompt first. Jumping directly to System Settings can
    // leave the user on the right pane before the app is actually registered in the list.
    await MainActor.run {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
    }
  }

  func requestInputMonitoring() async -> Bool {
    logger.info("Requesting input monitoring permission...")
    if await MainActor.run(body: { CGPreflightListenEventAccess() }) {
      logger.info("Input monitoring permission already granted")
      return true
    }

    // On current macOS releases, creating the event tap is what reliably causes the
    // app to appear in Input Monitoring. Directly jumping to Settings is confusing if
    // the system has not registered the app yet.
    await triggerInputMonitoringPrompt()

    let granted = await MainActor.run {
      CGPreflightListenEventAccess()
    }
    logger.info("Input monitoring permission granted after prompt attempt: \(granted)")
    return granted
  }

  func openAccessibilitySettings() async {
    logger.info("Opening accessibility settings in System Preferences...")
    await MainActor.run {
      _ = NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
      )
    }
  }

  func openInputMonitoringSettings() async {
    logger.info("Opening input monitoring settings in System Preferences...")
    await MainActor.run {
      _ = NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
      )
    }
  }

  // MARK: - Reactive Monitoring

  nonisolated func observeAppActivation() -> AsyncStream<AppActivation> {
    activationStream
  }

  private nonisolated func mapIOHIDAccess(_ access: IOHIDAccessType) -> PermissionStatus {
    switch access {
    case kIOHIDAccessTypeGranted:
      return .granted
    case kIOHIDAccessTypeDenied:
      return .denied
    default:
      return .notDetermined
    }
  }

  @MainActor
  private func triggerInputMonitoringPrompt() async {
    let eventMask =
      ((1 << CGEventType.keyDown.rawValue)
       | (1 << CGEventType.keyUp.rawValue)
       | (1 << CGEventType.flagsChanged.rawValue))

    let callback: CGEventTapCallBack = { _, _, event, _ in
      Unmanaged.passUnretained(event)
    }

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: callback,
        userInfo: nil
      )
    else {
      logger.notice("Temporary event tap could not be created while requesting Input Monitoring")
      return
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    // Give macOS a moment to present the consent UI/register the app.
    try? await Task.sleep(for: .milliseconds(250))

    CGEvent.tapEnable(tap: eventTap, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
  }
}
