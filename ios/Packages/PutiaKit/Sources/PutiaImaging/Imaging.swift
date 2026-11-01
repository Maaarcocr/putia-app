import CoreImage
import Foundation
import ImageIO
import Vision

/// A photo ready to upload.
public struct PreparedPhoto: Sendable {
    /// The photo itself, as JPEG, at most 2000 pixels on its long side.
    public let full: Data
    /// A small image for lists: the cut-out on a transparent background (PNG) when one was asked
    /// for and found, otherwise the photo scaled down (JPEG).
    public let thumb: Data
    public let thumbType: String
}

public enum ImagingError: Error {
    case unreadable
}

/// Cut-outs and thumbnails, on the phone.
public enum Imaging {
    /// - Parameter cutOut: lift the subject from its background (a new piece), or keep the photo
    ///   as it is.
    public static func prepare(_ data: Data, cutOut: Bool) async throws -> PreparedPhoto {
        guard let original = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw ImagingError.unreadable }
        let context = CIContext()
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let photo = scaled(original, toFit: 2000)
        guard let full = context.jpegRepresentation(
            of: photo, colorSpace: sRGB, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.8]
        ) else { throw ImagingError.unreadable }

        if cutOut, let subject = foreground(of: photo),
           let thumb = context.pngRepresentation(of: scaled(subject, toFit: 600), format: .RGBA8, colorSpace: sRGB) {
            return PreparedPhoto(full: full, thumb: thumb, thumbType: "image/png")
        }
        guard let thumb = context.jpegRepresentation(of: scaled(photo, toFit: 600), colorSpace: sRGB) else { throw ImagingError.unreadable }
        return PreparedPhoto(full: full, thumb: thumb, thumbType: "image/jpeg")
    }

    /// The image scaled down (never up) so its long side is at most `side`, with its origin at zero.
    static func scaled(_ image: CIImage, toFit side: CGFloat) -> CIImage {
        let scale = min(1, side / max(image.extent.width, image.extent.height))
        return image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// The photo's subject on a transparent background, cropped to it; nil when Vision finds none.
    private static func foreground(of image: CIImage) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first,
              let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
        else { return nil }
        return CIImage(cvPixelBuffer: buffer)
    }
}
