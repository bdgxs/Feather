import Foundation
import ZIPFoundation
import UIKit

enum FileOperationError: Error {
    case fileNotFound(String)
    case invalidDestination(String)
    case unknownError(String)
}

class FileOperations {

    static let fileManager = FileManager.default

    /// Copies a file from a source URL to a destination URL.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL of the file to copy.
    ///   - destinationURL: The URL to copy the file to.
    /// - Throws: An error if the file does not exist or if the copy operation fails.
    static func copyFile(at sourceURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FileOperationError.fileNotFound("Source file not found at \(sourceURL.path)")
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            print("File copied from \(sourceURL.path) to \(destinationURL.path)")
        } catch {
            throw FileOperationError.unknownError("Failed to copy file: \(error.localizedDescription)")
        }
    }

    /// Moves a file from a source URL to a destination URL.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL of the file to move.
    ///   - destinationURL: The URL to move the file to.
    /// - Throws: An error if the file does not exist or if the move operation fails.
    static func moveFile(at sourceURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FileOperationError.fileNotFound("Source file not found at \(sourceURL.path)")
        }
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            print("File moved from \(sourceURL.path) to \(destinationURL.path)")
        } catch {
            throw FileOperationError.unknownError("Failed to move file: \(error.localizedDescription)")
        }
    }

    /// Compresses a file at a given URL to a destination URL using ZIPFoundation.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of the file to compress.
    ///   - destinationURL: The URL where the ZIP archive should be created.
    /// - Throws: An error if the file does not exist or if the compression fails.
    static func compressFile(at fileURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw FileOperationError.fileNotFound("File not found at \(fileURL.path)")
        }
        do {
            try fileManager.zipItem(at: fileURL, to: destinationURL)
            print("File compressed from \(fileURL.path) to \(destinationURL.path)")
        } catch {
            throw FileOperationError.unknownError("Failed to compress file: \(error.localizedDescription)")
        }
    }

    /// Deletes a file at the specified URL.
    ///
    /// - Parameter fileURL: The URL of the file to delete.
    /// - Throws: An error if the file does not exist or if the deletion fails.
    static func deleteFile(at fileURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw FileOperationError.fileNotFound("File not found at \(fileURL.path)")
        }
        do {
            try fileManager.removeItem(at: fileURL)
            print("File deleted at \(fileURL.path)")
        } catch {
            throw FileOperationError.unknownError("Failed to delete file: \(error.localizedDescription)")
        }
    }

    /// Unzips a file at a given URL to a destination URL using ZIPFoundation.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of the ZIP archive to extract.
    ///   - destinationURL: The URL where the contents of the archive should be extracted.
    /// - Throws: An error if the file does not exist or if the extraction fails.
    static func unzipFile(at fileURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw FileOperationError.fileNotFound("File not found at \(fileURL.path)")
        }
        do {
            let archive = try Archive(url: fileURL, accessMode: .read)
            for entry in archive {
                let destination = destinationURL.appendingPathComponent(entry.path)
                if entry.type == .directory {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
                } else {
                    _ = try archive.extract(entry, to: destination)
                }
            }
            print("File unzipped from \(fileURL.path) to \(destinationURL.path)")
        } catch {
            throw FileOperationError.unknownError("Failed to unzip file: \(error.localizedDescription)")
        }
    }

    /// Presents a Hex Editor View Controller for editing the file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of the file to be edited.
    ///   - viewController: The view controller to present the Hex Editor from.
    static func hexEditFile(at fileURL: URL, in viewController: UIViewController) {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("File not found at \(fileURL.path)")
            return
        }

        let hexEditorViewController = HexEditorViewController(fileURL: fileURL)
        viewController.present(hexEditorViewController, animated: true, completion: nil)
    }
}