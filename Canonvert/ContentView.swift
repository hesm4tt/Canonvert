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
    @State private var previewTask: Task<Void, Never>?
    @State private var showingSaveLook = false
    @State private var newLookName = ""
    @State private var showingCamera = false

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
                    if document.sourceURL != nil { presetPicker; customizePanel; exportPanel }
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
        .onChange(of: document.preset) { _ in schedulePreviewRefresh() }
        .onChange(of: document.lookSettings) { _ in schedulePreviewRefresh() }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image, .heic, .jpeg, .rawImage], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { do { try await document.load(url: url) } catch { document.errorMessage = error.localizedDescription } } }
        }
        .fileExporter(isPresented: $showingExporter, document: ExportFile(url: exportURL), contentType: exportURL?.pathExtension == "heic" ? .heic : .jpeg, defaultFilename: exportURL?.lastPathComponent ?? "Canonvert") { result in
            if case .failure(let error) = result { document.errorMessage = error.localizedDescription }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView { url in
                Task {
                    do { try await document.load(url: url); showOriginal = false }
                    catch { document.errorMessage = error.localizedDescription }
                }
            }
        }
        .sheet(isPresented: $showingSaveLook) {
            NavigationStack {
                Form {
                    TextField("Preset name", text: $newLookName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                }
                .navigationTitle("Save this look")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingSaveLook = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            document.saveLook(named: newLookName)
                            showingSaveLook = false
                        }.disabled(newLookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .presentationDetents([.height(210)])
            }
        }
        .alert("Canonvert", isPresented: Binding(get: { document.errorMessage != nil || document.noticeMessage != nil }, set: { if !$0 { document.errorMessage = nil; document.noticeMessage = nil } })) {
            Button("OK", role: .cancel) { document.errorMessage = nil; document.noticeMessage = nil }
        } message: { Text(document.errorMessage ?? document.noticeMessage ?? "") }
    }

    private func schedulePreviewRefresh() {
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            await document.refreshPreview()
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        // Photos may expose a RAW+JPEG asset as a pair. Prefer its original DNG
        // resource when the picker gives us an asset identifier, then fall back to
        // the system picker representation (which can still be a rendered HEIC/JPEG).
        if let identifier = item.itemIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
           let raw = PHAssetResource.assetResources(for: asset).first(where: { $0.originalFilename.lowercased().hasSuffix(".dng") }) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("canonvert-\(UUID().uuidString).dng")
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
                Text("CANONVERT").font(.system(size: 29, weight: .black, design: .rounded)).tracking(-1.5)
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
                        VStack { HStack { Text(showOriginal ? "ORIGINAL" : "CANONVERT · \((document.activeSavedLookName ?? document.preset.rawValue).uppercased())").font(.system(size: 9, weight: .black, design: .monospaced)).tracking(1).padding(.horizontal, 11).padding(.vertical, 7).background(showOriginal ? silver : cyan, in: Capsule()); Spacer() }; Spacer() }.padding(21)
                    }
                }.frame(maxWidth: .infinity)
                HStack(spacing: 7) {
                    Button { showingCamera = true } label: { Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity) }.buttonStyle(CameraButtonStyle(filled: true))
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) { Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity) }.buttonStyle(CameraButtonStyle(filled: false))
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
            VStack(alignment: .leading, spacing: 4) { Text("From RAW to retro").font(.system(size: 17, weight: .bold, design: .rounded)); Text("HEIC · JPEG · DNG / Apple ProRAW").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }
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
        Button { document.selectPreset(name); showOriginal = false } label: {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(document.preset == name ? cyan : (name == .flash ? pink : ink))
                Text(name.rawValue).font(.system(size: 12, weight: .bold, design: .rounded))
                Text(note).font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
            }.foregroundStyle(document.preset == name ? .white : ink).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(document.preset == name ? ink : .white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private var customizePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MAKE IT YOURS").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.3)
                    Text("Tune the pocket-camera color, light, and detail.").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset") { document.selectPreset(document.preset) }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }

            settingSlider("Color", keyPath: \.saturation, range: 0.75...1.5, valueText: { String(format: "%.2f×", $0) })
            settingSlider("Contrast", keyPath: \.contrast, range: 0.85...1.3, valueText: { String(format: "%.2f×", $0) })
            settingSlider("Warmth", keyPath: \.warmth, range: 5000...7500, valueText: { "\(Int($0)) K" })
            settingSlider("Flash lift", keyPath: \.shadowLift, range: 0...1, valueText: { "\(Int($0 * 100))%" })

            DisclosureGroup("Fine tune") {
                VStack(spacing: 12) {
                    settingSlider("Exposure", keyPath: \.exposure, range: -0.08...0.12, valueText: { String(format: "%+.2f", $0) })
                    settingSlider("Sharpness", keyPath: \.sharpness, range: 0...0.6, valueText: { String(format: "%.2f", $0) })
                    settingSlider("Vignette", keyPath: \.vignette, range: 0...0.35, valueText: { "\(Int($0 * 100))%" })
                }.padding(.top, 12)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tint(ink)

            HStack(spacing: 9) {
                Menu {
                    if document.savedLooks.isEmpty {
                        Text("Save a look to see it here")
                    } else {
                        ForEach(document.savedLooks) { look in
                            Button(look.name, systemImage: "bookmark") { document.applySavedLook(look); showOriginal = false }
                        }
                        Divider()
                        ForEach(document.savedLooks) { look in
                            Button("Delete \(look.name)", systemImage: "trash", role: .destructive) { document.deleteLook(look) }
                        }
                    }
                } label: {
                    Label("My looks · \(document.savedLooks.count)", systemImage: "bookmark")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(silver.opacity(0.5), in: RoundedRectangle(cornerRadius: 13))
                }.disabled(document.savedLooks.isEmpty)

                Button {
                    newLookName = document.activeSavedLookName ?? "\(document.preset.rawValue) Custom"
                    showingSaveLook = true
                } label: {
                    Label("Save look", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(ink, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(.white)
                }
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(16)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 22))
        .foregroundStyle(ink)
    }

    private func settingSlider(_ title: String, keyPath: WritableKeyPath<CameraLookSettings, Double>, range: ClosedRange<Double>, valueText: @escaping (Double) -> String) -> some View {
        let value = Binding<Double>(
            get: { document.lookSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = document.lookSettings
                settings[keyPath: keyPath] = newValue
                document.updateLookSettings(settings)
            }
        )
        return VStack(spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
                Spacer()
                Text(valueText(value.wrappedValue)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).tint(cyan).accessibilityLabel(title).accessibilityValue(valueText(value.wrappedValue))
        }
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text("FULL RESOLUTION").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.3); Text("Original size · max quality · metadata kept").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.down.to.line.compact").foregroundStyle(ink).padding(8).background(cyan.opacity(0.6), in: Circle()) }
            HStack(spacing: 9) {
                formatMenu("Save to Photos", icon: "photo.on.rectangle.angled", toPhotos: true)
                formatMenu("Export to Files", icon: "folder", toPhotos: false)
            }
        }.padding(16).background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 22)).foregroundStyle(ink)
    }

    private func formatMenu(_ title: String, icon: String, toPhotos: Bool) -> some View {
        Menu {
            Button("HEIC", systemImage: "livephoto") { runExport(type: .heic, toPhotos: toPhotos) }
            Button("JPEG", systemImage: "photo") { runExport(type: .jpeg, toPhotos: toPhotos) }
        } label: {
            HStack(spacing: 7) { if document.isBusy { ProgressView().tint(.white) } else { Image(systemName: icon) }; Text(document.isBusy ? "Working…" : title).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8) }.frame(maxWidth: .infinity).padding(.vertical, 14).background(toPhotos ? ink : silver, in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(toPhotos ? .white : ink)
        }
        .disabled(document.isBusy)
    }

    private func runExport(type: UTType, toPhotos: Bool) {
        Task {
            do {
                if toPhotos {
                    try await document.saveToPhotos(as: type)
                } else {
                    exportURL = try await document.export(as: type)
                    showingExporter = true
                }
            } catch { document.errorMessage = error.localizedDescription }
        }
    }

    private var footer: some View {
        HStack { Image(systemName: "sparkles"); Text("SHOT ON YOUR CAMERA. FINISHED IN CANONVERT."); Spacer(); Text("01 / 03") }.font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.8).foregroundStyle(ink.opacity(0.48)).padding(.horizontal, 3)
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
