import Foundation

actor TakeStore {
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "TRACE/Takes", directoryHint: .isDirectory)
    }
    func load() throws -> [MotionTake] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> MotionTake? in
                guard let data = try? Data(contentsOf: url), data.count < 25_000_000,
                      let take = try? JSONDecoder().decode(MotionTake.self, from: data), take.isValid else { return nil }
                return take
            }.sorted { $0.createdAt > $1.createdAt }
    }
    func save(_ take: MotionTake) throws {
        guard take.isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(take).write(to: directory.appending(path: "\(take.id.uuidString).json"), options: .atomic)
    }
    func delete(_ take: MotionTake) throws {
        try FileManager.default.removeItem(at: directory.appending(path: "\(take.id.uuidString).json"))
    }
}
