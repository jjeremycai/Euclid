//
//  TranscriptionClient.swift
//  Euclid
//
//  Created by Kit Langton on 1/24/25.
//

import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import EuclidCore
import WhisperKit

private let transcriptionLogger = EuclidLog.transcription
private let modelsLogger = EuclidLog.models
private let parakeetLogger = EuclidLog.parakeet

/// A client that coordinates WhisperKit and Parakeet model loading, then transcribes audio files using the loaded backend.
/// Exposes progress callbacks to report overall download-and-load percentage and transcription progress.
@DependencyClient
struct TranscriptionClient {
  /// Transcribes an audio file at the specified `URL` using the named `model`.
  /// Reports transcription progress via `progressCallback`.
  var transcribe: @Sendable (URL, String, DecodingOptions, [VocabularyTerm], @escaping (Progress) -> Void) async throws -> String

  /// Ensures a model is downloaded (if missing) and loaded into memory, reporting progress via `progressCallback`.
  var downloadModel: @Sendable (String, @escaping (Progress) -> Void) async throws -> Void

  /// Deletes a model from disk if it exists
  var deleteModel: @Sendable (String) async throws -> Void

  /// Checks if a named model is already downloaded on this system.
  var isModelDownloaded: @Sendable (String) async -> Bool = { _ in false }

  /// Loads a previously downloaded model into memory so first transcription is not cold-start bound.
  var prewarmModel: @Sendable (String) async -> Void = { _ in }

  /// Fetches a recommended set of models for the user's hardware from Hugging Face's `argmaxinc/whisperkit-coreml`.
  var getRecommendedModels: @Sendable () async throws -> ModelSupport

  /// Lists all model variants found in `argmaxinc/whisperkit-coreml`.
  var getAvailableModels: @Sendable () async throws -> [String]
}

extension TranscriptionClient: DependencyKey {
  static var liveValue: Self {
    let live = TranscriptionClientLive()
    return Self(
      transcribe: { try await live.transcribe(url: $0, model: $1, options: $2, vocabularyTerms: $3, progressCallback: $4) },
      downloadModel: { try await live.downloadAndLoadModel(variant: $0, progressCallback: $1) },
      deleteModel: { try await live.deleteModel(variant: $0) },
      isModelDownloaded: { await live.isModelDownloaded($0) },
      prewarmModel: { await live.prewarmModel($0) },
      getRecommendedModels: { await live.getRecommendedModels() },
      getAvailableModels: { try await live.getAvailableModels() }
    )
  }
}

extension DependencyValues {
  var transcription: TranscriptionClient {
    get { self[TranscriptionClient.self] }
    set { self[TranscriptionClient.self] = newValue }
  }
}

/// An `actor` that manages transcription backends by downloading model assets,
/// loading them into memory, and then performing transcriptions.

actor TranscriptionClientLive {
  // MARK: - Stored Properties

  /// The current in-memory `WhisperKit` instance, if any.
  private var whisperKit: WhisperKit?

  /// The name of the currently loaded model, if any.
  private var currentModelName: String?
  private var parakeet: ParakeetClient = ParakeetClient()

  /// The base folder under which we store model data (e.g., ~/Library/Application Support/...).
  private lazy var modelsBaseFolder: URL = {
    do {
      return try URL.euclidModelsDirectory
    } catch {
      fatalError("Could not create Application Support folder: \(error)")
    }
  }()

  // MARK: - Public Methods

  /// Ensures the given `variant` model is downloaded and loaded, reporting
  /// overall progress (0%–50% for downloading, 50%–100% for loading).
  func downloadAndLoadModel(variant: String, progressCallback: @escaping (Progress) -> Void) async throws {
    let backend = await resolvedBackend(for: variant)
    if backend.modelName.isEmpty {
      throw NSError(
        domain: "TranscriptionClient",
        code: -3,
        userInfo: [
          NSLocalizedDescriptionKey: "Cannot download model: Empty model name",
        ]
      )
    }

    try await loadModel(backend: backend, progressCallback: progressCallback)
  }

  /// Deletes a model from disk if it exists
  func deleteModel(variant: String) async throws {
    try await deleteModel(backend: backend(for: variant))
  }

  /// Returns `true` if the model is already downloaded to the local folder.
  /// Performs a thorough check to ensure the model files are actually present and usable.
  func isModelDownloaded(_ modelName: String) async -> Bool {
    switch backend(for: modelName) {
    case .parakeet(let variant):
      let available = await parakeet.isModelAvailable(variant.identifier)
      parakeetLogger.debug("Parakeet available? \(available)")
      return available
    case .whisperKit:
      let modelFolderPath = modelPath(for: modelName).path
      let fileManager = FileManager.default

      // First, check if the basic model directory exists
      guard fileManager.fileExists(atPath: modelFolderPath) else {
        // Don't print logs that would spam the console
        return false
      }

      do {
        // Check if the directory has actual model files in it
        let contents = try fileManager.contentsOfDirectory(atPath: modelFolderPath)

        // Model should have multiple files and certain key components
        guard !contents.isEmpty else {
          return false
        }

        // Check for specific model structure - need both tokenizer and model files
        let hasModelFiles = contents.contains { $0.hasSuffix(".mlmodelc") || $0.contains("model") }
        let tokenizerFolderPath = tokenizerPath(for: modelName).path
        let hasTokenizer = fileManager.fileExists(atPath: tokenizerFolderPath)

        // Both conditions must be true for a model to be considered downloaded
        return hasModelFiles && hasTokenizer
      } catch {
        return false
      }
    }
  }

  /// Returns a list of recommended models based on current device hardware.
  func getRecommendedModels() async -> ModelSupport {
    await WhisperKit.recommendedRemoteModels()
  }

  /// Lists all model variants available in the `argmaxinc/whisperkit-coreml` repository.
  func getAvailableModels() async throws -> [String] {
    var names = try await WhisperKit.fetchAvailableModels()
    #if canImport(FluidAudio)
    for identifier in ParakeetModel.allCases.reversed().map(\.identifier) {
      if !names.contains(identifier) { names.insert(identifier, at: 0) }
    }
    #endif
    return names
  }

  func prewarmModel(_ model: String) async {
    guard !model.isEmpty else { return }
    guard await isModelDownloaded(model) else {
      transcriptionLogger.debug("Skipping model prewarm because \(model) is not downloaded")
      return
    }

    do {
      transcriptionLogger.notice("Prewarming model=\(model)")
      try await downloadAndLoadModel(variant: model) { _ in }
      transcriptionLogger.notice("Finished prewarming model=\(model)")
    } catch {
      transcriptionLogger.error("Model prewarm failed for \(model): \(error.localizedDescription)")
    }
  }

  /// Transcribes the audio file at `url` using a `model` name.
  /// If the model is not yet loaded (or if it differs from the current model), it is downloaded and loaded first.
  /// Transcription progress can be monitored via `progressCallback`.
  func transcribe(
    url: URL,
    model: String,
    options: DecodingOptions,
    vocabularyTerms: [VocabularyTerm],
    progressCallback: @escaping (Progress) -> Void
  ) async throws -> String {
    let startAll = Date()
    let backend = await resolvedBackend(for: model)
    if backend.modelName.isEmpty {
      throw NSError(
        domain: "TranscriptionClient",
        code: -3,
        userInfo: [
          NSLocalizedDescriptionKey: "Cannot download model: Empty model name",
        ]
      )
    }

    switch backend {
    case .parakeet(let variant):
      transcriptionLogger.notice("Transcribing with \(backend.logLabel) model=\(variant.identifier) file=\(url.lastPathComponent)")
      let startLoad = Date()
      try await loadModel(backend: backend, progressCallback: progressCallback)
      transcriptionLogger.info("\(backend.logLabel) ensureLoaded took \(String(format: "%.2f", Date().timeIntervalSince(startLoad)))s")

      let preparedClip = try ParakeetClipPreparer.ensureMinimumDuration(url: url, logger: parakeetLogger)
      defer { preparedClip.cleanup() }

      let startTx = Date()
      if !backend.supportsVocabularyPrompt, !enabledVocabularyTerms(from: vocabularyTerms).isEmpty {
        transcriptionLogger.debug("Ignoring vocabulary bias for \(backend.logLabel) model=\(variant.identifier)")
      }
      let text = try await parakeet.transcribe(preparedClip.url)
      transcriptionLogger.info("\(backend.logLabel) transcription took \(String(format: "%.2f", Date().timeIntervalSince(startTx)))s")
      transcriptionLogger.info("\(backend.logLabel) request total elapsed \(String(format: "%.2f", Date().timeIntervalSince(startAll)))s")
      return text

    case .whisperKit(let modelName):
      if whisperKit == nil || modelName != currentModelName {
        unloadCurrentModel()
        let startLoad = Date()
        try await loadModel(backend: backend, progressCallback: progressCallback)
        let loadDuration = Date().timeIntervalSince(startLoad)
        transcriptionLogger.info("\(backend.logLabel) ensureLoaded model=\(modelName) took \(String(format: "%.2f", loadDuration))s")
      }

      guard let whisperKit = whisperKit else {
        throw NSError(
          domain: "TranscriptionClient",
          code: -1,
          userInfo: [
            NSLocalizedDescriptionKey: "Failed to initialize WhisperKit for model: \(modelName)",
          ]
        )
      }

      transcriptionLogger.notice("Transcribing with \(backend.logLabel) model=\(modelName) file=\(url.lastPathComponent)")
      let startTx = Date()
      var decodeOptions = options
      let enabledVocabularyTermCount = enabledVocabularyTerms(from: vocabularyTerms).count
      if backend.supportsVocabularyPrompt, let promptTokens = vocabularyPromptTokens(from: vocabularyTerms, tokenizer: whisperKit.tokenizer) {
        decodeOptions.promptTokens = promptTokens
        transcriptionLogger.info("Applied \(enabledVocabularyTermCount) vocabulary term(s) to Whisper prompt")
      }

      let results = try await whisperKit.transcribe(audioPath: url.path, decodeOptions: decodeOptions)
      transcriptionLogger.info("\(backend.logLabel) transcription took \(String(format: "%.2f", Date().timeIntervalSince(startTx)))s")
      transcriptionLogger.info("\(backend.logLabel) request total elapsed \(String(format: "%.2f", Date().timeIntervalSince(startAll)))s")
      return results.map(\.text).joined(separator: " ")
    }
  }

  // MARK: - Private Helpers

  /// Resolve wildcard patterns (e.g. "distil*large-v3") to a concrete model name.
  /// Preference: downloaded > non-turbo > any match.
  private func resolveVariant(_ variant: String) async -> String {
    guard variant.contains("*") || variant.contains("?") else { return variant }

    let names: [String]
    do { names = try await WhisperKit.fetchAvailableModels() } catch { return variant }

    // Build tuple array with download status for matching models
    var models: [(name: String, isDownloaded: Bool)] = []
    for name in names where ModelPatternMatcher.matches(variant, name) {
      models.append((name, await isModelDownloaded(name)))
    }

    return ModelPatternMatcher.resolvePattern(variant, from: models) ?? variant
  }

  private func backend(for modelName: String) -> TranscriptionBackend {
    TranscriptionBackend(modelName: modelName)
  }

  private func resolvedBackend(for modelName: String) async -> TranscriptionBackend {
    TranscriptionBackend(modelName: await resolveVariant(modelName))
  }

  private func loadModel(
    backend: TranscriptionBackend,
    progressCallback: @escaping (Progress) -> Void
  ) async throws {
    switch backend {
    case .parakeet(let variant):
      try await parakeet.ensureLoaded(modelName: variant.identifier, progress: progressCallback)
      currentModelName = variant.identifier
    case .whisperKit(let modelName):
      let overallProgress = Progress(totalUnitCount: 100)
      overallProgress.completedUnitCount = 0
      progressCallback(overallProgress)

      modelsLogger.info("Preparing model download and load for \(backend.logLabel) model=\(modelName)")

      if !(await isModelDownloaded(modelName)) {
        try await downloadModelIfNeeded(variant: modelName) { downloadProgress in
          let fraction = downloadProgress.fractionCompleted * 0.5
          overallProgress.completedUnitCount = Int64(fraction * 100)
          progressCallback(overallProgress)
        }
      } else {
        overallProgress.completedUnitCount = 50
        progressCallback(overallProgress)
      }

      try await loadWhisperKitModel(modelName) { loadingProgress in
        let fraction = 0.5 + (loadingProgress.fractionCompleted * 0.5)
        overallProgress.completedUnitCount = Int64(fraction * 100)
        progressCallback(overallProgress)
      }

      overallProgress.completedUnitCount = 100
      progressCallback(overallProgress)
    }
  }

  private func deleteModel(backend: TranscriptionBackend) async throws {
    switch backend {
    case .parakeet(let variant):
      try await parakeet.deleteCaches(modelName: variant.identifier)
      if currentModelName == variant.identifier { unloadCurrentModel() }
    case .whisperKit(let modelName):
      let modelFolder = modelPath(for: modelName)

      guard FileManager.default.fileExists(atPath: modelFolder.path) else {
        return
      }

      if currentModelName == modelName {
        unloadCurrentModel()
      }

      try FileManager.default.removeItem(at: modelFolder)
      modelsLogger.info("Deleted model \(modelName)")
    }
  }

  private func enabledVocabularyTerms(from vocabularyTerms: [VocabularyTerm]) -> [String] {
    vocabularyTerms
      .filter(\.isEnabled)
      .map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func vocabularyPromptTokens(
    from vocabularyTerms: [VocabularyTerm],
    tokenizer: WhisperTokenizer?
  ) -> [Int]? {
    guard let tokenizer else { return nil }
    let terms = Array(NSOrderedSet(array: enabledVocabularyTerms(from: vocabularyTerms))) as? [String] ?? []
    guard !terms.isEmpty else { return nil }
    return tokenizer
      .encode(text: " " + terms.joined(separator: ", "))
      .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
  }

  /// Creates or returns the local folder (on disk) for a given `variant` model.
  private func modelPath(for variant: String) -> URL {
    // Remove any possible path traversal or invalid characters from variant name
    let sanitizedVariant = variant.components(separatedBy: CharacterSet(charactersIn: "./\\")).joined(separator: "_")

    return modelsBaseFolder
      .appendingPathComponent("argmaxinc")
      .appendingPathComponent("whisperkit-coreml")
      .appendingPathComponent(sanitizedVariant, isDirectory: true)
  }

  /// Creates or returns the local folder for the tokenizer files of a given `variant`.
  private func tokenizerPath(for variant: String) -> URL {
    modelPath(for: variant).appendingPathComponent("tokenizer", isDirectory: true)
  }

  // Unloads any currently loaded model (clears `whisperKit` and `currentModelName`).
  private func unloadCurrentModel() {
    whisperKit = nil
    currentModelName = nil
  }

  /// Downloads the model to a temporary folder (if it isn't already on disk),
  /// then moves it into its final folder in `modelsBaseFolder`.
  private func downloadModelIfNeeded(
    variant: String,
    progressCallback: @escaping (Progress) -> Void
  ) async throws {
    let modelFolder = modelPath(for: variant)

    // If the model folder exists but isn't a complete model, clean it up
    let isDownloaded = await isModelDownloaded(variant)
    if FileManager.default.fileExists(atPath: modelFolder.path), !isDownloaded {
      try FileManager.default.removeItem(at: modelFolder)
    }

    // If model is already fully downloaded, we're done
    if isDownloaded {
      return
    }

    modelsLogger.info("Downloading model \(variant)")

    // Create parent directories
    let parentDir = modelFolder.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

    do {
      // Download directly using the exact variant name provided
      // WhisperKit 0.15.0 changed downloader params: passing
      // "argmaxinc/whisperkit-coreml" to a parameter interpreted as a host
      // yields NSURLErrorCannotFindHost in production builds that need
      // to fetch models for the first time. Let WhisperKit use its
      // default repo/host (Hugging Face) by omitting the repo/host arg.
      let tempFolder = try await WhisperKit.download(
        variant: variant,
        downloadBase: nil,
        useBackgroundSession: false,
        progressCallback: { progress in
          progressCallback(progress)
        }
      )

      // Ensure target folder exists
      try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

      // Move the downloaded snapshot to the final location
      try moveContents(of: tempFolder, to: modelFolder)

      modelsLogger.info("Downloaded model to \(modelFolder.path)")
    } catch {
      // Clean up any partial download if an error occurred
      FileManager.default.removeItemIfExists(at: modelFolder)

      // Rethrow the original error
      modelsLogger.error("Error downloading model \(variant): \(error.localizedDescription)")
      throw error
    }
  }

  /// Loads a local model folder via `WhisperKitConfig`, optionally reporting load progress.
  private func loadWhisperKitModel(
    _ modelName: String,
    progressCallback: @escaping (Progress) -> Void
  ) async throws {
    let loadingProgress = Progress(totalUnitCount: 100)
    loadingProgress.completedUnitCount = 0
    progressCallback(loadingProgress)

    let modelFolder = modelPath(for: modelName)
    let tokenizerFolder = tokenizerPath(for: modelName)

    // Use WhisperKit's config to load the model
    let config = WhisperKitConfig(
      model: modelName,
      modelFolder: modelFolder.path,
      tokenizerFolder: tokenizerFolder,
      // verbose: true,
      // logLevel: .debug,
      prewarm: false,
      load: true
    )

    // The initializer automatically calls `loadModels`.
    whisperKit = try await WhisperKit(config)
    currentModelName = modelName

    // Finalize load progress
    loadingProgress.completedUnitCount = 100
    progressCallback(loadingProgress)

    modelsLogger.info("Loaded WhisperKit model \(modelName)")
  }

  /// Moves all items from `sourceFolder` into `destFolder` (shallow move of directory contents).
  private func moveContents(of sourceFolder: URL, to destFolder: URL) throws {
    let fileManager = FileManager.default
    let items = try fileManager.contentsOfDirectory(atPath: sourceFolder.path)
    for item in items {
      let src = sourceFolder.appendingPathComponent(item)
      let dst = destFolder.appendingPathComponent(item)
      try fileManager.moveItem(at: src, to: dst)
    }
  }
}
