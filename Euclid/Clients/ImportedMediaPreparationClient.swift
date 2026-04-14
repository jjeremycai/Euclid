@preconcurrency import AVFoundation
import Dependencies
import DependenciesMacros
import EuclidCore
import Foundation
import UniformTypeIdentifiers

private let filesLogger = EuclidLog.files

enum ImportedMediaKind: String, Sendable {
  case audio
  case video
}

enum ImportedMediaSupport {
  static let supportedExtensions = ["mp3", "wav", "m4a", "flac", "mp4", "mov", "m4v"]

  static let openPanelContentTypes: [UTType] = {
    let types = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
    return types.isEmpty ? [.audio, .movie] : types
  }()

  static func kind(for url: URL) -> ImportedMediaKind? {
    switch url.pathExtension.lowercased() {
    case "mp3", "wav", "m4a", "flac":
      return .audio
    case "mp4", "mov", "m4v":
      return .video
    default:
      return nil
    }
  }

  static func isSupported(_ url: URL) -> Bool {
    kind(for: url) != nil
  }

  static var supportedExtensionsLabel: String {
    supportedExtensions.joined(separator: ", ")
  }
}

struct PreparedImportedMedia: Sendable {
  let normalizedURL: URL
  let duration: TimeInterval
  let sourceFilename: String

  private let cleanupURLs: [URL]

  init(normalizedURL: URL, duration: TimeInterval, sourceFilename: String, cleanupURLs: [URL] = []) {
    self.normalizedURL = normalizedURL
    self.duration = duration
    self.sourceFilename = sourceFilename
    self.cleanupURLs = cleanupURLs
  }

  func cleanupIntermediates() {
    for url in cleanupURLs {
      try? FileManager.default.removeItem(at: url)
    }
  }
}

private enum ImportedMediaPreparationError: LocalizedError {
  case unsupportedFileType
  case noAudioTrack
  case invalidDuration
  case unableToCreateExportSession
  case exportFailed(String)
  case failedToCreateOutputFormat
  case failedToCreateConverter
  case failedToAllocateBuffer
  case conversionFailed

  var errorDescription: String? {
    switch self {
    case .unsupportedFileType:
      return "Unsupported file type. Use mp3, wav, m4a, flac, mp4, mov, or m4v."
    case .noAudioTrack:
      return "This file does not contain an audio track."
    case .invalidDuration:
      return "Unable to determine the file duration."
    case .unableToCreateExportSession:
      return "Unable to prepare the media file for transcription."
    case let .exportFailed(message):
      return message
    case .failedToCreateOutputFormat:
      return "Unable to create the normalized audio format."
    case .failedToCreateConverter:
      return "Unable to convert the selected file into a transcription format."
    case .failedToAllocateBuffer:
      return "Unable to allocate audio buffers for normalization."
    case .conversionFailed:
      return "The selected file could not be normalized for transcription."
    }
  }
}

@DependencyClient
struct ImportedMediaPreparationClient {
  var isSupported: @Sendable (URL) -> Bool = { _ in false }
  var prepare: @Sendable (URL) async throws -> PreparedImportedMedia
}

extension ImportedMediaPreparationClient: DependencyKey {
  static let liveValue: Self = {
    let live = ImportedMediaPreparationClientLive()
    return Self(
      isSupported: { ImportedMediaSupport.isSupported($0) },
      prepare: { try await live.prepare(url: $0) }
    )
  }()

  static let testValue = Self(
    isSupported: { _ in false },
    prepare: { _ in
      throw NSError(
        domain: "ImportedMediaPreparationClient",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Imported media preparation is not configured for tests."]
      )
    }
  )
}

extension DependencyValues {
  var importedMediaPreparation: ImportedMediaPreparationClient {
    get { self[ImportedMediaPreparationClient.self] }
    set { self[ImportedMediaPreparationClient.self] = newValue }
  }
}

private actor ImportedMediaPreparationClientLive {
  func prepare(url: URL) async throws -> PreparedImportedMedia {
    guard let kind = ImportedMediaSupport.kind(for: url) else {
      throw ImportedMediaPreparationError.unsupportedFileType
    }

    let asset = AVURLAsset(url: url)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
      throw ImportedMediaPreparationError.noAudioTrack
    }

    let duration = try await asset.load(.duration)
    let durationSeconds = CMTimeGetSeconds(duration)
    guard durationSeconds.isFinite else {
      throw ImportedMediaPreparationError.invalidDuration
    }

    var cleanupURLs: [URL] = []
    let sourceFilename = url.lastPathComponent

    let normalizedURL: URL
    switch kind {
    case .audio:
      do {
        normalizedURL = try normalizeAudio(at: url, sourceFilename: sourceFilename)
      } catch {
        let extractedURL = try await exportAudioTrack(from: asset, sourceFilename: sourceFilename)
        cleanupURLs.append(extractedURL)
        normalizedURL = try normalizeAudio(at: extractedURL, sourceFilename: sourceFilename)
      }
    case .video:
      let extractedURL = try await exportAudioTrack(from: asset, sourceFilename: sourceFilename)
      cleanupURLs.append(extractedURL)
      normalizedURL = try normalizeAudio(at: extractedURL, sourceFilename: sourceFilename)
    }

    filesLogger.notice(
      "Prepared imported media source=\(sourceFilename, privacy: .private) normalized=\(normalizedURL.lastPathComponent, privacy: .private)"
    )

    return PreparedImportedMedia(
      normalizedURL: normalizedURL,
      duration: durationSeconds,
      sourceFilename: sourceFilename,
      cleanupURLs: cleanupURLs
    )
  }

  private func exportAudioTrack(from asset: AVAsset, sourceFilename: String) async throws -> URL {
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
      throw ImportedMediaPreparationError.unableToCreateExportSession
    }

    let exportURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("euclid-import-\(UUID().uuidString)")
      .appendingPathExtension("m4a")

    exportSession.shouldOptimizeForNetworkUse = false

    do {
      try await exportSession.export(to: exportURL, as: .m4a)
      filesLogger.notice("Extracted audio for imported media source=\(sourceFilename, privacy: .private)")
      return exportURL
    } catch is CancellationError {
      throw ImportedMediaPreparationError.exportFailed("Audio extraction was cancelled.")
    } catch {
      throw ImportedMediaPreparationError.exportFailed(error.localizedDescription)
    }
  }

  private func normalizeAudio(at inputURL: URL, sourceFilename: String) throws -> URL {
    let inputFile = try AVAudioFile(forReading: inputURL)
    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16_000,
      channels: 1,
      interleaved: true
    ) else {
      throw ImportedMediaPreparationError.failedToCreateOutputFormat
    }
    guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: outputFormat) else {
      throw ImportedMediaPreparationError.failedToCreateConverter
    }
    converter.downmix = inputFile.processingFormat.channelCount != outputFormat.channelCount

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("euclid-import-\(UUID().uuidString)")
      .appendingPathExtension("wav")

    let outputFile = try AVAudioFile(
      forWriting: outputURL,
      settings: outputFormat.settings,
      commonFormat: outputFormat.commonFormat,
      interleaved: outputFormat.isInterleaved
    )

    let inputBufferCapacity: AVAudioFrameCount = 4_096
    let estimatedRatio = max(1, outputFormat.sampleRate / inputFile.processingFormat.sampleRate)
    let outputBufferCapacity = AVAudioFrameCount(max(4_096, (Double(inputBufferCapacity) * estimatedRatio).rounded(.up) + 1_024))

    guard
      let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: inputBufferCapacity),
      let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputBufferCapacity)
    else {
      throw ImportedMediaPreparationError.failedToAllocateBuffer
    }

    var reachedEndOfInput = false
    while true {
      if inputFile.framePosition < inputFile.length {
        inputBuffer.frameLength = 0
        try inputFile.read(into: inputBuffer, frameCount: inputBufferCapacity)
      } else {
        inputBuffer.frameLength = 0
        reachedEndOfInput = true
      }

      let hasInput = inputBuffer.frameLength > 0
      var hasProvidedInput = false

      conversionLoop: while true {
        outputBuffer.frameLength = 0
        var conversionError: NSError?

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
          guard hasInput else {
            outStatus.pointee = .endOfStream
            return nil
          }

          guard hasProvidedInput == false else {
            outStatus.pointee = .noDataNow
            return nil
          }

          hasProvidedInput = true
          outStatus.pointee = .haveData
          return inputBuffer
        }

        if let conversionError {
          throw conversionError
        }

        if outputBuffer.frameLength > 0 {
          try outputFile.write(from: outputBuffer)
        }

        switch status {
        case .haveData:
          continue
        case .inputRanDry:
          break conversionLoop
        case .endOfStream:
          reachedEndOfInput = true
          break conversionLoop
        case .error:
          throw ImportedMediaPreparationError.conversionFailed
        @unknown default:
          throw ImportedMediaPreparationError.conversionFailed
        }
      }

      if reachedEndOfInput {
        break
      }
    }

    filesLogger.notice(
      "Normalized imported media source=\(sourceFilename, privacy: .private) output=\(outputURL.lastPathComponent, privacy: .private)"
    )
    return outputURL
  }
}
