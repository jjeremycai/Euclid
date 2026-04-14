//
//  AppFeature.swift
//  Euclid
//
//  Created by Kit Langton on 1/26/25.
//

import AppKit
import ComposableArchitecture
import Dependencies
import EuclidCore
import SwiftUI

private final class AppRecordingHotKeyProcessorBox: @unchecked Sendable {
  private let lock = NSLock()
  private var processor: RecordingHotKeyProcessor

  init(processor: RecordingHotKeyProcessor) {
    self.processor = processor
  }

  func update(settings: EuclidSettings) {
    let useDoubleTapOnly = settings.doubleTapLockEnabled && settings.useDoubleTapOnly
    withLock {
      processor.updateConfiguration(
        hotkeys: settings.recordingHotkeys,
        useDoubleTapOnly: useDoubleTapOnly,
        doubleTapLockEnabled: settings.doubleTapLockEnabled,
        minimumKeyTime: settings.minimumKeyTime
      )
    }
  }

  func activeState() -> HotKeyProcessor.State {
    withLock { processor.activeState }
  }

  func process(keyEvent: KeyEvent) -> RecordingHotKeyProcessor.Output? {
    withLock { processor.process(keyEvent: keyEvent) }
  }

  func processMouseClick() -> RecordingHotKeyProcessor.Output? {
    withLock { processor.processMouseClick() }
  }

  private func withLock<T>(_ operation: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return operation()
  }
}

@Reducer
struct AppFeature {
  enum ActiveTab: Equatable {
    case settings
    case files
    case remappings
    case history
    case about
  }

	@ObservableState
	struct State {
		var transcription: TranscriptionFeature.State = .init()
		var settings: SettingsFeature.State = .init()
		var files: FilesFeature.State = .init()
		var history: HistoryFeature.State = .init()
		var activeTab: ActiveTab = .settings
		@Shared(.euclidSettings) var euclidSettings: EuclidSettings
		@Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState

    // Permission state
    var microphonePermission: PermissionStatus = .notDetermined
    var accessibilityPermission: PermissionStatus = .notDetermined
    var inputMonitoringPermission: PermissionStatus = .notDetermined

    var allPermissionsGranted: Bool {
      microphonePermission == .granted
        && accessibilityPermission == .granted
        && inputMonitoringPermission == .granted
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case transcription(TranscriptionFeature.Action)
    case settings(SettingsFeature.Action)
    case files(FilesFeature.Action)
    case history(HistoryFeature.Action)
    case dictionarySampleRecordingTapped
    case setActiveTab(ActiveTab)
    case showFiles
    case task
    case pasteLastTranscript

    // Permission actions
    case checkPermissions
    case permissionsUpdated(mic: PermissionStatus, acc: PermissionStatus, input: PermissionStatus)
    case appActivated
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case openMicrophoneSettings
    case openAccessibilitySettings
    case openInputMonitoringSettings
    case modelStatusEvaluated(Bool)
  }

  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.pasteboard) var pasteboard
  @Dependency(\.transcription) var transcription
  @Dependency(\.permissions) var permissions

  var body: some ReducerOf<Self> {
    BindingReducer()

    Scope(state: \.transcription, action: \.transcription) {
      TranscriptionFeature()
    }

    Scope(state: \.settings, action: \.settings) {
      SettingsFeature()
    }

    Scope(state: \.files, action: \.files) {
      FilesFeature()
    }

    Scope(state: \.history, action: \.history) {
      HistoryFeature()
    }

    Reduce { state, action in
      switch action {
      case .binding:
        return .none
        
      case .task:
        return .merge(
          startGlobalInputMonitoring(),
          ensureSelectedModelReadiness(),
          prewarmSelectedModel(),
          startPermissionMonitoring()
        )
        
      case .pasteLastTranscript:
        @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
        guard let lastTranscript = transcriptionHistory.history.first?.text else {
          return .none
        }
        return .run { _ in
          await pasteboard.paste(lastTranscript)
        }
        
      case .transcription(.modelMissing):
        EuclidLog.app.notice("Model missing - activating app and switching to settings")
        state.activeTab = .settings
        state.settings.shouldFlashModelSection = true
        return .run { send in
          await MainActor.run {
            EuclidLog.app.notice("Activating app for model missing")
            NSApplication.shared.activate(ignoringOtherApps: true)
          }
          try? await Task.sleep(for: .seconds(2))
          await send(.settings(.set(\.shouldFlashModelSection, false)))
        }

      case .transcription:
        return .none

      case .settings(.requestMicrophone):
        return .send(.requestMicrophone)

      case .files:
        return .none

      case .settings(.requestAccessibility):
        return .send(.requestAccessibility)

      case .settings(.requestInputMonitoring):
        return .send(.requestInputMonitoring)

      case .settings(.openMicrophoneSettings):
        return .send(.openMicrophoneSettings)

      case .settings(.openAccessibilitySettings):
        return .send(.openAccessibilitySettings)

      case .settings(.openInputMonitoringSettings):
        return .send(.openInputMonitoringSettings)

      case .settings:
        return .none

      case .dictionarySampleRecordingTapped:
        if state.transcription.isRecording {
          return .send(.transcription(.stopRecording))
        }

        guard !state.transcription.isTranscribing else {
          return .none
        }

        let hotkey = state.euclidSettings.recordingHotkeys.first ?? state.euclidSettings.hotkey
        return .send(.transcription(.startRecording(hotkey)))

      case .history(.navigateToSettings):
        state.activeTab = .settings
        return .none
      case .history:
        return .none
		case .showFiles:
			state.activeTab = .files
			return .none
		case let .setActiveTab(tab):
			state.activeTab = tab
			return .none

      // Permission handling
      case .checkPermissions:
        return .run { send in
          async let mic = permissions.microphoneStatus()
          async let acc = permissions.accessibilityStatus()
          async let input = permissions.inputMonitoringStatus()
          await send(.permissionsUpdated(mic: mic, acc: acc, input: input))
        }

      case let .permissionsUpdated(mic, acc, input):
        state.microphonePermission = mic
        state.accessibilityPermission = acc
        state.inputMonitoringPermission = input
        return .none

      case .appActivated:
        // App became active - re-check permissions
        return .send(.checkPermissions)

      case .requestMicrophone:
        return .run { send in
          _ = await permissions.requestMicrophone()
          await send(.checkPermissions)
        }

      case .requestAccessibility:
        return .run { send in
          await permissions.requestAccessibility()
          // Poll for status change (macOS doesn't provide callback)
          for _ in 0..<10 {
            try? await Task.sleep(for: .seconds(1))
            await send(.checkPermissions)
          }
        }

      case .requestInputMonitoring:
        return .run { send in
          _ = await permissions.requestInputMonitoring()
          for _ in 0..<10 {
            try? await Task.sleep(for: .seconds(1))
            await send(.checkPermissions)
          }
        }

      case .openMicrophoneSettings:
        return .run { _ in
          await permissions.openMicrophoneSettings()
        }

      case .openAccessibilitySettings:
        return .run { _ in
          await permissions.openAccessibilitySettings()
        }

      case .openInputMonitoringSettings:
        return .run { _ in
          await permissions.openInputMonitoringSettings()
        }

      case .modelStatusEvaluated:
        return .none
      }
    }
  }
  
  private func startGlobalInputMonitoring() -> Effect<Action> {
    .run { send in
      let hotKeyProcessor = AppRecordingHotKeyProcessorBox(
        processor: RecordingHotKeyProcessor(hotkeys: [HotKey(key: nil, modifiers: [.option])])
      )

      @Shared(.isSettingPasteLastTranscriptHotkey) var isSettingPasteLastTranscriptHotkey: Bool
      @Shared(.isSettingHotKey) var isSettingHotKey: Bool
      @Shared(.euclidSettings) var euclidSettings: EuclidSettings
      let isSettingPasteLastTranscriptHotkeyRef = $isSettingPasteLastTranscriptHotkey
      let isSettingHotKeyRef = $isSettingHotKey
      let euclidSettingsRef = $euclidSettings

      let token = keyEventMonitor.handleInputEvent { inputEvent in
        if isSettingHotKeyRef.withLock({ $0 }) || isSettingPasteLastTranscriptHotkeyRef.withLock({ $0 }) {
          return false
        }

        let settings = euclidSettingsRef.withLock { $0 }
        hotKeyProcessor.update(settings: settings)

        let handled: Bool
        let actions: [Action]

        switch inputEvent {
        case .keyboard(let keyEvent):
          if let pasteHotkey = settings.pasteLastTranscriptHotkey,
             let key = keyEvent.key,
             key == pasteHotkey.key,
             keyEvent.modifiers.matchesExactly(pasteHotkey.modifiers)
          {
            handled = true
            actions = [.pasteLastTranscript]
          } else if keyEvent.key == .escape,
                    keyEvent.modifiers.isEmpty,
                    hotKeyProcessor.activeState() == .idle
          {
            handled = false
            actions = [.transcription(.cancel)]
          } else {
            let useDoubleTapOnly = settings.doubleTapLockEnabled && settings.useDoubleTapOnly
            let output = hotKeyProcessor.process(keyEvent: keyEvent)

            switch output?.action {
            case .startRecording:
              if hotKeyProcessor.activeState() == .doubleTapLock, let hotkey = output?.hotkey {
                handled = useDoubleTapOnly || keyEvent.key != nil
                actions = [.transcription(.startRecording(hotkey))]
              } else if let hotkey = output?.hotkey {
                handled = useDoubleTapOnly || keyEvent.key != nil
                actions = [.transcription(.hotKeyPressed(hotkey))]
              } else {
                handled = false
                actions = []
              }

            case .stopRecording:
              handled = false
              actions = [.transcription(.hotKeyReleased)]

            case .cancel:
              handled = true
              actions = [.transcription(.cancel)]

            case .discard:
              handled = false
              actions = [.transcription(.discard)]

            case nil:
              handled = keyEvent.key.map { pressedKey in
                settings.recordingHotkeys.contains(where: {
                  $0.key == pressedKey && keyEvent.modifiers == $0.modifiers
                })
              } ?? false
              actions = []
            }
          }

        case .mouseClick:
          switch hotKeyProcessor.processMouseClick()?.action {
          case .cancel:
            handled = false
            actions = [.transcription(.cancel)]
          case .discard:
            handled = false
            actions = [.transcription(.discard)]
          case .stopRecording:
            handled = false
            actions = [.transcription(.hotKeyReleased)]
          case .startRecording, nil:
            handled = false
            actions = []
          }
        }

        if !actions.isEmpty {
          Task {
            for action in actions {
              await send(action)
            }
          }
        }

        return handled
      }

      defer { token.cancel() }

      await withTaskCancellationHandler {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(60))
        }
      } onCancel: {
        token.cancel()
      }
    }
  }

  private func ensureSelectedModelReadiness() -> Effect<Action> {
    .run { send in
      @Shared(.euclidSettings) var euclidSettings: EuclidSettings
      @Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState
      let selectedModel = euclidSettings.selectedModel
      guard !selectedModel.isEmpty else {
        await send(.modelStatusEvaluated(false))
        return
      }
      let isReady = await transcription.isModelDownloaded(selectedModel)
      $modelBootstrapState.withLock { state in
        state.modelIdentifier = selectedModel
        if state.modelDisplayName?.isEmpty ?? true {
          state.modelDisplayName = selectedModel
        }
        state.isModelReady = isReady
        if isReady {
          state.lastError = nil
          state.progress = 1
        } else {
          state.progress = 0
        }
      }
      await send(.modelStatusEvaluated(isReady))
    }
  }

  private func prewarmSelectedModel() -> Effect<Action> {
    .run { _ in
      @Shared(.euclidSettings) var euclidSettings: EuclidSettings
      let selectedModel = euclidSettings.selectedModel
      guard !selectedModel.isEmpty else { return }
      await transcription.prewarmModel(selectedModel)
    }
  }

  private func startPermissionMonitoring() -> Effect<Action> {
    .run { send in
      // Initial check on app launch
      await send(.checkPermissions)

      // Monitor app activation events
      for await activation in permissions.observeAppActivation() {
        if case .didBecomeActive = activation {
          await send(.appActivated)
        }
      }

    }
  }

}

struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>
  @State private var columnVisibility = NavigationSplitViewVisibility.automatic

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List(selection: $store.activeTab) {
        Button {
          store.send(.setActiveTab(.settings))
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.settings)

        Button {
          store.send(.setActiveTab(.files))
        } label: {
          Label("Files", systemImage: "tray.and.arrow.down")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.files)

        Button {
          store.send(.setActiveTab(.remappings))
        } label: {
          Label("Dictionary", systemImage: "text.badge.plus")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.remappings)

        Button {
          store.send(.setActiveTab(.history))
        } label: {
          Label("History", systemImage: "clock")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.history)

        Button {
          store.send(.setActiveTab(.about))
        } label: {
          Label("About", systemImage: "info.circle")
        }
        .buttonStyle(.plain)
        .tag(AppFeature.ActiveTab.about)
      }
    } detail: {
      switch store.state.activeTab {
      case .settings:
        SettingsView(
          store: store.scope(state: \.settings, action: \.settings),
          microphonePermission: store.microphonePermission,
          accessibilityPermission: store.accessibilityPermission,
          inputMonitoringPermission: store.inputMonitoringPermission
        )
        .navigationTitle("Settings")
      case .files:
        FilesView(store: store.scope(state: \.files, action: \.files))
          .navigationTitle("Files")
      case .remappings:
        WordRemappingsView(
          store: store.scope(state: \.settings, action: \.settings),
          isRecording: store.transcription.isRecording,
          isTranscribing: store.transcription.isTranscribing,
          onRecordSample: { store.send(.dictionarySampleRecordingTapped) }
        )
          .navigationTitle("Dictionary")
      case .history:
        HistoryView(store: store.scope(state: \.history, action: \.history))
          .navigationTitle("History")
      case .about:
        AboutView(store: store.scope(state: \.settings, action: \.settings))
          .navigationTitle("About")
      }
    }
    .enableInjection()
  }
}
