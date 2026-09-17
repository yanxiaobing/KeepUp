// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeepUpPersistenceSpike",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "PersistenceSpike", targets: ["PersistenceSpike"])],
    dependencies: [
        .package(url: "https://github.com/Tencent/wcdb.git", exact: "2.1.16")
    ],
    targets: [
        .target(name: "PersistenceSpike", dependencies: [
            .product(name: "WCDBSwift", package: "wcdb")
        ]),
        .testTarget(name: "PersistenceSpikeTests", dependencies: ["PersistenceSpike"])
    ],
    swiftLanguageModes: [.v6]
)
