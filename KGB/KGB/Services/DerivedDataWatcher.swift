import Foundation

final class DerivedDataWatcher {
    private var stream: FSEventStreamRef?
    private let callback: @Sendable (String) -> Void
    private let watchPath: String

    /// - Parameters:
    ///   - path: DerivedData directory to watch
    ///   - callback: Called with the full path to each new .xcresult bundle or .xcactivitylog file
    init(path: String, callback: @escaping @Sendable (String) -> Void) {
        self.watchPath = path
        self.callback = callback
    }

    func start() {
        var context = FSEventStreamContext()
        context.info = Unmanaged.passRetained(self).toOpaque()

        let paths = [watchPath] as CFArray
        stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info else { return }
                let watcher = Unmanaged<DerivedDataWatcher>.fromOpaque(info)
                    .takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths)
                    .takeUnretainedValue() as! [String]
                for i in 0..<numEvents {
                    if let result = watcher.buildArtifactPath(from: paths[i]) {
                        watcher.callback(result)
                    }
                }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // 1 second latency
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes
            )
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    /// Returns the normalized path if it refers to an `.xcresult` bundle or `.xcactivitylog` file, or `nil` otherwise.
    func buildArtifactPath(from eventPath: String) -> String? {
        if eventPath.hasSuffix(".xcresult") || eventPath.hasSuffix(".xcresult/") {
            return eventPath.hasSuffix("/") ? String(eventPath.dropLast()) : eventPath
        }
        if eventPath.hasSuffix(".xcactivitylog") {
            return eventPath
        }
        return nil
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
