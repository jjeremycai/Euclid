import ComposableArchitecture
import EuclidCore
import Foundation
import IdentifiedCollections
import Inject
import SwiftUI
import UniformTypeIdentifiers
import WhisperKit

private let filesFeatureLogger = EuclidLog.files

@Reducer
struct FilesFeature {
  @ObservableState
  struct State: Equatable {
    struct QueueItem: Equatable, Identifiable {
      enum Status: Equatable {
        case queued
        case preparing
        case transcribing(Double)
        case completed
        case failed(String)
      }

      let id: UUID
      let sourceURL: URL
      let displayName: String
      var status: Status
      var transcript: String
      var duration: TimeInterval?

      init(
        id: UUID = UUID(),
        sourceURL: URL,
        displayName: String? = nil,
        status: Status = .queued,
        transcript: String = "",
        duration: TimeInterval? = nil
      ) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName ?? sourceURL.lastPathComponent
        self.status = status
        self.transcript = transcript
        self.duration = duration
      }

      var isActivelyProcessing: Bool {
        switch status {
        case .preparing, .transcribing:
          true
        case .queued, .completed, .failed:
          false
        }
      }
    }

    @Shared(.euclidSettings) var euclidSettings: EuclidSettings
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory

    var items: IdentifiedArrayOf<QueueItem> = []
    var selectedItemID: QueueItem.ID?
  }

  enum Action: Equatable {
    case addFilesButtonTapped
    case filesPicked([URL]?)
    case filesDropped([URL])
    case enqueueFiles([URL])
    case selectItem(UUID?)
    case copyTranscript(UUID)
    case processNext
    case processingProgress(UUID, Double)
    case processingSucceeded(UUID, String, TimeInterval?)
    case processingFailed(UUID, String)
  }

  @Dependency(\.importedMediaPicker) var importedMediaPicker
  @Dependency(\.importedMediaPreparation) var importedMediaPreparation
  @Dependency(\.transcription) var transcription
  @Dependency(\.pasteboard) var pasteboard
  @Dependency(\.transcriptPersistence) var transcriptPersistence
  @Dependency(\.uuid) var uuid

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .addFilesButtonTapped:
        return .run { send in
          let urls = await importedMediaPicker.pickFiles()
          await send(.filesPicked(urls))
        }

      case let .filesPicked(urls):
        guard let urls, !urls.isEmpty else { return .none }
        return .send(.enqueueFiles(urls))

      case let .filesDropped(urls):
        guard !urls.isEmpty else { return .none }
        return .send(.enqueueFiles(urls))

      case let .enqueueFiles(urls):
        guard !urls.isEmpty else { return .none }

        var firstAddedID: UUID?
        for url in urls {
          let isSupported = importedMediaPreparation.isSupported(url)
          let item = State.QueueItem(
            id: uuid(),
            sourceURL: url,
            status: isSupported
              ? .queued
              : .failed("Unsupported file type. Use \(ImportedMediaSupport.supportedExtensionsLabel).")
          )
          if firstAddedID == nil {
            firstAddedID = item.id
          }
          state.items.append(item)
        }

        if state.selectedItemID == nil {
          state.selectedItemID = firstAddedID
        }

        return shouldProcessNext(from: state) ? .send(.processNext) : .none

      case let .selectItem(id):
        state.selectedItemID = id
        return .none

      case let .copyTranscript(id):
        guard let item = state.items[id: id], !item.transcript.isEmpty else {
          return .none
        }
        return .run { _ in
          await pasteboard.copy(item.transcript)
        }

      case .processNext:
        guard shouldProcessNext(from: state) else { return .none }
        guard let nextItem = state.items.first(where: { item in
          if case .queued = item.status { return true }
          return false
        }) else {
          return .none
        }

        state.items[id: nextItem.id]?.status = .preparing
        if state.selectedItemID == nil {
          state.selectedItemID = nextItem.id
        }

        let sourceURL = nextItem.sourceURL
        let itemID = nextItem.id
        let euclidSettings = state.euclidSettings
        let transcriptionHistory = state.$transcriptionHistory

        return .run { [transcription, transcriptPersistence, importedMediaPreparation] send in
          var preparedMedia: PreparedImportedMedia?

          do {
            preparedMedia = try await importedMediaPreparation.prepare(sourceURL)
            guard let preparedMedia else { return }

            let decodeOptions = DecodingOptions(
              language: euclidSettings.outputLanguage,
              detectLanguage: euclidSettings.outputLanguage == nil,
              chunkingStrategy: .vad
            )

            let rawTranscript = try await transcription.transcribe(
              preparedMedia.normalizedURL,
              euclidSettings.selectedModel,
              decodeOptions,
              euclidSettings.vocabularyTerms
            ) { progress in
              Task {
                await send(.processingProgress(itemID, progress.fractionCompleted))
              }
            }

            let processedTranscript = TranscriptTextProcessor.process(rawTranscript, settings: euclidSettings)

            try await saveImportedTranscriptIfNeeded(
              transcript: processedTranscript,
              preparedMedia: preparedMedia,
              settings: euclidSettings,
              transcriptionHistory: transcriptionHistory,
              transcriptPersistence: transcriptPersistence
            )
            preparedMedia.cleanupIntermediates()

            await send(.processingSucceeded(itemID, processedTranscript, preparedMedia.duration))
          } catch {
            filesFeatureLogger.error(
              "Imported transcription failed file=\(sourceURL.lastPathComponent, privacy: .private) error=\(error.localizedDescription, privacy: .private)"
            )

            preparedMedia?.cleanupIntermediates()
            if let preparedMedia {
              try? FileManager.default.removeItem(at: preparedMedia.normalizedURL)
            }

            await send(.processingFailed(itemID, error.localizedDescription))
          }
        }

      case let .processingProgress(id, progress):
        guard let item = state.items[id: id], item.isActivelyProcessing else {
          return .none
        }
        state.items[id: id]?.status = .transcribing(progress)
        return .none

      case let .processingSucceeded(id, transcript, duration):
        guard state.items[id: id] != nil else { return .none }
        state.items[id: id]?.status = .completed
        state.items[id: id]?.transcript = transcript
        state.items[id: id]?.duration = duration
        if state.selectedItemID == nil {
          state.selectedItemID = id
        }
        return .send(.processNext)

      case let .processingFailed(id, message):
        guard state.items[id: id] != nil else { return .none }
        state.items[id: id]?.status = .failed(message)
        if state.selectedItemID == nil {
          state.selectedItemID = id
        }
        return .send(.processNext)
      }
    }
  }
}

private extension FilesFeature {
  func shouldProcessNext(from state: State) -> Bool {
    !state.items.contains(where: \.isActivelyProcessing)
  }

  func saveImportedTranscriptIfNeeded(
    transcript: String,
    preparedMedia: PreparedImportedMedia,
    settings: EuclidSettings,
    transcriptionHistory: Shared<TranscriptionHistory>,
    transcriptPersistence: TranscriptPersistenceClient
  ) async throws {
    guard !transcript.isEmpty else {
      try? FileManager.default.removeItem(at: preparedMedia.normalizedURL)
      return
    }

    guard settings.saveTranscriptionHistory else {
      try? FileManager.default.removeItem(at: preparedMedia.normalizedURL)
      return
    }

    let savedTranscript = try await transcriptPersistence.save(
      transcript,
      preparedMedia.normalizedURL,
      preparedMedia.duration,
      nil,
      preparedMedia.sourceFilename
    )

    transcriptionHistory.withLock { history in
      history.history.insert(savedTranscript, at: 0)
    }

    if let maxEntries = settings.maxHistoryEntries, maxEntries > 0 {
      var removed: [Transcript] = []
      transcriptionHistory.withLock { history in
        while history.history.count > maxEntries {
          if let item = history.history.popLast() {
            removed.append(item)
          }
        }
      }

      for transcript in removed {
        try? await transcriptPersistence.deleteAudio(transcript)
      }
    }
  }
}

struct FilesView: View {
  @Bindable var store: StoreOf<FilesFeature>
  @ObserveInjection var inject
  @State private var isDropTargeted = false

  var body: some View {
    Group {
      if store.items.isEmpty {
        emptyState
      } else {
        content
      }
    }
    .toolbar {
      Button {
        store.send(.addFilesButtonTapped)
      } label: {
        Label("Add Files", systemImage: "plus")
      }
    }
    .background(backgroundDropZone)
    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
    .enableInjection()
  }

  private var emptyState: some View {
    VStack(spacing: 20) {
      Spacer()

      dropZone

      VStack(spacing: 6) {
        Text("Queue local audio or video files for transcription.")
          .font(.headline)
        Text("Supported formats: \(ImportedMediaSupport.supportedExtensionsLabel)")
          .foregroundStyle(.secondary)
      }

      Button {
        store.send(.addFilesButtonTapped)
      } label: {
        Label("Add Files", systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private var content: some View {
    HStack(spacing: 0) {
      List(selection: selectionBinding) {
        ForEach(store.items) { item in
          QueueItemRow(item: item)
            .tag(item.id)
        }
      }
      .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

      Divider()

      detailPane
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var detailPane: some View {
    Group {
      if let selectedItem = selectedItem {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 8) {
                Text(selectedItem.displayName)
                  .font(.title3.weight(.semibold))
                  .textSelection(.enabled)
                Text(selectedItem.sourceURL.path)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
                if let duration = selectedItem.duration {
                  Text(String(format: "%.1f seconds", duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }

              Spacer()

              if case .completed = selectedItem.status, !selectedItem.transcript.isEmpty {
                Button {
                  store.send(.copyTranscript(selectedItem.id))
                } label: {
                  Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
              }
            }

            statusView(for: selectedItem)
          }
          .padding(24)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        ContentUnavailableView(
          "Select a File",
          systemImage: "waveform.badge.magnifyingglass",
          description: Text("Choose an imported file to inspect its transcript or status.")
        )
      }
    }
  }

  @ViewBuilder
  private func statusView(for item: FilesFeature.State.QueueItem) -> some View {
    switch item.status {
    case .queued:
      statusCard(
        title: "Queued",
        message: "This file will start once earlier imports finish."
      )
    case .preparing:
      statusCard(
        title: "Preparing",
        message: "Euclid is normalizing the media into a transcription-ready audio file.",
        progress: nil
      )
    case let .transcribing(progress):
      statusCard(
        title: "Transcribing",
        message: progress > 0 ? "Model load progress: \(Int(progress * 100))%" : "Euclid is loading the model and transcribing this file.",
        progress: progress > 0 ? progress : nil
      )
    case .completed:
      if item.transcript.isEmpty {
        ContentUnavailableView(
          "No Speech Detected",
          systemImage: "waveform",
          description: Text("Transcription finished, but no text was returned.")
        )
      } else {
        Text(item.transcript)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
    case let .failed(message):
      statusCard(
        title: "Failed",
        message: message
      )
    }
  }

  private func statusCard(title: String, message: String, progress: Double? = nil) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)
      Text(message)
        .foregroundStyle(.secondary)
      if let progress {
        ProgressView(value: progress)
          .controlSize(.large)
      } else if title == "Preparing" {
        ProgressView()
          .controlSize(.large)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(nsColor: .controlBackgroundColor))
    )
  }

  private var dropZone: some View {
    RoundedRectangle(cornerRadius: 8)
      .strokeBorder(
        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
        style: StrokeStyle(lineWidth: 2, dash: [10, 8])
      )
      .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
      .frame(maxWidth: 640, minHeight: 220)
      .overlay {
        VStack(spacing: 12) {
          Image(systemName: "tray.and.arrow.down")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(.secondary)
          Text("Drop Files Here")
            .font(.title3.weight(.semibold))
          Text("mp3, wav, m4a, flac, mp4, mov, m4v")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
  }

  private var backgroundDropZone: some View {
    dropZone
      .padding(24)
      .opacity(store.items.isEmpty ? 0 : 0.0001)
      .allowsHitTesting(false)
  }

  private var selectionBinding: Binding<UUID?> {
    Binding(
      get: { store.selectedItemID },
      set: { store.send(.selectItem($0)) }
    )
  }

  private var selectedItem: FilesFeature.State.QueueItem? {
    guard let selectedItemID = store.selectedItemID else { return nil }
    return store.items[id: selectedItemID]
  }

  private func handleDrop(providers: [NSItemProvider]) -> Bool {
    Task {
      let urls = await providers.loadFileURLs()
      guard !urls.isEmpty else { return }
      await MainActor.run {
        _ = store.send(.filesDropped(urls))
      }
    }
    return true
  }
}

private struct QueueItemRow: View {
  let item: FilesFeature.State.QueueItem

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: statusSymbol)
        .foregroundStyle(statusColor)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 4) {
        Text(item.displayName)
          .lineLimit(1)

        switch item.status {
        case .queued:
          Text("Queued")
            .font(.caption)
            .foregroundStyle(.secondary)
        case .preparing:
          Text("Preparing")
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .transcribing(progress):
          if progress > 0 {
            ProgressView(value: progress)
              .controlSize(.small)
          } else {
            Text("Transcribing")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        case .completed:
          if item.transcript.isEmpty {
            Text("No speech detected")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Text(item.transcript)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        case let .failed(message):
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private var statusSymbol: String {
    switch item.status {
    case .queued:
      return "clock"
    case .preparing:
      return "waveform.badge.plus"
    case .transcribing:
      return "waveform"
    case .completed:
      return "checkmark.circle.fill"
    case .failed:
      return "exclamationmark.triangle.fill"
    }
  }

  private var statusColor: Color {
    switch item.status {
    case .queued:
      return .secondary
    case .preparing, .transcribing:
      return .accentColor
    case .completed:
      return .green
    case .failed:
      return .red
    }
  }
}

private extension Array where Element == NSItemProvider {
  func loadFileURLs() async -> [URL] {
    await withTaskGroup(of: URL?.self) { group in
      for provider in self {
        group.addTask {
          await provider.loadFileURL()
        }
      }

      var urls: [URL] = []
      for await url in group {
        if let url {
          urls.append(url)
        }
      }
      return urls
    }
  }
}

private extension NSItemProvider {
  func loadFileURL() async -> URL? {
    await withCheckedContinuation { continuation in
      if canLoadObject(ofClass: NSURL.self) {
        _ = loadObject(ofClass: NSURL.self) { object, _ in
          if let url = object as? NSURL {
            continuation.resume(returning: url as URL)
          } else {
            continuation.resume(returning: nil)
          }
        }
        return
      }

      loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        switch item {
        case let data as Data:
          continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
        case let url as URL:
          continuation.resume(returning: url)
        case let url as NSURL:
          continuation.resume(returning: url as URL)
        default:
          continuation.resume(returning: nil)
        }
      }
    }
  }
}
