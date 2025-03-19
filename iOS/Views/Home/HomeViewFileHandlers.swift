import UIKit
import ZIPFoundation
import os.log
import Foundation

protocol FileHandlingDelegate: AnyObject {
    var documentsDirectory: URL { get }
    var activityIndicator: UIActivityIndicatorView { get }
    func loadFiles()
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
}

class HomeViewFileHandlers {
    private let fileManager = FileManager.default
    private let utilities = HomeViewUtilities()

    func uploadFile(viewController: FileHandlingDelegate) {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        documentPicker.delegate = viewController as? UIDocumentPickerDelegate
        documentPicker.modalPresentationStyle = .formSheet
        viewController.present(documentPicker, animated: true, completion: nil)
    }

    func importFile(viewController: FileHandlingDelegate) {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        documentPicker.delegate = viewController as? UIDocumentPickerDelegate
        documentPicker.modalPresentationStyle = .formSheet
        viewController.present(documentPicker, animated: true, completion: nil)
    }

    func createNewFolder(viewController: FileHandlingDelegate, folderName: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let folderURL = viewController.documentsDirectory.appendingPathComponent(folderName)
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            viewController.loadFiles()
            completion(.success(folderURL))
        } catch {
            utilities.handleError(in: viewController as! UIViewController, error: error, withTitle: "Creating Folder")
            completion(.failure(error))
        }
    }

    func createNewFile(viewController: FileHandlingDelegate, fileName: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let fileURL = viewController.documentsDirectory.appendingPathComponent(fileName)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
            viewController.loadFiles()
            completion(.success(fileURL))
        } else {
            let error = NSError(domain: "FileExists", code: 1, userInfo: [NSLocalizedDescriptionKey: "File already exists"])
            utilities.handleError(in: viewController as! UIViewController, error: error, withTitle: "Creating File")
            completion(.failure(error))
        }
    }

    func renameFile(viewController: FileHandlingDelegate, fileURL: URL, newName: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let destinationURL = fileURL.deletingLastPathComponent().appendingPathComponent(newName)
        viewController.activityIndicator.startAnimating()
        let workItem = DispatchWorkItem {
            do {
                try self.fileManager.moveItem(at: fileURL, to: destinationURL)
                DispatchQueue.main.async {
                    viewController.activityIndicator.stopAnimating()
                    viewController.loadFiles()
                    completion(.success(destinationURL))
                }
            } catch {
                DispatchQueue.main.async {
                    viewController.activityIndicator.stopAnimating()
                    self.utilities.handleError(in: viewController as! UIViewController, error: error, withTitle: "Renaming File")
                    completion(.failure(error))
                }
            }
        }
        DispatchQueue.global().async(execute: workItem)
    }

    func deleteFile(viewController: FileHandlingDelegate, fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        viewController.activityIndicator.startAnimating()
        let workItem = DispatchWorkItem {
            do {
                try self.fileManager.removeItem(at: fileURL)
                DispatchQueue.main.async {
                    viewController.activityIndicator.stopAnimating()
                    viewController.loadFiles()
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async {
                    viewController.activityIndicator.stopAnimating()
                    self.utilities.handleError(in: viewController as! UIViewController, error: error, withTitle: "Deleting File")
                    completion(.failure(error))
                }
            }
        }
        DispatchQueue.global().async(execute: workItem)
    }

    func unzipFile(viewController: FileHandlingDelegate, fileURL: URL, destinationName: String, progressHandler: ((Double) -> Void)? = nil, completion: @escaping (Result<URL, Error>) -> Void) {
        let destinationURL = fileURL.deletingLastPathComponent().appendingPathComponent(destinationName)
        viewController.activityIndicator.startAnimating()
        let workItem = DispatchWorkItem {
            do {
                let progress = Progress(totalUnitCount: 100)
                progress.cancellationHandler = {
                    print("Unzip cancelled")
                }
                try self.fileManager.unzipItem(at: fileURL, to: destinationURL, progress: progress)
                progressHandler?(1.0)
                DispatchQueue.main.async {
                    viewController.activityIndicator.stopAnimating()
                    viewController.loadFiles()
                    completion(.success(destinationURL))
                }
            } catch {
                DispatchQueue.main.async {
                    viewController.activityIndicator.stopAnimating()
                    self.utilities.handleError(in: viewController as! UIViewController, error: error, withTitle: "Unzipping File")
                    completion(.failure(error))
                }
            }
        }
        DispatchQueue.global().async(execute: workItem)
    }

    func shareFile(viewController: UIViewController, fileURL: URL) {
        let activityController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        viewController.present(activityController, animated: true, completion: nil)
    }
}