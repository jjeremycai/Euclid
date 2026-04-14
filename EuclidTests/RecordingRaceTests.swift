import AppKit
import ComposableArchitecture
import EuclidCore
import Foundation
import XCTest

@testable import Euclid

@MainActor
final class RecordingRaceTests: XCTestCase {
  func testNewRecordingCancelsPendingDiscardCleanup() async throws {
    let now = Date(timeIntervalSince1970: 1_234)
    let recordingHotKey = HotKey(key: nil, modifiers: [.option])
    let stopURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("discard-cleanup-\(UUID().uuidString).wav")
    let created = FileManager.default.createFile(
      atPath: stopURL.path,
      contents: Data("test".utf8)
    )
    XCTAssertTrue(created)
    defer { try? FileManager.default.removeItem(at: stopURL) }

    let probe = RecordingProbe(stopURL: stopURL)
    var recording = RecordingClient()
    recording.startRecording = {
      await probe.recordStart()
    }
    recording.stopRecording = {
      await probe.beginStop()
    }
    let sleepManagement = SleepManagementClient(
      preventSleep: { _ in },
      allowSleep: {}
    )
    let soundEffects = SoundEffectsClient(
      play: { _ in },
      stop: { _ in },
      stopAll: {},
      preloadSounds: {},
      setEnabled: { _ in }
    )

    let store = Store(initialState: Self.makeState()) {
      TranscriptionFeature()
    } withDependencies: {
      $0.date = .constant(now)
      $0.recording = recording
      $0.sleepManagement = sleepManagement
      $0.soundEffects = soundEffects
    }

    await store.send(.startRecording(recordingHotKey)).finish()
    let discardTask = store.send(.discard)

    await probe.waitForPendingStop()

    await store.send(.startRecording(recordingHotKey)).finish()

    await probe.resumePendingStop()
    await discardTask.finish()

    let counts = await probe.counts()
    XCTAssertEqual(counts.startCalls, 2)
    XCTAssertEqual(counts.stopCalls, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: stopURL.path))
    XCTAssertTrue(store.withState(\.isRecording))
  }

  func testStopGuardIgnoresOnlyStaleSessions() {
    let currentSessionID = UUID()

    XCTAssertFalse(
      RecordingClientLive.shouldIgnoreStopRequest(
        snapshotSessionID: currentSessionID,
        currentSessionID: currentSessionID
      )
    )
    XCTAssertFalse(
      RecordingClientLive.shouldIgnoreStopRequest(
        snapshotSessionID: nil,
        currentSessionID: currentSessionID
      )
    )
    XCTAssertTrue(
      RecordingClientLive.shouldIgnoreStopRequest(
        snapshotSessionID: currentSessionID,
        currentSessionID: UUID()
      )
    )
  }

  private static func makeState() -> TranscriptionFeature.State {
    TranscriptionFeature.State(
      euclidSettings: Shared(value: .init()),
      isRemappingScratchpadFocused: false,
      modelBootstrapState: Shared(value: .init(isModelReady: true)),
      transcriptionHistory: Shared(value: .init())
    )
  }
}

private actor RecordingProbe {
  private let stopURL: URL
  private var startCalls = 0
  private var stopCalls = 0
  private var stopContinuation: CheckedContinuation<URL, Never>?

  init(stopURL: URL) {
    self.stopURL = stopURL
  }

  func recordStart() {
    startCalls += 1
  }

  func beginStop() async -> URL {
    stopCalls += 1
    return await withCheckedContinuation { continuation in
      stopContinuation = continuation
    }
  }

  func waitForPendingStop() async {
    while stopContinuation == nil {
      await Task.yield()
    }
  }

  func resumePendingStop() {
    stopContinuation?.resume(returning: stopURL)
    stopContinuation = nil
  }

  func counts() -> (startCalls: Int, stopCalls: Int) {
    (startCalls, stopCalls)
  }
}
