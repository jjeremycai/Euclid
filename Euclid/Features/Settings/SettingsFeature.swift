import AVFoundation
import AppKit
import ComposableArchitecture
import CoreAudio
import Dependencies
import EuclidCore
import IdentifiedCollections
import Sauce
import ServiceManagement
import SwiftUI

private let settingsLogger = EuclidLog.settings
private typealias SettingsAudioPropertyListenerBlock = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

private enum HotKeyCaptureTarget: Equatable {
  case recording(index: Int)
  case addingRecording
  case pasteLastTranscript
}

extension SharedReaderKey
  where Self == InMemoryKey<Bool>.Default
{
  static var isSettingHotKey: Self {
    Self[.inMemory("isSettingHotKey"), default: false]
  }
  
  static var isSettingPasteLastTranscriptHotkey: Self {
    Self[.inMemory("isSettingPasteLastTranscriptHotkey"), default: false]
  }

  static var isRemappingScratchpadFocused: Self {
    Self[.inMemory("isRemappingScratchpadFocused"), default: false]
  }
}

// MARK: - Settings Feature

@Reducer
struct SettingsFeature {
  @ObservableState
  struct State {
    @Shared(.euclidSettings) var euclidSettings: EuclidSettings
    @Shared(.isSettingHotKey) var isSettingHotKey: Bool = false
    @Shared(.isSettingPasteLastTranscriptHotkey) var isSettingPasteLastTranscriptHotkey: Bool = false
    @Shared(.isRemappingScratchpadFocused) var isRemappingScratchpadFocused: Bool = false
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
    @Shared(.hotkeyPermissionState) var hotkeyPermissionState: HotkeyPermissionState

    var languages: IdentifiedArrayOf<Language> = []
    var currentModifiers: Modifiers = .init(modifiers: [])
    var currentPasteLastModifiers: Modifiers = .init(modifiers: [])
    var recordingHotKeyCaptureIndex: Int?
    var isAddingRecordingHotKey: Bool = false
    var remappingScratchpadText: String = ""
    
    // Available microphones
    var availableInputDevices: [AudioInputDevice] = []
    var defaultInputDeviceName: String?

    // Model Management
    var modelDownload = ModelDownloadFeature.State()
    var shouldFlashModelSection = false

  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)

    // Existing
    case task
    case startSettingRecordingHotKey(Int)
    case addRecordingHotKey
    case removeRecordingHotKey(Int)
    case cancelSettingRecordingHotKeyCapture
    case completeSettingHotKeyCapture
    case startSettingPasteLastTranscriptHotkey
    case cancelSettingPasteLastTranscriptHotkeyCapture
    case completeSettingPasteLastTranscriptHotkeyCapture
    case clearPasteLastTranscriptHotkey
    case keyEvent(KeyEvent)
    case toggleOpenOnLogin(Bool)
    case toggleShowDockIcon(Bool)
    case togglePreventSystemSleep(Bool)
    case setRecordingAudioBehavior(RecordingAudioBehavior)
    case setRecordingIndicatorStyle(RecordingIndicatorStyle)
    case setRecordingIndicatorPlacement(RecordingIndicatorPlacement)
    case toggleSuperFastMode(Bool)
    case setUseClipboardPaste(Bool)
    case setCopyToClipboard(Bool)
    case setDoubleTapLockEnabled(Bool)
    case setUseDoubleTapOnly(Bool)
    case setMinimumKeyTime(Double)
    case setOutputLanguage(String?)
    case setSelectedMicrophoneID(String?)
    case setSoundEffectsEnabled(Bool)
    case setSoundEffectsVolume(Double)

    // Permission delegation (forwarded to AppFeature)
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case openMicrophoneSettings
    case openAccessibilitySettings
    case openInputMonitoringSettings

    // Microphone selection
    case loadAvailableInputDevices
    case availableInputDevicesLoaded([AudioInputDevice], String?)

    // Model Management
    case modelDownload(ModelDownloadFeature.Action)
    
    // History Management
    case toggleSaveTranscriptionHistory(Bool)
    case setMaxHistoryEntries(Int?)

    // Modifier configuration
    case setModifierSide(Int, Modifier.Kind, Modifier.Side)

    // Word remappings
    case setWordRemovalsEnabled(Bool)
    case addWordRemoval
    case updateWordRemoval(WordRemoval)
    case removeWordRemoval(UUID)
    case addWordRemapping
    case updateWordRemapping(WordRemapping)
    case removeWordRemapping(UUID)
    case addVocabularyTerm
    case updateVocabularyTerm(VocabularyTerm)
    case removeVocabularyTerm(UUID)
    case setRemappingScratchpadFocused(Bool)
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.transcription) var transcription
  @Dependency(\.recording) var recording
  @Dependency(\.permissions) var permissions
  @Dependency(\.soundEffects) var soundEffects
  @Dependency(\.transcriptPersistence) var transcriptPersistence

  private func deleteAudioEffect(for transcripts: [Transcript]) -> Effect<Action> {
    .run { [transcriptPersistence] _ in
      for transcript in transcripts {
        try? await transcriptPersistence.deleteAudio(transcript)
      }
    }
  }

  private func beginCapture(_ target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case let .recording(index):
      state.$isSettingHotKey.withLock { $0 = true }
      state.recordingHotKeyCaptureIndex = index
      state.isAddingRecordingHotKey = false
      state.currentModifiers = .init(modifiers: [])
    case .addingRecording:
      state.$isSettingHotKey.withLock { $0 = true }
      state.recordingHotKeyCaptureIndex = nil
      state.isAddingRecordingHotKey = true
      state.currentModifiers = .init(modifiers: [])
    case .pasteLastTranscript:
      state.$isSettingPasteLastTranscriptHotkey.withLock { $0 = true }
      state.currentPasteLastModifiers = .init(modifiers: [])
    }
  }

  private func endCapture(_ target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case .recording, .addingRecording:
      state.$isSettingHotKey.withLock { $0 = false }
      state.recordingHotKeyCaptureIndex = nil
      state.isAddingRecordingHotKey = false
      state.currentModifiers = .init(modifiers: [])
    case .pasteLastTranscript:
      state.$isSettingPasteLastTranscriptHotkey.withLock { $0 = false }
      state.currentPasteLastModifiers = .init(modifiers: [])
    }
  }

  private func captureModifiers(for target: HotKeyCaptureTarget, state: State) -> Modifiers {
    switch target {
    case .recording, .addingRecording:
      state.currentModifiers
    case .pasteLastTranscript:
      state.currentPasteLastModifiers
    }
  }

  private func updateCaptureModifiers(_ modifiers: Modifiers, for target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case .recording, .addingRecording:
      state.currentModifiers = modifiers
    case .pasteLastTranscript:
      state.currentPasteLastModifiers = modifiers
    }
  }

  private func applyCapturedHotKey(key: Key?, modifiers: Modifiers, for target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case let .recording(index):
      state.$euclidSettings.withLock {
        $0.setRecordingHotKey(
          HotKey(key: key, modifiers: modifiers.erasingSides()),
          at: index
        )
      }
    case .addingRecording:
      state.$euclidSettings.withLock {
        $0.appendRecordingHotKey(HotKey(key: key, modifiers: modifiers.erasingSides()))
      }
    case .pasteLastTranscript:
      guard let key else { return }
      state.$euclidSettings.withLock {
        $0.pasteLastTranscriptHotkey = HotKey(key: key, modifiers: modifiers.erasingSides())
      }
    }
  }

  private func finishCaptureEffect(for target: HotKeyCaptureTarget) -> Effect<Action> {
    .run { send in
      try? await Task.sleep(for: .milliseconds(100))
      switch target {
      case .recording, .addingRecording:
        await send(.completeSettingHotKeyCapture)
      case .pasteLastTranscript:
        await send(.completeSettingPasteLastTranscriptHotkeyCapture)
      }
    }
  }

  private func handleCapture(_ keyEvent: KeyEvent, for target: HotKeyCaptureTarget, state: inout State) -> Effect<Action> {
    if keyEvent.key == .escape {
      endCapture(target, state: &state)
      return .none
    }

    let updatedModifiers = keyEvent.modifiers.union(captureModifiers(for: target, state: state))
    updateCaptureModifiers(updatedModifiers, for: target, state: &state)

    if target == .pasteLastTranscript, keyEvent.key != nil, updatedModifiers.isEmpty {
      return .none
    }

    if let key = keyEvent.key {
      applyCapturedHotKey(key: key, modifiers: updatedModifiers, for: target, state: &state)
      return finishCaptureEffect(for: target)
    }

    if target != .pasteLastTranscript, keyEvent.modifiers.isEmpty, !updatedModifiers.isEmpty {
      applyCapturedHotKey(key: nil, modifiers: updatedModifiers, for: target, state: &state)
      return finishCaptureEffect(for: target)
    }

    return .none
  }

  private func recordingCaptureTarget(for state: State) -> HotKeyCaptureTarget? {
    if let index = state.recordingHotKeyCaptureIndex {
      return .recording(index: index)
    }
    if state.isAddingRecordingHotKey {
      return .addingRecording
    }
    return nil
  }

  var body: some ReducerOf<Self> {
    BindingReducer()

    Scope(state: \.modelDownload, action: \.modelDownload) {
      ModelDownloadFeature()
    }

    Reduce { state, action in
      switch action {
      case .binding:
        let didNormalizeDoubleTapOnly = !state.euclidSettings.doubleTapLockEnabled && state.euclidSettings.useDoubleTapOnly
        if didNormalizeDoubleTapOnly {
          state.$euclidSettings.withLock {
            $0.useDoubleTapOnly = false
          }
        }

        return .none

      case .task:
        if let url = Bundle.main.url(forResource: "languages", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let languages = try? JSONDecoder().decode([Language].self, from: data)
        {
          state.languages = IdentifiedArray(uniqueElements: languages)
        } else {
          settingsLogger.error("Failed to load languages JSON from bundle")
        }

        // Listen for key events and load microphones (existing + new)
        return .run { send in
          func audioPropertyAddress(
            _ selector: AudioObjectPropertySelector,
            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
            element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
          ) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
              mSelector: selector,
              mScope: scope,
              mElement: element
            )
          }

          await send(.modelDownload(.fetchModels))
          await send(.loadAvailableInputDevices)

          // Set up periodic refresh of available devices (every 120 seconds)
          // Using a longer interval to reduce resource usage
	          let deviceRefreshTask = Task { @MainActor in
	            for await _ in clock.timer(interval: .seconds(120)) {
	              // Only refresh when the app is active to save resources
	              if NSApplication.shared.isActive {
	                send(.loadAvailableInputDevices)
	              }
	            }
	          }

          // Listen for device connection/disconnection notifications
          // Using a simpler debounced approach with a single task
          var deviceUpdateTask: Task<Void, Never>?
          var audioHardwareObservers: [(AudioObjectPropertySelector, SettingsAudioPropertyListenerBlock)] = []

          // Helper function to debounce device updates
          func debounceDeviceUpdate() {
            deviceUpdateTask?.cancel()
            deviceUpdateTask = Task {
              try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
              if !Task.isCancelled {
                await send(.loadAvailableInputDevices)
              }
            }
          }

          func installAudioHardwareObserver(_ selector: AudioObjectPropertySelector) {
            let listener: SettingsAudioPropertyListenerBlock = { _, _ in
              debounceDeviceUpdate()
            }
            var address = audioPropertyAddress(selector)
            let status = AudioObjectAddPropertyListenerBlock(
              AudioObjectID(kAudioObjectSystemObject),
              &address,
              DispatchQueue.main,
              listener
            )

            if status == noErr {
              audioHardwareObservers.append((selector, listener))
            } else {
              settingsLogger.error("Failed to observe audio hardware selector \(selector): \(status)")
            }
          }

          let deviceConnectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "AVCaptureDeviceWasConnected"),
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }
          
          let deviceDisconnectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "AVCaptureDeviceWasDisconnected"),
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }

          let appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }

          let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }

          installAudioHardwareObserver(kAudioHardwarePropertyDefaultInputDevice)
          installAudioHardwareObserver(kAudioHardwarePropertyDevices)

          // Be sure to clean up resources when the task is finished
          defer {
            deviceUpdateTask?.cancel()
            NotificationCenter.default.removeObserver(deviceConnectionObserver)
            NotificationCenter.default.removeObserver(deviceDisconnectionObserver)
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)

            for (selector, listener) in audioHardwareObservers {
              var address = audioPropertyAddress(selector)
              let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                listener
              )
              if status != noErr {
                settingsLogger.error("Failed to remove audio hardware observer for selector \(selector): \(status)")
              }
            }
          }

          await withTaskCancellationHandler {
            while !Task.isCancelled {
              try? await Task.sleep(for: .seconds(60))
            }
          } onCancel: {
            deviceRefreshTask.cancel()
          }
        }

      case let .startSettingRecordingHotKey(index):
        settingsLogger.info("Starting recording hotkey capture for index \(index)")
        beginCapture(.recording(index: index), state: &state)
        return .none

      case .addRecordingHotKey:
        settingsLogger.info("Starting recording hotkey capture for new shortcut")
        beginCapture(.addingRecording, state: &state)
        return .none

      case let .removeRecordingHotKey(index):
        state.$euclidSettings.withLock {
          $0.removeRecordingHotKey(at: index)
        }
        return .none

      case .cancelSettingRecordingHotKeyCapture:
        if let target = recordingCaptureTarget(for: state) {
          endCapture(target, state: &state)
        }
        return .none

      case .completeSettingHotKeyCapture:
        settingsLogger.info("Finished recording hotkey capture")
        if let target = recordingCaptureTarget(for: state) {
          endCapture(target, state: &state)
        }
        return .none

      case .addWordRemoval:
        state.$euclidSettings.withLock {
          $0.wordRemovals.append(.init(pattern: ""))
        }
        return .none

      case let .updateWordRemoval(removal):
        state.$euclidSettings.withLock {
          guard let index = $0.wordRemovals.firstIndex(where: { $0.id == removal.id }) else { return }
          $0.wordRemovals[index] = removal
        }
        return .none

      case let .removeWordRemoval(id):
        state.$euclidSettings.withLock {
          $0.wordRemovals.removeAll { $0.id == id }
        }
        return .none

      case .addWordRemapping:
        state.$euclidSettings.withLock {
          $0.wordRemappings.append(.init(match: "", replacement: ""))
        }
        return .none

      case let .updateWordRemapping(remapping):
        state.$euclidSettings.withLock {
          guard let index = $0.wordRemappings.firstIndex(where: { $0.id == remapping.id }) else { return }
          $0.wordRemappings[index] = remapping
        }
        return .none

      case let .removeWordRemapping(id):
        state.$euclidSettings.withLock {
          $0.wordRemappings.removeAll { $0.id == id }
        }
        return .none

      case .addVocabularyTerm:
        state.$euclidSettings.withLock {
          $0.vocabularyTerms.append(.init(term: ""))
        }
        return .none

      case let .updateVocabularyTerm(term):
        state.$euclidSettings.withLock {
          guard let index = $0.vocabularyTerms.firstIndex(where: { $0.id == term.id }) else { return }
          $0.vocabularyTerms[index] = term
        }
        return .none

      case let .removeVocabularyTerm(id):
        state.$euclidSettings.withLock {
          $0.vocabularyTerms.removeAll { $0.id == id }
        }
        return .none

      case let .setRemappingScratchpadFocused(isFocused):
        state.$isRemappingScratchpadFocused.withLock { $0 = isFocused }
        return .none

      case .startSettingPasteLastTranscriptHotkey:
        settingsLogger.info("Starting paste-last hotkey capture")
        beginCapture(.pasteLastTranscript, state: &state)
        return .none

      case .cancelSettingPasteLastTranscriptHotkeyCapture:
        endCapture(.pasteLastTranscript, state: &state)
        return .none

      case .completeSettingPasteLastTranscriptHotkeyCapture:
        settingsLogger.info("Finished paste-last hotkey capture")
        endCapture(.pasteLastTranscript, state: &state)
        return .none
        
      case .clearPasteLastTranscriptHotkey:
        state.$euclidSettings.withLock { $0.pasteLastTranscriptHotkey = nil }
        return .none

      case let .keyEvent(keyEvent):
        if state.isSettingPasteLastTranscriptHotkey {
          return handleCapture(keyEvent, for: .pasteLastTranscript, state: &state)
        }

        guard state.isSettingHotKey else { return .none }
        guard let target = recordingCaptureTarget(for: state) else { return .none }
        return handleCapture(keyEvent, for: target, state: &state)

      case let .toggleOpenOnLogin(enabled):
        state.$euclidSettings.withLock { $0.openOnLogin = enabled }
        return .run { _ in
          if enabled {
            try? SMAppService.mainApp.register()
          } else {
            try? SMAppService.mainApp.unregister()
          }
        }

      case let .toggleShowDockIcon(enabled):
        state.$euclidSettings.withLock { $0.showDockIcon = enabled }
        return .run { _ in
          await MainActor.run {
            NotificationCenter.default.post(name: .updateAppMode, object: nil)
          }
        }

      case let .togglePreventSystemSleep(enabled):
        state.$euclidSettings.withLock { $0.preventSystemSleep = enabled }
        return .none

      case let .setUseClipboardPaste(enabled):
        state.$euclidSettings.withLock { $0.useClipboardPaste = enabled }
        return .none

      case let .setCopyToClipboard(enabled):
        state.$euclidSettings.withLock { $0.copyToClipboard = enabled }
        return .none

      case let .setRecordingAudioBehavior(behavior):
        state.$euclidSettings.withLock { $0.recordingAudioBehavior = behavior }
        return .none

      case let .setRecordingIndicatorStyle(style):
        state.$euclidSettings.withLock { $0.recordingIndicatorStyle = style }
        return .none

      case let .setRecordingIndicatorPlacement(placement):
        state.$euclidSettings.withLock { $0.recordingIndicatorPlacement = placement }
        return .none

      case let .toggleSuperFastMode(enabled):
        state.$euclidSettings.withLock { $0.superFastModeEnabled = enabled }
        return .run { _ in
          await recording.warmUpRecorder()
        }

      case let .setDoubleTapLockEnabled(enabled):
        state.$euclidSettings.withLock {
          $0.doubleTapLockEnabled = enabled
          if !enabled {
            $0.useDoubleTapOnly = false
          }
        }
        return .none

      case let .setUseDoubleTapOnly(enabled):
        state.$euclidSettings.withLock {
          $0.useDoubleTapOnly = enabled && $0.doubleTapLockEnabled
        }
        return .none

      case let .setMinimumKeyTime(value):
        state.$euclidSettings.withLock { $0.minimumKeyTime = value }
        return .none

      case let .setOutputLanguage(language):
        state.$euclidSettings.withLock { $0.outputLanguage = language }
        return .none

      case let .setSelectedMicrophoneID(deviceID):
        state.$euclidSettings.withLock { $0.selectedMicrophoneID = deviceID }
        return .none

      case let .setSoundEffectsEnabled(enabled):
        state.$euclidSettings.withLock { $0.soundEffectsEnabled = enabled }
        return .run { _ in
          await soundEffects.setEnabled(enabled)
        }

      case let .setSoundEffectsVolume(volume):
        state.$euclidSettings.withLock { $0.soundEffectsVolume = volume }
        return .none

      // Permission requests
      case .requestMicrophone:
        return .none

      case .requestAccessibility:
        return .none

      case .requestInputMonitoring:
        return .none

      case .openMicrophoneSettings:
        settingsLogger.info("User opened microphone settings from settings")
        return .run { _ in
          await permissions.openMicrophoneSettings()
        }

      case .openAccessibilitySettings:
        settingsLogger.info("User opened accessibility settings from settings")
        return .run { _ in
          await permissions.openAccessibilitySettings()
        }

      case .openInputMonitoringSettings:
        settingsLogger.info("User opened input monitoring settings from settings")
        return .run { _ in
          await permissions.openInputMonitoringSettings()
        }

      // Model Management
      case let .modelDownload(.selectModel(newModel)):
        // Also store it in euclidSettings:
        state.$euclidSettings.withLock {
          $0.selectedModel = newModel
        }
        // Then continue with the child's normal logic:
        return .none

      case .modelDownload:
        return .none
      
      // Microphone device selection
      case .loadAvailableInputDevices:
        return .run { send in
          let devices = await recording.getAvailableInputDevices()
          let defaultName = await recording.getDefaultInputDeviceName()
          await send(.availableInputDevicesLoaded(devices, defaultName))
        }
        
      case let .availableInputDevicesLoaded(devices, defaultName):
        state.availableInputDevices = devices
        state.defaultInputDeviceName = defaultName
        return .none
        
      case let .toggleSaveTranscriptionHistory(enabled):
        state.$euclidSettings.withLock { $0.saveTranscriptionHistory = enabled }
        
        // If disabling history, delete all existing entries
        if !enabled {
          let transcripts = state.transcriptionHistory.history
          
          // Clear the history
          state.$transcriptionHistory.withLock { history in
            history.history.removeAll()
          }

          return deleteAudioEffect(for: transcripts)
        }
        
        return .none

      case let .setMaxHistoryEntries(maxHistoryEntries):
        state.$euclidSettings.withLock { $0.maxHistoryEntries = maxHistoryEntries }
        return .none

      case let .setModifierSide(index, kind, side):
        state.$euclidSettings.withLock {
          $0.setRecordingHotKeyModifierSide(at: index, kind: kind, side: side)
        }
        return .none

      case let .setWordRemovalsEnabled(enabled):
        state.$euclidSettings.withLock { $0.wordRemovalsEnabled = enabled }
        return .none

      }
    }
  }
}
