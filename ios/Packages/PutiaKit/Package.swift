// swift-tools-version: 6.2
import PackageDescription

// PutiaCore is pure Swift (Foundation only) and also builds and tests on Linux.
// PutiaImaging needs Vision and Core Image, so it exists only on Apple platforms.
var products: [Product] = [
    .library(name: "PutiaCore", targets: ["PutiaCore"]),
]
var targets: [Target] = [
    .target(name: "PutiaCore"),
    .testTarget(name: "PutiaCoreTests", dependencies: ["PutiaCore"]),
]

#if !os(Linux)
products.append(.library(name: "PutiaImaging", targets: ["PutiaImaging"]))
targets.append(.target(name: "PutiaImaging"))
targets.append(.testTarget(name: "PutiaImagingTests", dependencies: ["PutiaImaging"]))
#endif

let package = Package(
    name: "PutiaKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
