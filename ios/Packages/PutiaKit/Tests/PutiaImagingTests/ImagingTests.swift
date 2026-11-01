import CoreImage
import Foundation
@testable import PutiaImaging
import Testing

private func png(width: Int, height: Int) throws -> Data {
    let image = CIImage(color: CIColor(red: 0.12, green: 0.16, blue: 0.27)).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(CIContext().pngRepresentation(of: image, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
}

@Test func keepsAPhotoAsItIs() async throws {
    let prepared = try await Imaging.prepare(try png(width: 3000, height: 1500), cutOut: false)
    #expect(prepared.thumbType == "image/jpeg")
    #expect(!prepared.full.isEmpty && !prepared.thumb.isEmpty)
}

@Test func scalesDownButNeverUp() throws {
    let large = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 3000, height: 1500))
    #expect(Imaging.scaled(large, toFit: 2000).extent.width.rounded() == 2000)
    let small = CIImage(color: .white).cropped(to: CGRect(x: 10, y: 10, width: 300, height: 200))
    #expect(Imaging.scaled(small, toFit: 600).extent == CGRect(x: 0, y: 0, width: 300, height: 200))
}

@Test func refusesSomethingThatIsNotAnImage() async {
    await #expect(throws: ImagingError.self) {
        try await Imaging.prepare(Data("not an image".utf8), cutOut: true)
    }
}
