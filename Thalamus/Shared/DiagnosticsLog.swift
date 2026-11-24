import Foundation

nonisolated struct DiagnosticsLog: Sendable {
    let url: URL
    var limit = 512 * 1024

    func write(_ lines: [String]) {
        let stamp = Date().formatted(.iso8601)
        let data = Data(lines.map { "\(stamp) \($0)\n" }.joined().utf8)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > limit { try? FileManager.default.removeItem(at: url) }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
