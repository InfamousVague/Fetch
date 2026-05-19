// swift-tools-version: 5.9
import PackageDescription

// Homebrew prefixes (Apple Silicon). openssl@3 is keg-only.
let brew = "/opt/homebrew"
let ssl  = "/opt/homebrew/opt/openssl@3"

let package = Package(
    name: "Fetch",
    platforms: [.macOS(.v14)],
    targets: [
        // C++ shim exposing a flat C API over libtorrent 2.0.
        .target(
            name: "CFetchEngine",
            path: "Sources/CFetchEngine",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-std=c++17",
                    "-I\(brew)/include",
                    "-I\(ssl)/include",
                ])
            ]
        ),
        .executableTarget(
            name: "Fetch",
            dependencies: ["CFetchEngine"],
            path: "Sources/Fetch",
            linkerSettings: [
                .unsafeFlags([
                    "-L\(brew)/lib", "-ltorrent-rasterbar",
                    "-L\(ssl)/lib", "-lssl", "-lcrypto",
                    "-lc++",
                ])
            ]
        ),
        .executableTarget(
            name: "FetchSelftest",
            dependencies: ["CFetchEngine"],
            path: "Sources/FetchSelftest",
            linkerSettings: [
                .unsafeFlags([
                    "-L\(brew)/lib", "-ltorrent-rasterbar",
                    "-L\(ssl)/lib", "-lssl", "-lcrypto",
                    "-lc++",
                ])
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
