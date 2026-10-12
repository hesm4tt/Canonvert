import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Photos

private enum EditorStep: Equatable {
    case start, customize, export
}

private enum ExportFormat: String, CaseIterable, Identifiable {
    case heic = "HEIC"
    case jpeg = "JPEG"
    var id: String { rawValue }
    var contentType: UTType { self == .heic ? .heic : .jpeg }
    var detail: String { self == .heic ? "Smaller file · keeps more image data" : "Works almost everywhere" }
}

private enum ExportDestination: String, CaseIterable, Identifiable {
    case cameraRoll = "Camera Roll"
    case files = "Files"
    var id: String { rawValue }
    var detail: String { self == .cameraRoll ? "Save to your Photos library" : "Choose a folder and filename" }
    var icon: String { self == .cameraRoll ? "photo.on.rectangle.angled" : "folder" }
}

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
    @State private var step: EditorStep = .start
    @State private var exportFormat: ExportFormat = .heic
    @State private var exportDestination: ExportDestination = .cameraRoll

    private let ink = Color(red: 0.10, green: 0.12, blue: 0.18)
    private let cyan = Color(red: 0.28, green: 0.89, blue: 0.98)
    private let silver = Color(red: 0.79, green: 0.84, blue: 0.91)
    private let pink = Color(red: 1.0, green: 0.48, blue: 0.72)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.96, green: 0.98, blue: 1), Color(red: 0.86, green: 0.91, blue: 0.98)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Group {
                switch step {
                case .start: startScreen
                case .customize: customizeScreen
                case .export: exportScreen
                }
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                await importPhoto(item)
                if document.sourceURL != nil { showOriginal = false; step = .customize }
            }
        }
        .onChange(of: document.preset) { _ in schedulePreviewRefresh() }
        .onChange(of: document.lookSettings) { _ in schedulePreviewRefresh() }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image, .heic, .jpeg, .rawImage], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                do {
                    try await document.load(url: url)
                    showOriginal = false
                    step = .customize
                } catch { document.errorMessage = error.localizedDescription }
            }
        }
        .fileExporter(isPresented: $showingExporter, document: ExportFile(url: exportURL), contentType: exportURL?.pathExtension == "heic" ? .heic : .jpeg, defaultFilename: exportURL?.deletingPathExtension().lastPathComponent ?? "Canonvert") { result in
            switch result {
            case .success: document.noticeMessage = "Your photo was exported to Files."
            case .failure(let error): document.errorMessage = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView { url in
                Task {
                    do {
                        try await document.load(url: url)
                        showOriginal = false
                        step = .customize
                    } catch { document.errorMessage = error.localizedDescription }
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

    private var startScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                brandHeader
                HStack {
                    Text("01 / 03 · CAPTURE").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.1).foregroundStyle(.secondary)
                    Spacer()
                    stepIndicator(active: 1).frame(width: 86)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start with a photo.").font(.system(size: 32, weight: .black, design: .rounded)).tracking(-1.2)
                    Text("Take one now, or choose an image to give it a pocket-camera look.").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                }.foregroundStyle(ink)

                Button { showingCamera = true } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "camera.fill").font(.system(size: 21, weight: .semibold)).frame(width: 48, height: 48).background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Take a photo").font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("3:4 viewfinder · grid · max quality").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold))
                    }.padding(16).foregroundStyle(.white).background(ink, in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 12) {
                    Text("OR CHOOSE A PHOTO").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.2).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            sourceButton(title: "Photos", icon: "photo.on.rectangle", highlighted: false)
                        }.buttonStyle(.plain)
                        Button { showingImporter = true } label: { sourceButton(title: "Files", icon: "folder", highlighted: false) }.buttonStyle(.plain)
                    }
                }

                HStack(spacing: 13) {
                    Image(systemName: "sparkles.rectangle.stack").font(.system(size: 20)).foregroundStyle(ink).frame(width: 43, height: 43).background(LinearGradient(colors: [cyan, pink.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HEIC · JPEG · DNG / Apple ProRAW").font(.system(size: 11, weight: .bold, design: .monospaced))
                        Text("Your images stay on this device.").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(15).background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 19))
            }.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 28)
        }
    }

    private var customizeScreen: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                screenHeader(title: "Customize", stepNumber: 2, backAction: { step = .start })
                    .padding(.horizontal, 20).padding(.top, 7).padding(.bottom, 10)

                previewFrame(height: min(max(geometry.size.height * 0.40, 225), 370))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 13) {
                        presetPicker
                        customizePanel
                    }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                primaryAction(title: "Next · Export", icon: "arrow.right") { step = .export }
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
            }
        }
    }

    private var exportScreen: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                screenHeader(title: "Export", stepNumber: 3, backAction: { step = .customize })
                    .padding(.horizontal, 20).padding(.top, 7).padding(.bottom, 10)

                HStack(spacing: 14) {
                    if let image = document.preview {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 86, height: 86).clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("READY TO SAVE").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.1).foregroundStyle(.secondary)
                        Text(document.sourceName.isEmpty ? "Your edited photo" : document.sourceName).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1)
                        Text("\(document.dimensions) · metadata kept").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(15).background(.white.opacity(0.83), in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 18).padding(.bottom, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        selectionSection(title: "1 · CHOOSE FORMAT", subtitle: "Full resolution, highest available quality") {
                            ForEach(ExportFormat.allCases) { format in
                                selectionCard(title: format.rawValue, detail: format.detail, icon: format == .heic ? "livephoto" : "photo", selected: exportFormat == format) { exportFormat = format }
                            }
                        }
                        selectionSection(title: "2 · CHOOSE LOCATION", subtitle: "Pick where the finished photo should go") {
                            ForEach(ExportDestination.allCases) { destination in
                                selectionCard(title: destination.rawValue, detail: destination.detail, icon: destination.icon, selected: exportDestination == destination) { exportDestination = destination }
                            }
                        }
                    }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 15)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                let saveTitle = exportDestination == .cameraRoll ? "Save to Camera Roll" : "Choose Files location"
                primaryAction(title: saveTitle, icon: exportDestination == .cameraRoll ? "photo.badge.arrow.down" : "folder.badge.plus", busy: document.isBusy) { runExport() }
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var brandHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("CANONVERT").font(.system(size: 28, weight: .black, design: .rounded)).tracking(-1.5)
                Text("POCKET CAMERA CLUB").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2.1).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "camera.aperture").font(.system(size: 21, weight: .medium)).foregroundStyle(ink).frame(width: 46, height: 42).background(LinearGradient(colors: [.white, silver], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white, lineWidth: 2))
        }.foregroundStyle(ink)
    }

    private func stepIndicator(active: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(1...3, id: \.self) { number in
                Capsule().fill(number <= active ? cyan : ink.opacity(0.10)).frame(height: 4)
            }
        }.accessibilityLabel("Step \(active) of 3")
    }

    private func screenHeader(title: String, stepNumber: Int, backAction: @escaping () -> Void) -> some View {
        VStack(spacing: 11) {
            HStack {
                Button(action: backAction) {
                    Label("Back", systemImage: "chevron.left").font(.system(size: 13, weight: .semibold, design: .rounded))
                }.foregroundStyle(ink)
                Spacer()
                Text("0\(stepNumber) / 03").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
            }
            HStack {
                Text(title).font(.system(size: 27, weight: .black, design: .rounded)).tracking(-0.7)
                Spacer()
                stepIndicator(active: stepNumber).frame(width: 86)
            }.foregroundStyle(ink)
        }
    }

    private func previewFrame(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22).fill(ink)
            if let image = showOriginal ? document.originalPreview : document.preview {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: height).clipShape(RoundedRectangle(cornerRadius: 16)).padding(8)
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(showOriginal ? "ORIGINAL" : "CANONVERT · \((document.activeSavedLookName ?? document.preset.rawValue).uppercased())")
                .font(.system(size: 9, weight: .black, design: .monospaced)).tracking(0.7).padding(.horizontal, 10).padding(.vertical, 7)
                .background(showOriginal ? silver : cyan, in: Capsule()).padding(14)
            Button { showOriginal.toggle() } label: {
                Text(showOriginal ? "EDITED" : "COMPARE").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.7).foregroundStyle(.white).padding(.horizontal, 11).padding(.vertical, 8).background(.black.opacity(0.58), in: Capsule())
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(14)
        }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: 22)).shadow(color: ink.opacity(0.13), radius: 14, y: 8)
    }

    private func sourceButton(title: String, icon: String, highlighted: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer(minLength: 0)
        }.padding(15).frame(maxWidth: .infinity).foregroundStyle(highlighted ? .white : ink).background(highlighted ? ink : .white.opacity(0.82), in: RoundedRectangle(cornerRadius: 17))
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
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(document.preset == name ? cyan : (name == .flash ? pink : ink))
                Text(name.rawValue).font(.system(size: 12, weight: .bold, design: .rounded))
                Text(note).font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
            }.foregroundStyle(document.preset == name ? .white : ink).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(document.preset == name ? ink : .white.opacity(0.75), in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }

    private var customizePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MAKE IT YOURS").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.3)
                    Text("Adjust the look. Your photo stays up top.").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset") { document.selectPreset(document.preset) }.font(.system(size: 11, weight: .semibold, design: .rounded))
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
            }.font(.system(size: 12, weight: .semibold, design: .rounded)).tint(ink)
            HStack(spacing: 9) {
                Menu {
                    if document.savedLooks.isEmpty { Text("Save a look to see it here") }
                    else {
                        ForEach(document.savedLooks) { look in Button(look.name, systemImage: "bookmark") { document.applySavedLook(look); showOriginal = false } }
                        Divider()
                        ForEach(document.savedLooks) { look in Button("Delete \(look.name)", systemImage: "trash", role: .destructive) { document.deleteLook(look) } }
                    }
                } label: { Label("My looks · \(document.savedLooks.count)", systemImage: "bookmark").frame(maxWidth: .infinity).padding(.vertical, 12).background(silver.opacity(0.5), in: RoundedRectangle(cornerRadius: 13)) }
                    .disabled(document.savedLooks.isEmpty)
                Button {
                    newLookName = document.activeSavedLookName ?? "\(document.preset.rawValue) Custom"
                    showingSaveLook = true
                } label: { Label("Save look", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 12).background(ink, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(.white) }
            }.font(.system(size: 11, weight: .bold, design: .rounded))
        }.padding(15).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 21)).foregroundStyle(ink)
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

    private func selectionSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.1)
                Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            content()
        }.foregroundStyle(ink)
    }

    private func selectionCard(title: String, detail: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 39, height: 39).background(selected ? cyan : silver.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(detail).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 20, weight: .medium)).foregroundStyle(selected ? ink : .secondary.opacity(0.45))
            }.padding(12).background(.white.opacity(selected ? 0.98 : 0.72), in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(selected ? cyan.opacity(0.85) : .clear, lineWidth: 2))
        }.buttonStyle(.plain)
    }

    private func primaryAction(title: String, icon: String, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if busy { ProgressView().tint(ink) } else { Image(systemName: icon) }
                Text(busy ? "Working…" : title).font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                if !busy && step == .customize { Image(systemName: "arrow.right") }
            }.padding(.horizontal, 18).frame(maxWidth: .infinity).frame(height: 54).foregroundStyle(ink).background(cyan, in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain).disabled(busy)
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
        // Prefer the original DNG resource when Photos exposes a RAW+JPEG pair.
        if let identifier = item.itemIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
           let raw = PHAssetResource.assetResources(for: asset).first(where: { $0.originalFilename.lowercased().hasSuffix(".dng") }) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("canonvert-\(UUID().uuidString).dng")
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    PHAssetResourceManager.default().writeData(for: raw, toFile: url, options: nil) { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    }
                }
                try await document.load(url: url)
                return
            } catch {
                // Fall back to the rendered representation from Photos.
            }
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "heic"
        await document.load(data: data, name: "Photo.\(ext)")
    }

    private func runExport() {
        Task {
            do {
                if exportDestination == .cameraRoll {
                    try await document.saveToPhotos(as: exportFormat.contentType)
                } else {
                    exportURL = try await document.export(as: exportFormat.contentType)
                    showingExporter = true
                }
            } catch { document.errorMessage = error.localizedDescription }
        }
    }
}

struct CameraButtonStyle: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .bold, design: .rounded)).padding(.vertical, 12).foregroundStyle(filled ? Color(red: 0.1, green: 0.12, blue: 0.18) : Color.white).background(filled ? Color(red: 0.28, green: 0.89, blue: 0.98) : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13)).opacity(configuration.isPressed ? 0.75 : 1)
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
