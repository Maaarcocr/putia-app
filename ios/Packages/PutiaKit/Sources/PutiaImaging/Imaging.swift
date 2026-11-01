import CoreImage
import Foundation
import ImageIO
import PutiaCore
import Vision

/// A photo ready to upload.
public struct PreparedPhoto: Sendable {
    /// The photo itself, as JPEG, at most 2000 pixels on its long side.
    public let full: Data
    /// A small image for lists: the cut-out on a transparent background (PNG) when one was found,
    /// otherwise the photo scaled down (JPEG).
    public let thumb: Data
    public let thumbType: String
    public let hasCutout: Bool
    public let width: Int
    public let height: Int
    /// Dominant colours of the cut-out; empty without one, since a background would dominate.
    public let swatches: [Swatch]
    /// What Vision thinks the piece is, when that is clothing.
    public let category: ClothingCategory?
}

public enum ImagingError: Error {
    case unreadable
}

/// Cut-outs, thumbnails and colour measurement, all on the phone. Runs off the main actor.
public enum Imaging {
    /// - Parameter cutOut: lift the subject from its background (pieces), or keep the photo as it is
    ///   (mirror photos and inspiration).
    public static func prepare(_ data: Data, cutOut: Bool) async throws -> PreparedPhoto {
        guard let original = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw ImagingError.unreadable }
        let context = CIContext()
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let photo = scaled(original, toFit: 2000)
        guard let full = context.jpegRepresentation(
            of: photo, colorSpace: sRGB, options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.8]
        ) else { throw ImagingError.unreadable }

        let subject = cutOut ? foreground(of: photo) : nil
        let thumbImage = scaled(subject ?? photo, toFit: 600)
        let thumb: Data?
        if subject != nil {
            thumb = context.pngRepresentation(of: thumbImage, format: .RGBA8, colorSpace: sRGB)
        } else {
            thumb = context.jpegRepresentation(of: thumbImage, colorSpace: sRGB)
        }
        guard let thumb else { throw ImagingError.unreadable }

        return PreparedPhoto(
            full: full,
            thumb: thumb,
            thumbType: subject != nil ? "image/png" : "image/jpeg",
            hasCutout: subject != nil,
            width: Int(photo.extent.width.rounded()),
            height: Int(photo.extent.height.rounded()),
            swatches: subject.map { Swatches.dominant(rgba: pixels(of: $0, context: context)) } ?? [],
            category: cutOut ? category(of: photo) : nil
        )
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

    /// RGBA pixels of a small copy of the image, for measuring colours.
    private static func pixels(of image: CIImage, context: CIContext) -> [UInt8] {
        let small = scaled(image, toFit: 64)
        let width = Int(small.extent.width.rounded(.down)), height = Int(small.extent.height.rounded(.down))
        guard width > 0, height > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            small, toBitmap: &bytes, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes
    }

    /// Vision's labels that name clothing. Anything else suggests no category.
    static let categories: [String: ClothingCategory] = [
        "jacket": .jacket, "coat": .coat, "suit": .suit, "blazer": .jacket,
        "shirt": .shirt, "tshirt": .tshirt, "t_shirt": .tshirt, "sweater": .knitwear, "sweatshirt": .sweatshirt,
        "jeans": .jeans, "trousers": .trousers, "pants": .trousers, "shorts": .shorts,
        "shoes": .shoes, "sneaker": .shoes, "boot": .boots, "sandal": .shoes,
        "hat": .hat, "scarf": .scarf, "tie": .accessory, "belt": .accessory, "bag": .bag, "handbag": .bag, "backpack": .bag,
    ]

    private static func category(of image: CIImage) -> ClothingCategory? {
        let request = VNClassifyImageRequest()
        guard (try? VNImageRequestHandler(ciImage: image, options: [:]).perform([request])) != nil else { return nil }
        return (request.results ?? [])
            .filter { $0.confidence > 0.3 }
            .sorted { $0.confidence > $1.confidence }
            .lazy
            .compactMap { categories[$0.identifier] }
            .first
    }
}
