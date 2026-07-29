//
//  ImportSheet.swift
//  Tennis AI Coach
//
//  Pick a video from Photos (PhotosPicker) or Files (.fileImporter), copy it to
//  a temp URL the app owns, and hand it back for analysis.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Transferable wrapper that copies a picked movie into a temp file we control.
struct MovieImport: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("import_\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return MovieImport(url: temp)
        }
    }
}

struct ImportSheet: View {
    let onPicked: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "video.badge.plus")
                    .font(.title)
                    .foregroundStyle(Theme.court)
                    .padding(.top, Theme.Spacing.m)
                    .accessibilityHidden(true)

                Text("Add a tennis clip")
                    .font(.title2.weight(.semibold))
                Text("Choose a video of your play. For best results, film side-on with your full body in frame.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    PhotosPicker(selection: $photoItem, matching: .videos, preferredItemEncoding: .current) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionButton()

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Browse Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryActionButton()
                }
                .padding(.horizontal)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.focus)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .overlay {
                if isLoading {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                        ProgressView("Preparing video…")
                            .padding(Theme.Spacing.l)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.2), value: isLoading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isLoading)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            loadFromPhotos(newItem)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie, .video],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func loadFromPhotos(_ item: PhotosPickerItem) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                if let movie = try await item.loadTransferable(type: MovieImport.self) {
                    finish(with: movie.url)
                } else {
                    fail("Couldn't load that video. Try another clip.")
                }
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let picked = urls.first else { return }
            isLoading = true
            errorMessage = nil
            let didScope = picked.startAccessingSecurityScopedResource()
            defer { if didScope { picked.stopAccessingSecurityScopedResource() } }
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("import_\(UUID().uuidString).\(picked.pathExtension.isEmpty ? "mov" : picked.pathExtension)")
            do {
                try? FileManager.default.removeItem(at: temp)
                try FileManager.default.copyItem(at: picked, to: temp)
                finish(with: temp)
            } catch {
                fail(error.localizedDescription)
            }
        case .failure(let error):
            fail(error.localizedDescription)
        }
    }

    private func finish(with url: URL) {
        isLoading = false
        onPicked(url)
    }

    private func fail(_ message: String) {
        isLoading = false
        errorMessage = message
    }
}
