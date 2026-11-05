import Foundation

/// Signed DEBUG inspection copies can opt into the same isolated fixtures as
/// command-line/UI tests. Release always uses the process's actual arguments.
enum FoldDevelopmentArguments {
    static var current: [String] {
        #if DEBUG && targetEnvironment(macCatalyst)
        if Bundle.main.bundleIdentifier?.hasSuffix(".inspection") == true,
           let fixture = Bundle.main.object(forInfoDictionaryKey: "FoldDevelopmentArguments") as? [String] {
            return ProcessInfo.processInfo.arguments + fixture
        }
        #endif
        return ProcessInfo.processInfo.arguments
    }
}
