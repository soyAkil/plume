// Sources/Plume/ReadAloudEvalCommand.swift
import Foundation
import PlumeKit

/// `plume read-aloud --eval <folder> --engines a,b --out results.json`.
enum ReadAloudEvalCommand {
    static func run(_ options: ReadAloudCommand.Options, folder: String, context: ReadAloudCommand.Context, emit: (String) -> Void) async throws -> Int32 {
        // Everything is checked before any model loads: a run takes long and holds the owner's texts.
        guard Set(options.evalEngines).count == 2, options.evalEngines.count == 2 else { throw ReadAloudError.evalNeedsTwoEngines }
        guard let outPath = options.evalOut else { throw ReadAloudError.evalOutRequired }
        let out = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
        guard !isInsideGitWorkTree(out) else { throw ReadAloudError.evalOutInsideRepository }
        let directory = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".txt") }.sorted()
        guard !names.isEmpty else { throw ReadAloudError.evalNoSelections }
        let files = try names.map { ($0, try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)) }
        let engines = try options.evalEngines.map { id -> (entry: SummaryEngineEntry, service: any SummaryService) in
            guard let entry = SummaryEngineCatalog.entry(id: id, in: context.catalog) else { throw ReadAloudError.unknownEngine }
            guard context.models.isInstalled(entry) else { throw ReadAloudError.engineNotInstalled }
            return (entry, context.summaryService(entry, context.models.modelURL(for: entry)))
        }
        let results = await ReadAloudEval.run(
            files: files, engines: engines, options: ReadAloudEval.options, interface: context.interface, created: Date(),
            progress: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(results).write(to: out, options: .atomic)
        emit(out.path)
        return 0
    }

    /// The results file holds every source text: a `.git` above its folder (a directory, or a
    /// file in a linked worktree) means it could be committed by accident.
    static func isInsideGitWorkTree(_ file: URL) -> Bool {
        var folder = file.deletingLastPathComponent().standardizedFileURL
        // Resolve symlinks on the part that exists (/tmp, /var), so the walk sees the real tree.
        var existing = folder
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" { existing.deleteLastPathComponent() }
        let resolved = existing.resolvingSymlinksInPath()
        folder = URL(fileURLWithPath: resolved.path + folder.path.dropFirst(existing.path.count))
        while true {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) { return true }
            if folder.path == "/" { return false }
            folder.deleteLastPathComponent()
        }
    }
}
