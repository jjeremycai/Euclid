import XCTest
@testable import EuclidCore

final class EuclidSettingsMigrationTests: XCTestCase {
	func testV1FixtureMigratesToCurrentDefaults() throws {
		let data = try loadFixture(named: "v1")
		let decoded = try JSONDecoder().decode(EuclidSettings.self, from: data)

		XCTAssertEqual(decoded.recordingAudioBehavior, .pauseMedia, "Legacy pauseMediaOnRecord bool should map to pauseMedia behavior")
		XCTAssertEqual(decoded.soundEffectsEnabled, false)
		XCTAssertEqual(decoded.soundEffectsVolume, EuclidSettings.baseSoundEffectsVolume)
		XCTAssertEqual(decoded.openOnLogin, true)
		XCTAssertEqual(decoded.showDockIcon, false)
		XCTAssertEqual(decoded.selectedModel, "whisper-large-v3")
		XCTAssertEqual(decoded.useClipboardPaste, false)
			XCTAssertEqual(decoded.preventSystemSleep, true)
			XCTAssertEqual(decoded.recordingIndicatorStyle, .notch)
		XCTAssertEqual(decoded.recordingIndicatorPlacement, .top)
		XCTAssertEqual(decoded.minimumKeyTime, 0.25)
		XCTAssertEqual(decoded.copyToClipboard, true)
		XCTAssertFalse(decoded.superFastModeEnabled)
		XCTAssertEqual(decoded.useDoubleTapOnly, true)
		XCTAssertEqual(decoded.doubleTapLockEnabled, true)
		XCTAssertEqual(decoded.outputLanguage, "en")
		XCTAssertEqual(decoded.selectedMicrophoneID, "builtin:mic")
		XCTAssertEqual(decoded.saveTranscriptionHistory, false)
		XCTAssertEqual(decoded.maxHistoryEntries, 10)
		XCTAssertEqual(decoded.hasCompletedModelBootstrap, true)
		XCTAssertEqual(decoded.hasCompletedStorageMigration, true)
	}

	func testEncodeDecodeRoundTripPreservesDefaults() throws {
		let settings = EuclidSettings()
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(EuclidSettings.self, from: data)
		XCTAssertEqual(decoded, settings)
	}

	func testLegacyRecordingIndicatorStyleNamesDecodeToCurrentStyles() throws {
		let legacyPairs: [(String, RecordingIndicatorStyle)] = [
			("underneathNotch", .notch),
			("floatingBar", .panel),
			("circle", .circle),
		]

		for (legacyRawValue, expectedStyle) in legacyPairs {
			let payload = #"{"recordingIndicatorStyle":"\#(legacyRawValue)"}"#
			let data = try XCTUnwrap(payload.data(using: .utf8))
			let decoded = try JSONDecoder().decode(EuclidSettings.self, from: data)

			XCTAssertEqual(decoded.recordingIndicatorStyle, expectedStyle, "Expected \(legacyRawValue) to decode as \(expectedStyle)")
		}
	}

	func testInitNormalizesDoubleTapOnlyWhenLockDisabled() {
		let settings = EuclidSettings(useDoubleTapOnly: true, doubleTapLockEnabled: false)

		XCTAssertFalse(settings.useDoubleTapOnly)
		XCTAssertFalse(settings.doubleTapLockEnabled)
	}

	func testDecodeNormalizesDoubleTapOnlyWhenLockDisabled() throws {
		let payload = "{\"useDoubleTapOnly\":true,\"doubleTapLockEnabled\":false}"
		guard let data = payload.data(using: .utf8) else {
			XCTFail("Failed to encode JSON payload")
			return
		}

		let decoded = try JSONDecoder().decode(EuclidSettings.self, from: data)

		XCTAssertFalse(decoded.useDoubleTapOnly)
		XCTAssertFalse(decoded.doubleTapLockEnabled)
	}

	func testEncodeDecodeRoundTripPreservesNormalizedDoubleTapValues() throws {
		let settings = EuclidSettings(useDoubleTapOnly: true, doubleTapLockEnabled: false)
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(EuclidSettings.self, from: data)

		XCTAssertFalse(settings.useDoubleTapOnly)
		XCTAssertFalse(decoded.useDoubleTapOnly)
		XCTAssertEqual(decoded, settings)
	}

	private func loadFixture(named name: String) throws -> Data {
		guard let url = Bundle.module.url(
			forResource: name,
			withExtension: "json",
			subdirectory: "Fixtures/EuclidSettings"
		) else {
			XCTFail("Missing fixture \(name).json")
			throw NSError(domain: "Fixture", code: 0)
		}
		return try Data(contentsOf: url)
	}
}
