import AVFoundation
import ComposableArchitecture
import ConcurrencyExtras
import EuclidCore
import Foundation
import XCTest

@testable import Euclid

@MainActor
final class FilesFeatureTests: XCTestCase {
  func testQueueProcessesMultipleFilesSerially() async throws {
    let firstSource = URL(fileURLWithPath: "/tmp/first.m4a")
    let secondSource = URL(fileURLWithPath: "/tmp/second.mp4")
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let firstPrepared = PreparedImportedMedia(
      normalizedURL: URL(fileURLWithPath: "/tmp/first-normalized.wav"),
      duration: 1.2,
      sourceFilename: firstSource.lastPathComponent
    )
    let secondPrepared = PreparedImportedMedia(
      normalizedURL: URL(fileURLWithPath: "/tmp/second-normalized.wav"),
      duration: 2.4,
      sourceFilename: secondSource.lastPathComponent
    )

    let store = TestStore(initialState: Self.makeState(saveHistory: false)) {
      FilesFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.importedMediaPreparation.isSupported = { _ in true }
      $0.importedMediaPreparation.prepare = { url in
        url == firstSource ? firstPrepared : secondPrepared
      }
      $0.transcription.transcribe = { url, _, _, _, _ in
        url == firstPrepared.normalizedURL ? "first transcript" : "second transcript"
      }
      $0.pasteboard.copy = { _ in }
    }

    await store.send(.enqueueFiles([firstSource, secondSource])) {
      $0.items.append(.init(id: firstID, sourceURL: firstSource))
      $0.items.append(.init(id: secondID, sourceURL: secondSource))
      $0.selectedItemID = firstID
    }

    await store.receive(.processNext) {
      $0.items[id: firstID]?.status = .preparing
    }
    await store.receive(.processingSucceeded(firstID, "first transcript", 1.2)) {
      $0.items[id: firstID]?.status = .completed
      $0.items[id: firstID]?.transcript = "first transcript"
      $0.items[id: firstID]?.duration = 1.2
    }
    await store.receive(.processNext) {
      $0.items[id: secondID]?.status = .preparing
    }
    await store.receive(.processingSucceeded(secondID, "second transcript", 2.4)) {
      $0.items[id: secondID]?.status = .completed
      $0.items[id: secondID]?.transcript = "second transcript"
      $0.items[id: secondID]?.duration = 2.4
    }
    await store.receive(.processNext)
  }

  func testFailedItemDoesNotBlockNextQueuedFile() async throws {
    let firstSource = URL(fileURLWithPath: "/tmp/bad.mov")
    let secondSource = URL(fileURLWithPath: "/tmp/good.m4a")
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let firstPrepared = PreparedImportedMedia(
      normalizedURL: URL(fileURLWithPath: "/tmp/bad-normalized.wav"),
      duration: 1.0,
      sourceFilename: firstSource.lastPathComponent
    )
    let secondPrepared = PreparedImportedMedia(
      normalizedURL: URL(fileURLWithPath: "/tmp/good-normalized.wav"),
      duration: 3.0,
      sourceFilename: secondSource.lastPathComponent
    )

    let store = TestStore(initialState: Self.makeState(saveHistory: false)) {
      FilesFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.importedMediaPreparation.isSupported = { _ in true }
      $0.importedMediaPreparation.prepare = { url in
        url == firstSource ? firstPrepared : secondPrepared
      }
      $0.transcription.transcribe = { url, _, _, _, _ in
        if url == firstPrepared.normalizedURL {
          throw NSError(domain: "FilesFeatureTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Broken file"])
        }
        return "good transcript"
      }
      $0.pasteboard.copy = { _ in }
    }

    await store.send(.enqueueFiles([firstSource, secondSource])) {
      $0.items.append(.init(id: firstID, sourceURL: firstSource))
      $0.items.append(.init(id: secondID, sourceURL: secondSource))
      $0.selectedItemID = firstID
    }

    await store.receive(.processNext) {
      $0.items[id: firstID]?.status = .preparing
    }
    await store.receive(.processingFailed(firstID, "Broken file")) {
      $0.items[id: firstID]?.status = .failed("Broken file")
    }
    await store.receive(.processNext) {
      $0.items[id: secondID]?.status = .preparing
    }
    await store.receive(.processingSucceeded(secondID, "good transcript", 3.0)) {
      $0.items[id: secondID]?.status = .completed
      $0.items[id: secondID]?.transcript = "good transcript"
      $0.items[id: secondID]?.duration = 3.0
    }
    await store.receive(.processNext)
  }

  func testCopyTranscriptUsesClipboard() async throws {
    let sourceURL = URL(fileURLWithPath: "/tmp/copiable.m4a")
    let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let prepared = PreparedImportedMedia(
      normalizedURL: URL(fileURLWithPath: "/tmp/copiable-normalized.wav"),
      duration: 1.0,
      sourceFilename: sourceURL.lastPathComponent
    )

    let copiedText = LockIsolated<String?>(nil)
    let store = TestStore(initialState: Self.makeState(saveHistory: false)) {
      FilesFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.importedMediaPreparation.isSupported = { _ in true }
      $0.importedMediaPreparation.prepare = { _ in prepared }
      $0.transcription.transcribe = { _, _, _, _, _ in "copied text" }
      $0.pasteboard.copy = { text in
        copiedText.setValue(text)
      }
    }

    await store.send(.enqueueFiles([sourceURL])) {
      $0.items.append(.init(id: itemID, sourceURL: sourceURL))
      $0.selectedItemID = itemID
    }

    await store.receive(.processNext) {
      $0.items[id: itemID]?.status = .preparing
    }
    await store.receive(.processingSucceeded(itemID, "copied text", 1.0)) {
      $0.items[id: itemID]?.status = .completed
      $0.items[id: itemID]?.transcript = "copied text"
      $0.items[id: itemID]?.duration = 1.0
    }
    await store.receive(.processNext)

    await store.send(.copyTranscript(itemID))
    XCTAssertEqual(copiedText.value, "copied text")
  }

  func testHistoryDisabledDeletesNormalizedAudioAfterSuccess() async throws {
    let sourceURL = URL(fileURLWithPath: "/tmp/history-disabled.wav")
    let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let normalizedURL = try Self.makeTemporaryAudioFile(name: "history-disabled-normalized")
    let prepared = PreparedImportedMedia(
      normalizedURL: normalizedURL,
      duration: 0.5,
      sourceFilename: sourceURL.lastPathComponent
    )

    let store = TestStore(initialState: Self.makeState(saveHistory: false)) {
      FilesFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.importedMediaPreparation.isSupported = { _ in true }
      $0.importedMediaPreparation.prepare = { _ in prepared }
      $0.transcription.transcribe = { _, _, _, _, _ in "offline transcript" }
      $0.pasteboard.copy = { _ in }
    }

    await store.send(.enqueueFiles([sourceURL])) {
      $0.items.append(.init(id: itemID, sourceURL: sourceURL))
      $0.selectedItemID = itemID
    }

    await store.receive(.processNext) {
      $0.items[id: itemID]?.status = .preparing
    }
    await store.receive(.processingSucceeded(itemID, "offline transcript", 0.5)) {
      $0.items[id: itemID]?.status = .completed
      $0.items[id: itemID]?.transcript = "offline transcript"
      $0.items[id: itemID]?.duration = 0.5
    }
    await store.receive(.processNext)

    XCTAssertFalse(FileManager.default.fileExists(atPath: normalizedURL.path))
  }

  func testHistoryEnabledSavesImportedTranscriptWithFilenameSource() async throws {
    let sourceURL = URL(fileURLWithPath: "/tmp/history-enabled.mp4")
    let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let normalizedURL = try Self.makeTemporaryAudioFile(name: "history-enabled-normalized")
    let prepared = PreparedImportedMedia(
      normalizedURL: normalizedURL,
      duration: 0.75,
      sourceFilename: sourceURL.lastPathComponent
    )

    let savedSourceName = LockIsolated<String?>(nil)
    let savedTranscript = Transcript(
      timestamp: Date(timeIntervalSince1970: 123),
      text: "saved transcript",
      audioPath: normalizedURL,
      duration: 0.75,
      sourceAppBundleID: nil,
      sourceAppName: sourceURL.lastPathComponent
    )
    let store = TestStore(initialState: Self.makeState(saveHistory: true)) {
      FilesFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.importedMediaPreparation.isSupported = { _ in true }
      $0.importedMediaPreparation.prepare = { _ in prepared }
      $0.transcription.transcribe = { _, _, _, _, _ in "saved transcript" }
      $0.transcriptPersistence.save = { result, audioURL, duration, sourceBundleID, sourceName in
        savedSourceName.setValue(sourceName)
        XCTAssertEqual(result, "saved transcript")
        XCTAssertEqual(audioURL, normalizedURL)
        XCTAssertEqual(duration, 0.75, accuracy: 0.001)
        XCTAssertNil(sourceBundleID)
        XCTAssertEqual(sourceName, sourceURL.lastPathComponent)
        return savedTranscript
      }
      $0.transcriptPersistence.deleteAudio = { _ in }
      $0.pasteboard.copy = { _ in }
    }

    await store.send(.enqueueFiles([sourceURL])) {
      $0.items.append(.init(id: itemID, sourceURL: sourceURL))
      $0.selectedItemID = itemID
    }

    await store.receive(.processNext) {
      $0.$transcriptionHistory.withLock { history in
        history.history.insert(savedTranscript, at: 0)
      }
      $0.items[id: itemID]?.status = .preparing
    }
    await store.receive(.processingSucceeded(itemID, "saved transcript", 0.75)) {
      $0.items[id: itemID]?.status = .completed
      $0.items[id: itemID]?.transcript = "saved transcript"
      $0.items[id: itemID]?.duration = 0.75
    }
    await store.receive(.processNext)

    XCTAssertEqual(savedSourceName.value, sourceURL.lastPathComponent)
    XCTAssertEqual(store.state.transcriptionHistory.history.first?.sourceAppName, sourceURL.lastPathComponent)
  }

  func testShowFilesRouteDoesNotDependOnPermissionState() async throws {
    let reducer = AppFeature()
    var state = AppFeature.State()

    _ = reducer.reduce(
      into: &state,
      action: .permissionsUpdated(
        mic: PermissionStatus.denied,
        acc: PermissionStatus.denied,
        input: PermissionStatus.denied
      )
    )
    _ = reducer.reduce(into: &state, action: .showFiles)

    XCTAssertEqual(state.microphonePermission, .denied)
    XCTAssertEqual(state.accessibilityPermission, .denied)
    XCTAssertEqual(state.inputMonitoringPermission, .denied)
    XCTAssertEqual(state.activeTab, .files)
  }

  func testImportedMediaValidationAndNormalization() async throws {
    XCTAssertTrue(ImportedMediaSupport.isSupported(URL(fileURLWithPath: "/tmp/test.mp3")))
    XCTAssertTrue(ImportedMediaSupport.isSupported(URL(fileURLWithPath: "/tmp/test.mov")))
    XCTAssertFalse(ImportedMediaSupport.isSupported(URL(fileURLWithPath: "/tmp/test.txt")))

    let inputURL = try Self.makeTemporaryAudioFile(name: "normalization-input", sampleRate: 44_100, channels: 2)
    defer { try? FileManager.default.removeItem(at: inputURL) }

    let prepared = try await ImportedMediaPreparationClient.liveValue.prepare(inputURL)
    defer {
      prepared.cleanupIntermediates()
      try? FileManager.default.removeItem(at: prepared.normalizedURL)
    }

    XCTAssertEqual(prepared.normalizedURL.pathExtension, "wav")
    XCTAssertEqual(prepared.sourceFilename, inputURL.lastPathComponent)
    XCTAssertEqual(prepared.duration, 0.5, accuracy: 0.05)

    let normalizedFile = try AVAudioFile(forReading: prepared.normalizedURL)
    XCTAssertEqual(normalizedFile.processingFormat.sampleRate, 16_000, accuracy: 1)
    XCTAssertEqual(normalizedFile.processingFormat.channelCount, 1)
  }

  private static func makeState(saveHistory: Bool) -> FilesFeature.State {
    var settings = EuclidSettings()
    settings.saveTranscriptionHistory = saveHistory
    return FilesFeature.State(
      euclidSettings: Shared(value: settings),
      transcriptionHistory: Shared(value: .init())
    )
  }

  private static func makeTemporaryAudioFile(
    name: String,
    sampleRate: Double = 16_000,
    channels: AVAudioChannelCount = 1
  ) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(name)-\(UUID().uuidString)")
      .appendingPathExtension("wav")

    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: sampleRate,
      channels: channels,
      interleaved: true
    )!
    let frameCount = AVAudioFrameCount(sampleRate * 0.5)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    if format.isInterleaved {
      let audioBuffer = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)[0]
      let samples = audioBuffer.mData!.assumingMemoryBound(to: Float.self)
      for frame in 0..<Int(frameCount) {
        let sample = sin(Float(frame) / 20)
        for channelIndex in 0..<Int(channels) {
          samples[(frame * Int(channels)) + channelIndex] = sample
        }
      }
    } else {
      for channelIndex in 0..<Int(channels) {
        let channel = buffer.floatChannelData![channelIndex]
        for frame in 0..<Int(frameCount) {
          channel[frame] = sin(Float(frame) / 20)
        }
      }
    }

    let file = try AVAudioFile(
      forWriting: url,
      settings: format.settings,
      commonFormat: format.commonFormat,
      interleaved: format.isInterleaved
    )
    try file.write(from: buffer)
    return url
  }
}
