import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Combine
import Photos

enum CameraPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case everyday = "Everyday", flash = "Flash", night = "Night"
    var id: String { rawValue }

    var settings: CameraLookSettings {
        switch self {
        case .everyday:
            CameraLookSettings(saturation: 1.10, contrast: 1.055, exposure: 0.006, warmth: 6300, shadowLift: 0.48, highlightRolloff: 0.92, sharpness: 0.22, vignette: 0.10)
        case .flash:
            CameraLookSettings(saturation: 1.18, contrast: 1.12, exposure: 0.018, warmth: 6100, shadowLift: 0.30, highlightRolloff: 0.82, sharpness: 0.32, vignette: 0.10)
        case .night:
            CameraLookSettings(saturation: 1.08, contrast: 1.025, exposure: 0.028, warmth: 6300, shadowLift: 0.72, highlightRolloff: 0.92, sharpness: 0.22, vignette: 0.20)
        }
    }
}

struct CameraLookSettings: Codable, Equatable, Sendable {
    var saturation: Double
    var contrast: Double
    var exposure: Double
    var warmth: Double
    var shadowLift: Double
    var highlightRolloff: Double
    var sharpness: Double
    var vignette: Double

    func apply(to image: CIImage) -> CIImage {
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.saturation = Float(saturation)
        color.contrast = Float(contrast)
        color.brightness = Float(exposure)
        guard let controlled = color.outputImage else { return image }

        let balance = CIFilter.temperatureAndTint()
        balance.inputImage = controlled
        balance.neutral = CIVector(x: 6500, y: 0)
        balance.targetNeutral = CIVector(x: warmth, y: 0)
        let warmed = balance.outputImage ?? controlled

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = warmed
        sharpen.sharpness = Float(sharpness)
        let detailed = sharpen.outputImage ?? warmed

        let shadows = CIFilter.highlightShadowAdjust()
        shadows.inputImage = detailed
        shadows.shadowAmount = Float(shadowLift)
        shadows.highlightAmount = Float(highlightRolloff)
        let balanced = shadows.outputImage ?? detailed

        let vignetteFilter = CIFilter.vignette()
        vignetteFilter.inputImage = balanced
        vignetteFilter.intensity = Float(vignette)
        vignetteFilter.radius = Float(max(image.extent.width, image.extent.height) * 0.72)
        return vignetteFilter.outputImage ?? balanced
    }
}

struct SavedCameraLook: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var basePreset: CameraPreset
    var settings: CameraLookSettings
}

@MainActor
final class PhotoDocument: ObservableObject {
    @Published private(set) var sourceURL: URL?
    @Published private(set) var preview: UIImage?
    @Published private(set) var originalPreview: UIImage?
    @Published private(set) var sourceName = ""
    @Published private(set) var dimensions = ""
    @Published var preset: CameraPreset = .everyday
    @Published var lookSettings = CameraPreset.everyday.settings
    @Published private(set) var savedLooks: [SavedCameraLook] = []
    @Published private(set) var activeSavedLookName: String?
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private var metadata: [String: Any] = [:]
    private var previewRequestID = UUID()
    // Stable legacy key: retaining it preserves saved looks across the Canonvert rename.
    private let savedLooksKey = "Digify.savedCameraLooks.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: savedLooksKey),
           let looks = try? JSONDecoder().decode([SavedCameraLook].self, from: data) {
            savedLooks = looks
        }
    }

    func selectPreset(_ preset: CameraPreset) {
        self.preset = preset
        lookSettings = preset.settings
        activeSavedLookName = nil
    }

    func updateLookSettings(_ settings: CameraLookSettings) {
        lookSettings = settings
        activeSavedLookName = nil
    }

    func applySavedLook(_ look: SavedCameraLook) {
        preset = look.basePreset
        lookSettings = look.settings
        activeSavedLookName = look.name
    }

    func saveLook(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var saved = SavedCameraLook(name: name, basePreset: preset, settings: lookSettings)
        if let index = savedLooks.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            saved.id = savedLooks[index].id
            savedLooks[index] = saved
        } else {
            savedLooks.insert(saved, at: 0)
        }
        activeSavedLookName = name
        persistSavedLooks()
    }

    func deleteLook(_ look: SavedCameraLook) {
        savedLooks.removeAll { $0.id == look.id }
        if activeSavedLookName == look.name { activeSavedLookName = nil }
        persistSavedLooks()
    }

    private func persistSavedLooks() {
        guard let data = try? JSONEncoder().encode(savedLooks) else { return }
        UserDefaults.standard.set(data, forKey: savedLooksKey)
    }

    private struct Decoded {
        let url: URL
        let name: String
        let dimensions: String
        let metadata: [String: Any]
        let originalPreview: UIImage
        let preview: UIImage
    }

    nonisolated private static func sourceImage(at url: URL) -> CIImage? {
        if url.pathExtension.lowercased() == "dng" {
            return CIRAWFilter(imageURL: url)?.outputImage
        }
        return CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
    }

    func load(data: Data, name: String) async {
        do {
            let suffix = URL(fileURLWithPath: name).pathExtension
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("canonvert-\(UUID().uuidString).\(suffix.isEmpty ? "image" : suffix)")
            try await Task.detached(priority: .userInitiated) { try data.write(to: url, options: .atomic) }.value
            try await load(url: url)
        } catch { errorMessage = error.localizedDescription }
    }

    func load(url: URL) async throws {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer { if hasScopedAccess { url.stopAccessingSecurityScopedResource() } }
        let usableURL: URL
        if hasScopedAccess {
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("canonvert-source-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "image" : url.pathExtension)")
            try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: url, to: localURL) }.value
            usableURL = localURL
        } else {
            usableURL = url
        }
        let selectedSettings = lookSettings
        let decoded = try await Task.detached(priority: .userInitiated) {
            try Self.decode(url: usableURL, settings: selectedSettings)
        }.value
        sourceURL = decoded.url
        sourceName = decoded.name
        dimensions = decoded.dimensions
        metadata = decoded.metadata
        originalPreview = decoded.originalPreview
        preview = decoded.preview
        errorMessage = nil
    }

    nonisolated private static func decode(url: URL, settings: CameraLookSettings) throws -> Decoded {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let raw = Self.sourceImage(at: url) else {
            throw NSError(domain: "Canonvert", code: 1, userInfo: [NSLocalizedDescriptionKey: "This image could not be opened. Try a HEIC, JPEG, or DNG file."])
        }
        let metadata = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        let extent = raw.extent.integral
        let dimensions = "\(Int(extent.width)) × \(Int(extent.height))"
        let scale = min(1, 1400 / max(extent.width, extent.height))
        let proxy = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let originalPreview = render(proxy, maximumDimension: 1400),
              let preview = render(settings.apply(to: proxy), maximumDimension: 1400) else {
            throw NSError(domain: "Canonvert", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not create an image preview."])
        }
        return Decoded(url: url, name: url.deletingPathExtension().lastPathComponent, dimensions: dimensions, metadata: metadata, originalPreview: originalPreview, preview: preview)
    }

    func refreshPreview() async {
        guard let url = sourceURL else { return }
        let selectedSettings = lookSettings
        let requestID = UUID()
        previewRequestID = requestID
        let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = Self.sourceImage(at: url) else { return nil }
            let extent = image.extent.integral
            let scale = min(1, 1400 / max(extent.width, extent.height))
            let proxy = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            return Self.render(selectedSettings.apply(to: proxy), maximumDimension: 1400)
        }.value
        guard sourceURL == url, lookSettings == selectedSettings, previewRequestID == requestID else { return }
        preview = rendered
    }

    nonisolated private static func render(_ image: CIImage, maximumDimension: CGFloat) -> UIImage? {
        let extent = image.extent.integral
        guard !extent.isEmpty else { return nil }
        let ratio = min(1, maximumDimension / max(extent.width, extent.height))
        let output = ratio < 1 ? image.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio)) : image
        guard let cg = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func export(as type: UTType) async throws -> URL {
        guard let sourceURL else { throw NSError(domain: "Canonvert", code: 2, userInfo: [NSLocalizedDescriptionKey: "Select an image first."]) }
        isBusy = true
        defer { isBusy = false }
        let selectedSettings = lookSettings
        let sourceMetadata = metadata
        let input = try await Task.detached(priority: .userInitiated) { () throws -> (CGImage, [String: Any]) in
            guard let ci = Self.sourceImage(at: sourceURL),
                  let cg = CIContext(options: [.cacheIntermediates: false]).createCGImage(selectedSettings.apply(to: ci), from: ci.extent) else {
                throw NSError(domain: "Canonvert", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not render the full-resolution image."])
            }
            return (cg, sourceMetadata)
        }.value
        let ext = type == .heic ? "heic" : "jpg"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(sourceName)-Canonvert.\(ext)")
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, type.identifier as CFString, 1, nil) else {
            throw NSError(domain: "Canonvert", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create the export file."])
        }
        var properties = input.1
        properties[kCGImageDestinationLossyCompressionQuality as String] = 1.0
        properties[kCGImagePropertyOrientation as String] = 1
        properties[kCGImagePropertyTIFFDictionary as String] = {
            var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            tiff[kCGImagePropertyTIFFSoftware as String] = "Canonvert"
            return tiff
        }()
        CGImageDestinationAddImage(destination, input.0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Canonvert", code: 5, userInfo: [NSLocalizedDescriptionKey: "The image could not be saved."]) }
        return outputURL
    }

    func saveToPhotos(as type: UTType) async throws {
        let outputURL = try await export(as: type)
        isBusy = true
        defer { isBusy = false }
        do {
            var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if status == .notDetermined {
                status = await withCheckedContinuation { continuation in
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
                }
            }
            guard status == .authorized else {
                throw NSError(domain: "Canonvert", code: 7, userInfo: [NSLocalizedDescriptionKey: "Allow Canonvert to add photos in Settings to save this image to your Camera Roll."])
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: outputURL, options: nil)
                }) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: NSError(domain: "Canonvert", code: 8, userInfo: [NSLocalizedDescriptionKey: "Photos could not save the image. Please try again."]))
                    }
                }
            }
            try? FileManager.default.removeItem(at: outputURL)
            noticeMessage = "Saved at full resolution to your Camera Roll."
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
