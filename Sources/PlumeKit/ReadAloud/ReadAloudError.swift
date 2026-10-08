import Foundation

public enum ReadAloudError: LocalizedError, Equatable {
    case nothingToRead
    case voiceNotInstalled
    case engineNotInstalled
    case unknownEngine
    case noChatTemplate
    case unsupportedTemplate
    case loadFailed
    case decodeFailed
    case inputTooLong
    case emptySummary
    case downloadRunning
    case notEnoughSpace(neededBytes: Int64)
    case checksumMismatch
    case httpStatus(Int)
    case evalNeedsTwoEngines
    case evalNoSelections
    case evalOutRequired
    case evalOutInsideRepository

    public var errorDescription: String? {
        switch self {
        case .nothingToRead: return tr("Select some text first.")
        case .voiceNotInstalled:
            return tr("The voice is not installed. Download it in Settings › Local AI, or run: plume read-aloud --download voice")
        case .engineNotInstalled:
            return tr("No summary model is in use. Download one in Settings › Local AI, or run: plume read-aloud --download <model>")
        case .unknownEngine: return tr("Unknown summary model.")
        case .noChatTemplate: return tr("This model has no chat template.")
        case .unsupportedTemplate: return tr("Unsupported chat template.")
        case .loadFailed: return tr("The summary model could not be loaded.")
        case .decodeFailed: return tr("The summary model failed while writing.")
        case .inputTooLong: return tr("The selection is too long to summarize.")
        case .emptySummary: return tr("Couldn't summarize this text.")
        case .downloadRunning: return tr("A download is already running.")
        case .notEnoughSpace(let bytes):
            return tr("Not enough free space:") + " " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        case .checksumMismatch: return tr("The downloaded file is damaged. Try again.")
        case .httpStatus(let code): return tr("Download failed, HTTP status") + " \(code)"
        case .evalNeedsTwoEngines: return tr("The eval compares exactly two different models: --engines a,b")
        case .evalNoSelections: return tr("The eval folder has no .txt files.")
        case .evalOutRequired: return tr("Give the results file with --out, in your eval folder.")
        case .evalOutInsideRepository:
            return tr("The results hold your texts, so they must not be written inside a Git repository. Use a file in your eval folder.")
        }
    }
}
