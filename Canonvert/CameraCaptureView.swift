import SwiftUI
import AVFoundation

@MainActor
final class CameraCaptureController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var isReady = false
    @Published var supportsProRAW = false
    @Published var isCapturing = false
    @Published var message: String?
    let session = AVCaptureSession()

    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.hesm4tt.digify.camera-session")
    private var proRAWType: OSType?
    private var usesHEIF = true
    var onCapture: ((URL) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.configureAndStart() }
                    else { self.message = "Camera access is off. Allow it in Settings to take a photo." }
                }
            }
        case .denied, .restricted:
            message = "Camera access is off. Allow it in Settings to take a photo."
        @unknown default:
            message = "Camera access is unavailable on this device."
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                Task { @MainActor in self.message = "No camera is available in this environment. Photos and Files still work." }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                self.session.commitConfiguration()
                Task { @MainActor in self.message = "This device cannot configure photo capture." }
                return
            }
            self.session.addInput(input)
            self.session.addOutput(self.output)
            self.output.maxPhotoQualityPrioritization = .quality
            self.usesHEIF = self.output.availablePhotoCodecTypes.contains(.hevc)
            if #available(iOS 16.0, *) {
                if let dimensions = device.activeFormat.supportedMaxPhotoDimensions.max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) {
                    self.output.maxPhotoDimensions = dimensions
                }
            } else {
                self.output.isHighResolutionCaptureEnabled = true
            }
            self.proRAWType = self.output.availableRawPhotoPixelFormatTypes.first(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat)
            self.output.isAppleProRAWEnabled = self.proRAWType != nil
            self.session.commitConfiguration()
            self.session.startRunning()
            Task { @MainActor in
                self.supportsProRAW = self.proRAWType != nil
                self.isReady = true
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capture(useProRAW: Bool) {
        guard isReady, !isCapturing else { return }
        isCapturing = true
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings: AVCapturePhotoSettings
            if useProRAW, let rawType = self.proRAWType {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: nil)
            } else {
                let format: [String: Any]? = self.usesHEIF ? [AVVideoCodecKey: AVVideoCodecType.hevc] : nil
                settings = AVCapturePhotoSettings(format: format)
            }
            settings.photoQualityPrioritization = .quality
            if #available(iOS 16.0, *) { settings.maxPhotoDimensions = self.output.maxPhotoDimensions }
            else { settings.isHighResolutionPhotoEnabled = true }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let isRAW = photo.isRawPhoto
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Task { @MainActor in
                self.isCapturing = false
                self.message = error?.localizedDescription ?? "The camera could not create a photo."
            }
            return
        }
        let ext = isRAW ? "dng" : (usesHEIF ? "heic" : "jpg")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("canonvert-capture-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            Task { @MainActor in
                self.isCapturing = false
                self.onCapture?(url)
            }
        } catch {
            Task { @MainActor in
                self.isCapturing = false
                self.message = error.localizedDescription
            }
        }
    }
}

struct CameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraCaptureController()
    @State private var useProRAW = false
    var onCapture: (URL) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            GridOverlay().stroke(.white.opacity(0.58), lineWidth: 0.7).padding(.horizontal, 24).padding(.vertical, 30).allowsHitTesting(false)
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44).background(.black.opacity(0.48), in: Circle()) }
                    Spacer()
                    if camera.supportsProRAW {
                        Toggle(isOn: $useProRAW) { Text("ProRAW").font(.system(size: 12, weight: .bold, design: .rounded)) }
                            .toggleStyle(.button).tint(.white).foregroundStyle(.white)
                            .padding(8).background(.black.opacity(0.5), in: Capsule())
                    } else {
                        Text("MAX QUALITY").font(.system(size: 10, weight: .bold, design: .monospaced)).padding(10).background(.black.opacity(0.48), in: Capsule())
                    }
                }.padding(.horizontal, 20).padding(.top, 14)
                Spacer()
                HStack(spacing: 14) {
                    Image(systemName: "square.grid.3x3").font(.system(size: 14))
                    Text("3 × 3 GRID").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                }.padding(.horizontal, 15).padding(.vertical, 10).background(.black.opacity(0.48), in: Capsule()).padding(.bottom, 24)
                Button { camera.capture(useProRAW: useProRAW) } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 5).frame(width: 78, height: 78)
                        Circle().fill(.white).frame(width: 62, height: 62)
                        if camera.isCapturing { ProgressView().tint(.black) }
                    }
                }.disabled(!camera.isReady || camera.isCapturing).opacity(camera.isReady ? 1 : 0.55).padding(.bottom, 34)
            }.foregroundStyle(.white)
            if let message = camera.message {
                VStack(spacing: 14) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Close") { dismiss() }.fontWeight(.bold)
                }.padding(24).foregroundStyle(.white).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 18)).padding(30)
            } else if !camera.isReady {
                ProgressView("Starting camera…").tint(.white).foregroundStyle(.white)
            }
        }
        .statusBarHidden()
        .onAppear { camera.onCapture = { url in dismiss(); onCapture(url) }; camera.start() }
        .onDisappear { camera.stop() }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.previewLayer.session = session }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct GridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 1...2 {
            let x = rect.width * CGFloat(step) / 3
            let y = rect.height * CGFloat(step) / 3
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}
