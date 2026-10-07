import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum TendiesDocumentPicker {
    static let useCopyMode: Void = {
        let originalMethod = class_getInstanceMethod(
            UIDocumentPickerViewController.self,
            #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:))
        )!
        let copyMethod = class_getInstanceMethod(
            UIDocumentPickerViewController.self,
            #selector(UIDocumentPickerViewController.placard_init(forOpeningContentTypes:asCopy:))
        )!
        method_exchangeImplementations(originalMethod, copyMethod)
    }()
}

private extension UIDocumentPickerViewController {
    @objc func placard_init(
        forOpeningContentTypes contentTypes: [UTType],
        asCopy: Bool
    ) -> UIDocumentPickerViewController {
        placard_init(forOpeningContentTypes: contentTypes, asCopy: true)
    }
}

@main
struct PlacardApp: App {
    var body: some Scene {
        WindowGroup {
            AirBeepRootView()
        }
    }
}

struct UnsupportedSystemView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Unsupported System Version", systemImage: "exclamationmark.triangle")
        } description: {
            Text("This version of iOS/iPadOS is not supported.\nSupported: \(SystemCompatibility.supportedRangeDescription)")
        }
    }
}

struct PlacardRootView: View {
    @State private var selection: AppTab = .browse

    var body: some View {
        TabView(selection: $selection) {
            Tab("Browse", systemImage: "square.grid.2x2", value: .browse) {
                WallpaperBrowserView()
            }

            Tab("Create", systemImage: "plus", value: .create) {
                CustomWallpaperView()
            }

            Tab("Library", systemImage: "rectangle.stack", value: .library) {
                InstalledWallpapersView()
            }
        }
        .tint(.accentColor)
    }
}

private enum AppTab: Hashable {
    case browse
    case create
    case library
}

struct WallpaperBrowserView: View {
    private static let importablePackageTypes = ["tendies"].compactMap {
        UTType(filenameExtension: $0, conformingTo: .data)
    }

    private let catalog: WallpaperCatalog

    @State private var collection: WallpaperCollection = .caPlayground
    @State private var loadState: CatalogLoadState = .idle
    @State private var query = ""
    @State private var sortOrder: WallpaperSortOrder = .random
    @State private var ordered: [Wallpaper] = []
    @State private var loadedCollection: WallpaperCollection?
    @State private var isImportingPackage = false
    @State private var importCoordinator = InstallCoordinator()

    init(catalog: WallpaperCatalog = .live) {
        self.catalog = catalog
        _ = TendiesDocumentPicker.useCopyMode
    }

    private var displayedWallpapers: [Wallpaper] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return ordered }
        return ordered.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.authors?.localizedCaseInsensitiveContains(trimmedQuery) == true
        }
    }

    @ViewBuilder
    private var unavailableOverlay: some View {
        switch loadState {
        case .failed(let message):
            ContentUnavailableView {
                Label("Unable to Load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await load(collection) } }
            }
        case .loaded where displayedWallpapers.isEmpty:
            ContentUnavailableView.search(text: query)
        default:
            EmptyView()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                switch loadState {
                case .idle, .loading:
                    WallpaperLoadingGrid()
                case .loaded where !displayedWallpapers.isEmpty:
                    WallpaperGrid(wallpapers: displayedWallpapers)
                default:
                    EmptyView()
                }
            }
            .overlay { unavailableOverlay }
            .navigationTitle(collection.title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Wallpaper Source", selection: $collection) {
                        ForEach(WallpaperCollection.allCases) { collection in
                            Text(collection.title).tag(collection)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import Wallpaper", systemImage: "square.and.arrow.down") {
                        isImportingPackage = true
                    }
                    .labelStyle(.iconOnly)
                    .disabled(importCoordinator.state.isWorking)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(WallpaperSortOrder.allCases) { order in
                                Label(order.title, systemImage: order.symbol).tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .onChange(of: sortOrder) { _, _ in applyOrder() }
            .searchable(text: $query, prompt: "Search")
            .refreshable { await refresh() }
            .task(id: collection) { await loadIfNeeded(collection) }
            .fileImporter(
                isPresented: $isImportingPackage,
                allowedContentTypes: Self.importablePackageTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let packageURLs) = result, !packageURLs.isEmpty {
                    importCoordinator.install(packagesAt: packageURLs)
                }
            }
            .alert(
                "Unable to Import Wallpaper",
                isPresented: .init(
                    get: { importCoordinator.state.isTerminal },
                    set: { if !$0 { importCoordinator.reset() } }
                )
            ) {
                Button("OK", role: .cancel) { importCoordinator.reset() }
            } message: {
                Text(importCoordinator.state.message)
            }
            .alert(
                "Wallpaper Installed",
                isPresented: importLocationNoticePresented
            ) {
                Button("Don't Show Again") {
                    WallpaperLocationNotice.disable()
                    importCoordinator.continueAfterLocationNotice()
                }
                Button("Continue") {
                    importCoordinator.continueAfterLocationNotice()
                }
            } message: {
                Text("After the screen refreshes, open the system Add New Wallpaper page and find your wallpaper by name.")
            }
            .overlay {
                if importCoordinator.state == .respringing {
                    NeoSpringView()
                        .ignoresSafeArea()
                        .transition(.opacity)
                } else if importCoordinator.state.isWorking {
                    ProgressView(importCoordinator.state.message)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
            }
        }
    }

    private func applyOrder() {
        guard case .loaded(let wallpapers) = loadState else { return }
        ordered = sortOrder.apply(to: wallpapers)
    }

    private var importLocationNoticePresented: Binding<Bool> {
        Binding(
            get: { importCoordinator.state == .installed },
            set: { isPresented in
                if !isPresented {
                    importCoordinator.continueAfterLocationNotice()
                }
            }
        )
    }

    /// Initial load / collection change: show the loading grid, then fetch.
    private func loadIfNeeded(_ targetCollection: WallpaperCollection) async {
        guard loadedCollection != targetCollection else { return }
        await load(targetCollection)
    }

    private func load(_ targetCollection: WallpaperCollection) async {
        loadState = .loading
        ordered = []
        await fetch(targetCollection, policy: .cached)
    }

    /// Pull to refresh: keep the current content on screen while fetching so
    /// swapping to a loading state doesn't cancel the refresh task mid-request.
    private func refresh() async {
        await fetch(collection, policy: .refresh)
    }

    private func fetch(
        _ targetCollection: WallpaperCollection,
        policy: CatalogFetchPolicy
    ) async {
        do {
            let wallpapers = try await catalog.fetch(targetCollection, policy)
            guard targetCollection == collection else { return }
            loadState = .loaded(wallpapers)
            loadedCollection = targetCollection
            applyOrder()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            // Only surface a hard failure when there's nothing already shown;
            // a failed refresh should quietly keep the existing wallpapers.
            if case .loaded = loadState { return }
            loadState = .failed(error.localizedDescription)
        }
    }

}

private enum CatalogLoadState: Equatable {
    case idle
    case loading
    case loaded([Wallpaper])
    case failed(String)

}

struct CustomWallpaperView: View {
    @State private var selectedVideo: PhotosPickerItem?
    @State private var draft: VideoWallpaperDraft?
    @State private var importedVideoURL: URL?
    @State private var isImportingVideo = false
    @State private var videoImportError: String?

    var body: some View {
        NavigationStack {
            // Fills the visible height so the picker owns the page instead of
            // leaving a void below it, but still scrolls at large text sizes.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        videoPickerCard
                            .frame(maxHeight: .infinity)
                        supportSection
                    }
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Create")
            .onChange(of: selectedVideo) { _, item in
                guard let item else { return }
                importVideo(item)
            }
            .sheet(item: $draft, onDismiss: cleanUpImportedVideo) { draft in
                VideoWallpaperDetailView(draft: draft)
            }
            .alert(
                "Unable to Import Video",
                isPresented: .init(
                    get: { videoImportError != nil },
                    set: { if !$0 { videoImportError = nil } }
                ),
                presenting: videoImportError
            ) { _ in
                Button("OK", role: .cancel) { videoImportError = nil }
            } message: {
                Text($0)
            }
            .overlay {
                if isImportingVideo {
                    ProgressView("Importing…")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }
            }
        }
    }

    /// One large tap target instead of a card wrapped around a button — the whole
    /// area is the picker, so the page reads as a single action.
    private var videoPickerCard: some View {
        PhotosPicker(selection: $selectedVideo, matching: .videos) {
            VStack(spacing: 8) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                    .padding(.bottom, 4)

                Text("Choose Video")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Choose a vertical video to turn into a Lock Screen wallpaper.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Up to 12 seconds")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isImportingVideo)
        .background(.tint.opacity(0.08), in: .rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(
                    .tint.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])
                )
        }
    }

    /// Developer link and donation code share one grouped container so they read
    /// as secondary information rather than two more standalone cards.
    private var supportSection: some View {
        VStack(spacing: 0) {
            developerRow
            Divider().padding(.leading, 16)
            donationRow
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var developerRow: some View {
        Link(destination: URL(string: "https://v.douyin.com/jIfvCCHjwFE")!) {
            HStack(spacing: 12) {
                Image("DeveloperAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(.circle)

                Text("Developer")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("SUSS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Developer SUSS")
    }

    private var donationRow: some View {
        DisclosureGroup {
            Image("DonationCode")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: 220)
                .clipShape(.rect(cornerRadius: 12))
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 4)
        } label: {
            Label {
                Text("Thanks SUSS - WeChat Donation Code")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func importVideo(_ item: PhotosPickerItem) {
        isImportingVideo = true
        Task {
            defer {
                selectedVideo = nil
                isImportingVideo = false
            }
            do {
                guard let video = try await item.loadTransferable(type: ImportedVideo.self) else {
                    throw VideoWallpaperError.invalidVideo
                }
                importedVideoURL = video.url
                draft = VideoWallpaperDraft(url: video.url)
            } catch {
                videoImportError = error.localizedDescription
            }
        }
    }

    private func cleanUpImportedVideo() {
        guard let importedVideoURL else { return }
        try? FileManager.default.removeItem(at: importedVideoURL)
        self.importedVideoURL = nil
    }
}

#Preview("Browser") {
    PlacardRootView()
}

#Preview("Unavailable") {
    WallpaperBrowserView(catalog: .failingPreview)
}
