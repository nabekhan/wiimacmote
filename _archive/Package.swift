// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WiimoteGamepad",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WiimoteGamepadCLI", targets: ["WiimoteGamepadCLI"])
    ],
    targets: [
        .target(
            name: "CIOHIDUserDevice",
            path: "Sources/CIOHIDUserDevice",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "WiimoteGamepadCLI",
            dependencies: ["CIOHIDUserDevice"],
            path: "Sources/WiimoteGamepadCLI"
        )
    ]
)
