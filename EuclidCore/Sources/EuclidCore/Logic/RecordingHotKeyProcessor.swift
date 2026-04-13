import Foundation

public struct RecordingHotKeyProcessor {
	public struct Output: Equatable {
		public var action: HotKeyProcessor.Output
		public var hotkey: HotKey

		public init(action: HotKeyProcessor.Output, hotkey: HotKey) {
			self.action = action
			self.hotkey = hotkey
		}
	}

	private(set) var processors: [HotKeyProcessor]
	private(set) var hotkeys: [HotKey]
	private var activeIndex: Int?

	public init(
		hotkeys: [HotKey],
		useDoubleTapOnly: Bool = false,
		doubleTapLockEnabled: Bool = true,
		minimumKeyTime: TimeInterval = EuclidCoreConstants.defaultMinimumKeyTime
	) {
		let configuredHotkeys = hotkeys.isEmpty ? [HotKey(key: nil, modifiers: [.option])] : hotkeys
		self.hotkeys = configuredHotkeys
		self.processors = configuredHotkeys.map {
			HotKeyProcessor(
				hotkey: $0,
				useDoubleTapOnly: useDoubleTapOnly,
				doubleTapLockEnabled: doubleTapLockEnabled,
				minimumKeyTime: minimumKeyTime
			)
		}
	}

	public var activeState: HotKeyProcessor.State {
		guard let activeIndex, processors.indices.contains(activeIndex) else { return .idle }
		return processors[activeIndex].state
	}

	public mutating func updateConfiguration(
		hotkeys: [HotKey],
		useDoubleTapOnly: Bool,
		doubleTapLockEnabled: Bool,
		minimumKeyTime: TimeInterval
	) {
		let configuredHotkeys = hotkeys.isEmpty ? [HotKey(key: nil, modifiers: [.option])] : hotkeys
		let needsRebuild = configuredHotkeys != self.hotkeys || processors.count != configuredHotkeys.count
		self.hotkeys = configuredHotkeys

		if needsRebuild {
			processors = configuredHotkeys.map {
				HotKeyProcessor(
					hotkey: $0,
					useDoubleTapOnly: useDoubleTapOnly,
					doubleTapLockEnabled: doubleTapLockEnabled,
					minimumKeyTime: minimumKeyTime
				)
			}
			activeIndex = nil
			return
		}

		for index in processors.indices {
			processors[index].useDoubleTapOnly = useDoubleTapOnly
			processors[index].doubleTapLockEnabled = doubleTapLockEnabled
			processors[index].minimumKeyTime = minimumKeyTime
		}
	}

	public mutating func process(keyEvent: KeyEvent) -> Output? {
		if let activeIndex, processors.indices.contains(activeIndex) {
			return processActiveKeyEvent(keyEvent, at: activeIndex)
		}

		for index in processors.indices {
			if let output = processors[index].process(keyEvent: keyEvent) {
				return handleOutput(output, from: index)
			}
		}

		return nil
	}

	public mutating func processMouseClick() -> Output? {
		guard let activeIndex, processors.indices.contains(activeIndex) else { return nil }
		guard let output = processors[activeIndex].processMouseClick() else { return nil }
		return handleOutput(output, from: activeIndex)
	}
}

private extension RecordingHotKeyProcessor {
	mutating func processActiveKeyEvent(_ keyEvent: KeyEvent, at index: Int) -> Output? {
		guard let output = processors[index].process(keyEvent: keyEvent) else {
			if processors[index].state == .idle {
				activeIndex = nil
			}
			return nil
		}
		return handleOutput(output, from: index)
	}

	mutating func handleOutput(_ output: HotKeyProcessor.Output, from index: Int) -> Output {
		switch output {
		case .startRecording:
			activeIndex = index
		case .stopRecording, .cancel, .discard:
			activeIndex = nil
		}

		return Output(action: output, hotkey: hotkeys[index])
	}
}
