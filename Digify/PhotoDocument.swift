import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Combine

enum CameraPreset: String, CaseIterable, Identifiable, Sendable {
    case everyday = "Everyday", flash = "Flash", night = "Night"
    var id: String { rawValue }

    func apply(to image: CIImage) -> CIImage {
        // The reference compact camera renders bright, punchy JPEGs with warm skin,
        // crisp detail, visible flash pop, and lifted night shadows.
        let color = CIFilter.colorControls()
        color.inputImage = image
        switch self {
        case .everyday:
            color.saturation = 1.10; color.contrast = 1.055; color.brightness = 0.006
        case .flash:
            color.saturation = 1.18; color.contrast = 1.12; color.brightness = 0.018
        case .night:
            color.saturation = 1.08; color.contrast = 1.025; color.brightness = 0.028
        }
        guard let controlled = color.outputImage else { return image }

        let balance = CIFilter.temperatureAndTint()
        balance.inputImage = controlled
        balance.neutral = CIVector(x: 6500, y: 0)
        balance.targetNeutral = CIVector(x: self == .flash ? 6100 : 6300, y: 0)
        let warmed = balance.outputImage ?? controlled

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = warmed
        sharpen.sharpness = self == .flash ? 0.32 : 0.22
        let detailed = sharpen.outputImage ?? warmed
        let shadows = CIFilter.highlightShadowAdjust()
        shadows.inputImage = detailed
        shadows.shadowAmount = self == .night ? 0.72 : (self == .flash ? 0.30 : 0.48)
        shadows.highlightAmount = self == .flash ? 0.82 : 0.92
        let balanced = shadows.outputImage ?? detailed
        let vignette = CIFilter.vignette()
        vignette.inputImage = balanced
        vignette.intensity = self == .night ? 0.20 : 0.10
        vignette.radius = Float(max(image.extent.width, image.extent.height) * 0.72)
        return vignette.outputImage ?? balanced
    }
}

@MainActor
final class PhotoDocument: ObservableObject {
    @Published private(set) var sourceURL: URL?
    @Published private(set) var preview: UIImage?
    @Published private(set) var originalPreview: UIImage?
    @Published private(set) var sourceName = ""
    @Published private(set) var dimensions = ""
    @Published var preset: CameraPreset = .everyday
    @Published var isBusy = false
    @Published var errorMessage: String?

    private var metadata: [String: Any] = [:]

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
                .appendingPathComponent("digify-\(UUID().uuidString).\(suffix.isEmpty ? "image" : suffix)")
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
                .appendingPathComponent("digify-source-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "image" : url.pathExtension)")
            try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: url, to: localURL) }.value
            usableURL = localURL
        } else {
            usableURL = url
        }
        let selectedPreset = preset
        let decoded = try await Task.detached(priority: .userInitiated) {
            try Self.decode(url: usableURL, preset: selectedPreset)
        }.value
        sourceURL = decoded.url
        sourceName = decoded.name
        dimensions = decoded.dimensions
        metadata = decoded.metadata
        originalPreview = decoded.originalPreview
        preview = decoded.preview
        errorMessage = nil
    }

    nonisolated private static func decode(url: URL, preset: CameraPreset) throws -> Decoded {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let raw = Self.sourceImage(at: url) else {
            throw NSError(domain: "Digify", code: 1, userInfo: [NSLocalizedDescriptionKey: "This image could not be opened. Try a HEIC, JPEG, or DNG file."])
        }
        let metadata = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        let extent = raw.extent.integral
        let dimensions = "\(Int(extent.width)) × \(Int(extent.height))"
        let scale = min(1, 1400 / max(extent.width, extent.height))
        let proxy = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let originalPreview = render(proxy, maximumDimension: 1400),
              let preview = render(preset.apply(to: proxy), maximumDimension: 1400) else {
            throw NSError(domain: "Digify", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not create an image preview."])
        }
        return Decoded(url: url, name: url.deletingPathExtension().lastPathComponent, dimensions: dimensions, metadata: metadata, originalPreview: originalPreview, preview: preview)
    }

    func refreshPreview() async {
        guard let url = sourceURL else { return }
        let selectedPreset = preset
        let rendered = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = Self.sourceImage(at: url) else { return nil }
            let extent = image.extent.integral
            let scale = min(1, 1400 / max(extent.width, extent.height))
            let proxy = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            return Self.render(selectedPreset.apply(to: proxy), maximumDimension: 1400)
        }.value
        guard sourceURL == url, preset == selectedPreset else { return }
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
        guard let sourceURL else { throw NSError(domain: "Digify", code: 2, userInfo: [NSLocalizedDescriptionKey: "Select an image first."]) }
        isBusy = true
        defer { isBusy = false }
        let selectedPreset = preset
        let sourceMetadata = metadata
        let input = try await Task.detached(priority: .userInitiated) { () throws -> (CGImage, [String: Any]) in
            guard let ci = Self.sourceImage(at: sourceURL),
                  let cg = CIContext(options: [.cacheIntermediates: false]).createCGImage(selectedPreset.apply(to: ci), from: ci.extent) else {
                throw NSError(domain: "Digify", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not render the full-resolution image."])
            }
            return (cg, sourceMetadata)
        }.value
        let ext = type == .heic ? "heic" : "jpg"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(sourceName)-Digify.\(ext)")
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, type.identifier as CFString, 1, nil) else {
            throw NSError(domain: "Digify", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create the export file."])
        }
        var properties = input.1
        properties[kCGImageDestinationLossyCompressionQuality as String] = 1.0
        properties[kCGImagePropertyOrientation as String] = 1
        properties[kCGImagePropertyTIFFDictionary as String] = {
            var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            tiff[kCGImagePropertyTIFFSoftware as String] = "Digify"
            return tiff
        }()
        CGImageDestinationAddImage(destination, input.0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Digify", code: 5, userInfo: [NSLocalizedDescriptionKey: "The image could not be saved."]) }
        return outputURL
    }
}
