import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Photos

struct ContentView: View {
    @StateObject private var document = PhotoDocument()
    @State private var photoItem: PhotosPickerItem?
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportURL: URL?
    @State private var showOriginal = false

    private let ink = Color(red: 0.10, green: 0.12, blue: 0.18)
    private let cyan = Color(red: 0.28, green: 0.89, blue: 0.98)
    private let silver = Color(red: 0.79, green: 0.84, blue: 0.91)
    private let pink = Color(red: 1.0, green: 0.48, blue: 0.72)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.96, green: 0.98, blue: 1), Color(red: 0.86, green: 0.91, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    imageCard
                    if document.sourceURL != nil { presetPicker; exportPanel }
                    else { welcomeCard }
                    footer
                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .onChange(of: document.preset) { _ in Task { await document.refreshPreview() } }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image, .heic, .jpeg, .rawImage], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { do { try await document.load(url: url) } catch { document.errorMessage = error.localizedDescription } } }
        }
        .fileExporter(isPresented: $showingExporter, document: ExportFile(url: exportURL), contentType: exportURL?.pathExtension == "heic" ? .heic : .jpeg, defaultFilename: exportURL?.lastPathComponent ?? "Digify") { result in
            if case .failure(let error) = result { document.errorMessage = error.localizedDescription }
        }
        .alert("Digify", isPresented: Binding(get: { document.errorMessage != nil }, set: { if !$0 { document.errorMessage = nil } })) {
            Button("OK", role: .cancel) { document.errorMessage = nil }
        } message: { Text(document.errorMessage ?? "") }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        // Photos may expose a RAW+JPEG asset as a pair. Prefer its original DNG
        // resource when the picker gives us an asset identifier, then fall back to
        // the system picker representation (which can still be a rendered HEIC/JPEG).
        if let identifier = item.itemIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
           let raw = PHAssetResource.assetResources(for: asset).first(where: { $0.originalFilename.lowercased().hasSuffix(".dng") }) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("digify-\(UUID().uuidString).dng")
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    PHAssetResourceManager.default().writeData(for: raw, toFile: url, options: nil) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                try await document.load(url: url)
                return
            } catch {
                // Continue with the picker-provided image if the original is unavailable.
            }
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "heic"
        await document.load(data: data, name: "Photo.\(ext)")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("DIGIFY").font(.system(size: 29, weight: .black, design: .rounded)).tracking(-1.5)
                Text("POCKET CAMERA CLUB").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2.2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "camera.aperture").font(.system(size: 22, weight: .medium)).foregroundStyle(ink).frame(width: 46, height: 42).background(LinearGradient(colors: [.white, silver], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white, lineWidth: 2))
        }.foregroundStyle(ink)
    }

    private var imageCard: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28).fill(ink).shadow(color: ink.opacity(0.18), radius: 20, y: 12)
            VStack(spacing: 0) {
                HStack { Text("ELPH 360 HS A"); Spacer(); Image(systemName: "flashlight.on.fill"); Text("AUTO") }.font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.1).foregroundStyle(.white.opacity(0.78)).padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
                ZStack {
                    if let image = showOriginal ? document.originalPreview : document.preview {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 390).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 11)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.macro").font(.system(size: 49, weight: .ultraLight))
                            Text("YOUR NEXT FAVORITE PHOTO").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.6)
                        }.foregroundStyle(.white.opacity(0.35)).frame(height: 280)
                    }
                    if document.sourceURL != nil {
                        VStack { HStack { Text(showOriginal ? "ORIGINAL" : "DIGIFY · \(document.preset.rawValue.uppercased())").font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1).padding(.horizontal, 11).padding(.vertical, 7).background(showOriginal ? silver : cyan, in: Capsule()); Spacer() }; Spacer() }.padding(21)
                    }
                }.frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) { Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity) }.buttonStyle(CameraButtonStyle(filled: true))
                    Button { showingImporter = true } label: { Label("Files", systemImage: "folder").frame(maxWidth: .infinity) }.buttonStyle(CameraButtonStyle(filled: false))
                }.padding(13).background(.white.opacity(0.07))
            }
            if document.sourceURL != nil {
                Button { showOriginal.toggle() } label: { Text("COMPARE").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).foregroundStyle(.white).padding(10).background(.black.opacity(0.52), in: Capsule()) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.bottom, 70).padding(.trailing, 25)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var welcomeCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 20)).foregroundStyle(ink).frame(width: 43, height: 43).background(LinearGradient(colors: [cyan, pink.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) { Text("From RAW to retro").font(.system(size: 17, weight: .bold, design: .rounded)); Text("HEIC · JPEG · DNG / ProRAW").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }
            Spacer()
        }.padding(16).background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 21)).foregroundStyle(ink)
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack { Text("PICK YOUR VIBE").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.4); Spacer(); Text(document.dimensions).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }
            HStack(spacing: 9) {
                preset(name: .everyday, icon: "sun.max.fill", note: "THE CLASSIC")
                preset(name: .flash, icon: "bolt.fill", note: "PARTY MODE")
                preset(name: .night, icon: "moon.stars.fill", note: "AFTER HOURS")
            }
        }.foregroundStyle(ink)
    }

    private func preset(name: CameraPreset, icon: String, note: String) -> some View {
        Button { document.preset = name; showOriginal = false } label: {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(document.preset == name ? cyan : (name == .flash ? pink : ink))
                Text(name.rawValue).font(.system(size: 12, weight: .bold, design: .rounded))
                Text(note).font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
            }.foregroundStyle(document.preset == name ? .white : ink).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(document.preset == name ? ink : .white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text("FULL RESOLUTION").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.3); Text("Original size · max quality · metadata kept").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.down.to.line.compact").foregroundStyle(ink).padding(8).background(cyan.opacity(0.6), in: Circle()) }
            HStack(spacing: 9) {
                exportButton("Save HEIC", type: .heic, icon: "livephoto")
                exportButton("Save JPEG", type: .jpeg, icon: "photo")
            }
        }.padding(16).background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 22)).foregroundStyle(ink)
    }

    private func exportButton(_ title: String, type: UTType, icon: String) -> some View {
        Button {
            Task {
                do { exportURL = try await document.export(as: type); showingExporter = true }
                catch { document.errorMessage = error.localizedDescription }
            }
        } label: {
            HStack(spacing: 7) { if document.isBusy { ProgressView().tint(.white) } else { Image(systemName: icon) }; Text(document.isBusy ? "Rendering…" : title).font(.system(size: 12, weight: .bold, design: .rounded)) }.frame(maxWidth: .infinity).padding(.vertical, 14).background(ink, in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(.white)
        }.disabled(document.isBusy)
    }

    private var footer: some View {
        HStack { Image(systemName: "sparkles"); Text("SHOT ON YOUR CAMERA. FINISHED IN DIGIFY."); Spacer(); Text("01 / 03") }.font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.8).foregroundStyle(ink.opacity(0.48)).padding(.horizontal, 3)
    }
}

struct CameraButtonStyle: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .bold, design: .rounded)).padding(.vertical, 12).foregroundStyle(filled ? Color(red: 0.1, green: 0.12, blue: 0.18) : .white).background(filled ? Color(red: 0.28, green: 0.89, blue: 0.98) : .white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13)).opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.heic, .jpeg] }
    let url: URL?
    init(url: URL?) { self.url = url }
    init(configuration: ReadConfiguration) throws { url = nil }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        return try FileWrapper(url: url, options: .immediate)
    }
}
