@preconcurrency import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation

private let historyLogger = EuclidLog.history

@DependencyClient
public struct AudioPlaybackClient: Sendable {
  public var play: @Sendable (_ url: URL) async throws -> AsyncStream<Void> = { _ in
    AsyncStream { continuation in
      continuation.finish()
    }
  }

  public var stop: @Sendable () async -> Void = {}
}

extension AudioPlaybackClient: DependencyKey {
  public static let liveValue: Self = {
    let live = AudioPlaybackClientLive()
    return Self(
      play: { url in try await live.play(url: url) },
      stop: { await live.stop() }
    )
  }()

  public static let testValue = Self(
    play: { _ in
      AsyncStream { continuation in
        continuation.finish()
      }
    },
    stop: {}
  )
}

public extension DependencyValues {
  var audioPlayback: AudioPlaybackClient {
    get { self[AudioPlaybackClient.self] }
    set { self[AudioPlaybackClient.self] = newValue }
  }
}

actor AudioPlaybackClientLive {
  private var controller: AudioPlaybackController?
  private var playbackContinuation: AsyncStream<Void>.Continuation?

  func play(url: URL) throws -> AsyncStream<Void> {
    stop()

    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let controller = AudioPlaybackController()
    controller.onPlaybackFinished = { [weak self] in
      Task { await self?.finishPlayback() }
    }

    _ = try controller.play(url: url)
    self.controller = controller
    playbackContinuation = continuation

    historyLogger.debug("Started transcript playback for \(url.path, privacy: .private)")
    return stream
  }

  func stop() {
    controller?.stop()
    controller = nil
    playbackContinuation?.finish()
    playbackContinuation = nil
  }

  private func finishPlayback() {
    controller = nil
    playbackContinuation?.finish()
    playbackContinuation = nil
    historyLogger.debug("Transcript playback finished")
  }
}

final class AudioPlaybackController: NSObject, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?
  var onPlaybackFinished: (() -> Void)?

  func play(url: URL) throws -> AVAudioPlayer {
    let player = try AVAudioPlayer(contentsOf: url)
    player.delegate = self
    player.play()
    self.player = player
    return player
  }

  func stop() {
    player?.stop()
    player = nil
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    self.player = nil
    onPlaybackFinished?()
  }
}
