// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Picline",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Picline", targets: ["Tendedero"])],
    targets: [
        // Resources holds the translations. scripts/build-app.sh copies them
        // into the app, so SwiftPM leaves them alone.
        .executableTarget(name: "Tendedero", path: "Sources/Tendedero", exclude: ["Resources"]),
        .testTarget(name: "TendederoTests", dependencies: ["Tendedero"])
    ]
)
