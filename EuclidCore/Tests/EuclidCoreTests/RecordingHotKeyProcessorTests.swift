import Dependencies
import Foundation
@testable import EuclidCore
import Sauce
import Testing

struct RecordingHotKeyProcessorTests {
	@Test
	func startsModifierOnlyShortcutFromConfiguredList() {
		let fnHotKey = HotKey(key: nil, modifiers: [.fn])
		let letterHotKey = HotKey(key: .s, modifiers: [.option, .shift])
		var processor = RecordingHotKeyProcessor(hotkeys: [fnHotKey, letterHotKey])

		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 0)
		} operation: {
			let output = processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.fn]))
			#expect(output == .init(action: .startRecording, hotkey: fnHotKey))
			#expect(processor.activeState != .idle)
		}
	}

	@Test
	func startsSecondShortcutWithoutInterferingWithPrimary() {
		let fnHotKey = HotKey(key: nil, modifiers: [.fn])
		let letterHotKey = HotKey(key: .s, modifiers: [.option, .shift])
		var processor = RecordingHotKeyProcessor(hotkeys: [fnHotKey, letterHotKey])

		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 0)
		} operation: {
			let start = processor.process(keyEvent: KeyEvent(key: nil, modifiers: [.fn]))
			#expect(start == .init(action: .startRecording, hotkey: fnHotKey))
		}

		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 0.2)
		} operation: {
			let stop = processor.process(keyEvent: KeyEvent(key: nil, modifiers: []))
			#expect(stop == .init(action: .stopRecording, hotkey: fnHotKey))
			#expect(processor.activeState == .idle)
		}

		withDependencies {
			$0.date.now = Date(timeIntervalSince1970: 0.3)
		} operation: {
			let start = processor.process(keyEvent: KeyEvent(key: .s, modifiers: [.option, .shift]))
			#expect(start == .init(action: .startRecording, hotkey: letterHotKey))
		}
	}
}
