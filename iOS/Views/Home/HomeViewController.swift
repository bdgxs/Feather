import UIKit
import ZIPFoundation
import Foundation
import os.log
import UniformTypeIdentifiers
import PDFKit
import MobileCoreServices
import Nuke
import NukeUI

// MARK: - Protocols

protocol FileHandlingDelegate: AnyObject {
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
    func loadFiles()
    var documentsDirectory: URL { get }
}

class HomeViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating, UIDocumentPickerDelegate, UIDropInteractionDelegate, UIDocumentInteractionControllerDelegate {
    
    // MARK: - Properties

    private var fileList: [String] = []
    private var filteredFileList: [String] = []
    private let fileManager = FileManager.default
    private let searchController = UISearchController(searchResultsController: nil)
    private var sortOrder: SortOrder = .name
    private var currentDirectoryURL: URL!

    var documentsDirectory: URL {
        if let currentDirectoryURL = currentDirectoryURL {
            return currentDirectoryURL
        } else {
            let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("files")
            createFilesDirectoryIfNeeded(at: directory)
            return directory
        }
    }

    enum SortOrder {
        case name, date, size
    }

    let fileListTableView = UITableView()
    let activityIndicator = UIActivityIndicatorView(style: .large)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupActivityIndicator()
        loadFiles()
        configureTableView()
        setupDragAndDrop()
    }

    init(directoryURL: URL? = nil) {
        super.init(nibName: nil, bundle: nil)
        self.currentDirectoryURL = directoryURL
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        let navItem = UINavigationItem(title: currentDirectoryURL?.lastPathComponent ?? "Files")
        let menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(showMenu))
        let uploadButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(importFile))
        let addButton = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"), style: .plain, target: self, action: #selector(addDirectory))
        navItem.rightBarButtonItems = [menuButton, uploadButton, addButton]

        if currentDirectoryURL != documentsDirectory {
            let backButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(goBack))
            navItem.leftBarButtonItem = backButton
        }

        navigationController?.navigationBar.setItems([navItem], animated: false)
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - File Operations

    func loadFiles() {
        activityIndicator.startAnimating()
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            do {
                let files = try self.fileManager.contentsOfDirectory(at: self.documentsDirectory, includingPropertiesForKeys: nil)
                let sortedFiles = self.sortFiles(files, by: self.sortOrder)
                self.fileList = sortedFiles.map { $0.lastPathComponent }
                DispatchQueue.main.async {
                    self.filteredFileList = self.fileList
                    self.fileListTableView.reloadData()
                    self.activityIndicator.stopAnimating()
                }
            } catch {
                DispatchQueue.main.async {
                    self.handleError(error: error, withTitle: "Error Loading Files")
                    self.activityIndicator.stopAnimating()
                }
            }
        }
    }

    @objc private func importFile() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        present(documentPicker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let destinationURL = copyPickedFiles(urls: urls, to: documentsDirectory) else { return }
        self.loadFiles()
    }

    @objc private func addDirectory() {
        presentTextInputAlert(title: "Create Directory", message: "Enter the name for the new directory:", textFieldPlaceholder: "Directory Name") { directoryName in
            guard let directoryName = directoryName, !directoryName.isEmpty else { return }
            let newDirectoryURL = self.documentsDirectory.appendingPathComponent(directoryName)
            do {
                try self.fileManager.createDirectory(at: newDirectoryURL, withIntermediateDirectories: false, attributes: nil)
                self.loadFiles()
            } catch {
                self.handleError(error: error, withTitle: "Directory Creation Failed")
            }
        }
    }

    // MARK: - UI Actions

    @objc private func showMenu() {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let sortByNameAction = UIAlertAction(title: "Sort by Name", style: .default) { [weak self] _ in
            self?.sortOrder = .name
            self?.loadFiles()
        }
        let sortByDateAction = UIAlertAction(title: "Sort by Date", style: .default) { [weak self] _ in
            self?.sortOrder = .date
            self?.loadFiles()
        }
        let sortBySizeAction = UIAlertAction(title: "Sort by Size", style: .default) { [weak self] _ in
            self?.sortOrder = .size
            self?.loadFiles()
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(sortByNameAction)
        alertController.addAction(sortByDateAction)
        alertController.addAction(sortBySizeAction)
        alertController.addAction(cancelAction)
        present(alertController, animated: true, completion: nil)
    }

    // MARK: - Table View Configuration

    private func configureTableView() {
        fileListTableView.delegate = self
        fileListTableView.dataSource = self
        fileListTableView.register(UITableViewCell.self, forCellReuseIdentifier: "fileCell")
        fileListTableView.frame = view.bounds
        fileListTableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(fileListTableView)
        setupSearchController()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredFileList.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "fileCell", for: indexPath)
        cell.textLabel?.text = filteredFileList[indexPath.row]
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let fileName = filteredFileList[indexPath.row]
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        presentFileActionSheet(for: fileURL)
    }

    private func presentFileActionSheet(for fileURL: URL) {
        let isDirectory = isDirectory(at: fileURL)
        let title = fileURL.lastPathComponent
        let message = isDirectory ? "Directory Options" : "File Options"
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)

        if isDirectory {
            alertController.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
                self?.openDirectory(at: fileURL)
            })
        } else {
            // File options
            alertController.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
                self?.openFile(at: fileURL)
            })
            alertController.addAction(UIAlertAction(title: "View", style: .default) { [weak self] _ in
                self?.viewFile(at: fileURL)
            })
            alertController.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
                self?.renameFile(at: fileURL)
            })
            alertController.addAction(UIAlertAction(title: "Get Info", style: .default) { [weak self] _ in
                self?.getFileInfo(at: fileURL)
            })
        }

        alertController.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
            self?.shareFile(at: fileURL)
        })

        alertController.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteFile(at: fileURL)
        })

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        present(alertController, animated: true, completion: nil)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let fileName = filteredFileList[indexPath.row]
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            deleteFile(at: fileURL)
        }
    }

    // MARK: - Search Controller Setup

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Files"
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    func updateSearchResults(for searchController: UISearchController) {
        filterContentForSearchText(searchController.searchBar.text!)
    }

    private func filterContentForSearchText(_ searchText: String) {
        if searchText.isEmpty {
            filteredFileList = fileList
        } else {
            filteredFileList = fileList.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
        fileListTableView.reloadData()
    }

    // MARK: - Drag and Drop

    func setupDragAndDrop() {
        let dropInteraction = UIDropInteraction(delegate: self)
        view.addInteraction(dropInteraction)
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: URL.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard session.items.count == 1 else {
            presentAlert(title: "Multiple Items", message: "Only one item can be dropped at a time.")
            return
        }

        let item = session.items.first!
        item.itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, completionHandler: { (object, error) in
            if let url = object as? URL {
                DispatchQueue.main.async {
                    self.handleDroppedURL(url)
                }
            } else if error != nil {
                DispatchQueue.main.async {
                    self.presentAlert(title: "Error", message: "Failed to load dropped item.")
                }
            }
        })
    }

    private func handleDroppedURL(_ url: URL) {
        let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            // Check if file exists using FileManager.default.fileExists(atPath:)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                presentTextInputAlert(title: "File Exists", message: "A file with the same name already exists. Please enter a new name:", textFieldPlaceholder: "New Name") { newName in
                    guard let newName = newName, !newName.isEmpty else { return }
                    let newDestinationURL = self.documentsDirectory.appendingPathComponent(newName)
                    self.copyOrMoveItem(at: url, to: newDestinationURL)
                }
            } else {
                copyOrMoveItem(at: url, to: destinationURL)
            }
        }
    }

    private func copyOrMoveItem(at sourceURL: URL, to destinationURL: URL) {
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            loadFiles()
        } catch {
            handleError(error: error, withTitle: "Error Copying File")
        }
    }

    // MARK: - File Handling

    func createFilesDirectoryIfNeeded(at directory: URL) {
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                os_log("Error creating directory: %{public}@", log: OSLog.default, type: .error, error.localizedDescription)
            }
        }
    }

    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        } else {
            return false
        }
    }

    func getThumbnail(for url: URL) -> UIImage {
        let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, url.pathExtension as CFString, nil)?.takeRetainedValue()

        var systemIcon: UIImage
        if uti != nil {
            systemIcon = UIImage(systemName: "doc")! // Default document icon
            if UTTypeConformsTo(uti!, kUTTypeImage) {
                systemIcon = UIImage(systemName: "photo")!
            } else if UTTypeConformsTo(uti!, kUTTypeMovie) {
                systemIcon = UIImage(systemName: "film")!
            } else if UTTypeConformsTo(uti!, kUTTypeAudio) {
                systemIcon = UIImage(systemName: "music.note")!
            } else if UTTypeConformsTo(uti!, kUTTypeText) {
                systemIcon = UIImage(systemName: "doc.plaintext")!
            } else if UTTypeConformsTo(uti!, kUTTypeDirectory) {
                systemIcon = UIImage(systemName: "folder")!
            } else if UTTypeConformsTo(uti!, kUTTypePDF) {
                systemIcon = UIImage(systemName: "doc.pdf")!
            } else if UTTypeConformsTo(uti!, kUTTypeArchive) {
                systemIcon = UIImage(systemName: "archivebox")!
            }
        } else {
            systemIcon = UIImage(systemName: "questionmark.circle")! // Unknown file type icon
        }
        return systemIcon
    }

    func openDirectory(at directoryURL: URL) {
        let newViewController = HomeViewController(directoryURL: directoryURL)
        navigationController?.pushViewController(newViewController, animated: true)
    }

    func openFile(at fileURL: URL) {
        // Determine file type and open accordingly
        let fileType = UTType(filenameExtension: fileURL.pathExtension)

        if fileType == UTType.pdf {
            viewPDF(at: fileURL)
        } else if fileType == UTType.zip {
            viewZipContents(at: fileURL)
        } else if fileType == UTType("public.archive" as CFString) { // General archive type
            viewZipContents(at: fileURL) // Treat other archives like ZIPs
        }
        else {
            let controller = UIDocumentInteractionController(url: fileURL)
            controller.delegate = self
            controller.presentPreview(animated: true)
        }
    }

    func shareFile(at fileURL: URL) {
        let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(activityViewController, animated: true, completion: nil)
    }

    func deleteFile(at fileURL: URL) {
        do {
            try fileManager.removeItem(at: fileURL)
            loadFiles()
        } catch {
            handleError(error: error, withTitle: "Error Deleting File")
        }
    }

    func renameFile(at fileURL: URL) {
        presentTextInputAlert(title: "Rename File", message: "Enter the new name for the file:", textFieldPlaceholder: "New Name")
        { newName in
            guard let newName = newName, !newName.isEmpty else { return }
            let newFileURL = self.documentsDirectory.appendingPathComponent(newName)
            do {
                try self.fileManager.moveItem(at: fileURL, to: newFileURL)
                self.loadFiles()
            } catch {
                self.handleError(error: error, withTitle: "Error Renaming File")
            }
        }
    }

    func getFileInfo(at fileURL: URL) {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.fileSize] as? NSNumber
            let creationDate = attributes[.fileCreationDate] as? Date
            let modificationDate = attributes[.fileModificationDate] as? Date

            var message = "File Size: \(fileSize?.stringValue ?? "Unknown") bytes\n"
            if let creationDate = creationDate {
                message += "Creation Date: \(creationDate)\n"
            }
            if let modificationDate = modificationDate {
                message += "Modification Date: \(modificationDate)\n"
            }

            presentAlert(title: fileURL.lastPathComponent, message: message)

        } catch {
            handleError(error: error, withTitle: "Error Getting File Info")
        }
    }

    // MARK: - PDF Viewing

    func viewPDF(at url: URL) {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true

                let pdfViewController = UIViewController()
        pdfViewController.view = pdfView

        let closeButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissPDFView))
        pdfViewController.navigationItem.rightBarButtonItem = closeButton

        let navigationController = UINavigationController(rootViewController: pdfViewController)
        present(navigationController, animated: true, completion: nil)
    }

    @objc func dismissPDFView() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - File "View" Action

    func viewFile(at fileURL: URL) {
        let fileType = UTType(filenameExtension: fileURL.pathExtension)

        if fileType == UTType.image {
            viewImage(at: fileURL)
        } else if fileType == UTType.text {
            editTextFile(at: fileURL)
        } else if fileType == UTType.zip {
            viewZipContents(at: fileURL)
        } else if fileType == UTType("public.archive" as CFString) { // General archive type
            viewZipContents(at: fileURL) // Treat other archives like ZIPs
        }
        // Add more file type handling here (e.g., audio, video)
        else {
            presentAlert(title: "Cannot View File", message: "This file type cannot be viewed.")
        }
    }

    // MARK: - Image Viewing

    func viewImage(at fileURL: URL) {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        Nuke.loadImage(with: fileURL, into: imageView)

        let imageViewController = UIViewController()
        imageViewController.view = imageView

        let closeButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissImageView))
        imageViewController.navigationItem.rightBarButtonItem = closeButton

        let navigationController = UINavigationController(rootViewController: imageViewController)
        present(navigationController, animated: true, completion: nil)
    }

    @objc func dismissImageView() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Text File Editing

    func editTextFile(at fileURL: URL) {
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let textView = UITextView()
            textView.text = text
            textView.isEditable = true

            let textViewController = UIViewController()
            textViewController.view = textView

            let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTextFile(_:)))
            textViewController.navigationItem.rightBarButtonItem = saveButton
            textViewController.navigationItem.title = fileURL.lastPathComponent

            let navigationController = UINavigationController(rootViewController: textViewController)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true, completion: nil)

            objc_setAssociatedObject(textView, &textFileKey, fileURL, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) // Store the file URL

        } catch {
            handleError(error: error, withTitle: "Error Reading Text File")
        }
    }

    @objc func saveTextFile(_ sender: UIBarButtonItem) {
        if let navigationController = presentedViewController as? UINavigationController,
           let textViewController = navigationController.topViewController,
           let textView = textViewController.view as? UITextView,
           let fileURL = objc_getAssociatedObject(textView, &textFileKey) as? URL {

            do {
                try textView.text.write(to: fileURL, atomically: true, encoding: .utf8)
                dismiss(animated: true, completion: nil)
                loadFiles() // Reload to reflect changes
                presentAlert(title: "File Saved", message: "The text file has been saved.")
            } catch {
                handleError(error: error, withTitle: "Error Saving Text File")
            }
        }
    }

    // MARK: - ZIP File Handling

    func viewZipContents(at fileURL: URL) {
        do {
            let zip = try Archive(url: fileURL, accessMode: .read)

            var entries = [String]()
            for entry in zip {
                entries.append(entry.path)
            }

            let zipContentsViewController = ZipContentsViewController(entries: entries, zipURL: fileURL)
            navigationController?.pushViewController(zipContentsViewController, animated: true)

        } catch {
            handleError(error: error, withTitle: "Error Opening ZIP File")
        }
    }

    // MARK: - Hex Editing (Basic Structure)

    func editHexFile(at fileURL: URL) {
        // This is a placeholder for hex editing functionality.
        // Implementing a full hex editor is complex and requires:
        // 1. Reading file data into a buffer.
        // 2. Displaying the data in a hexadecimal format (e.g., using a custom UICollectionView or TextView).
        // 3. Allowing users to modify the hexadecimal representation.
        // 4. Writing the modified data back to the file.
        // This would likely involve custom UI elements and data conversion logic.

        presentAlert(title: "Hex Editing", message: "Hex editing functionality is not fully implemented in this example.")
    }

    // MARK: - IPA Information (Basic Structure)

    func getIPAInfo(at fileURL: URL) {
        // This is a placeholder for IPA information retrieval.
        // IPA files are essentially ZIP archives with a specific structure.
        // To get information from them, you would need to:
        // 1. Open the IPA file as a ZIP archive (using ZIPFoundation).
        // 2. Look for specific files within the archive (e.g., `Info.plist`).
        // 3. Parse the contents of those files to extract information.
        // This would require knowledge of the IPA file structure and parsing techniques.

        presentAlert(title: "IPA Information", message: "IPA information retrieval is not fully implemented in this example.")
    }
}

// MARK: - ZipContentsViewController (Embedded)

extension HomeViewController {
    class ZipContentsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
        let entries: [String]
        let zipURL: URL
        let tableView = UITableView()

        init(entries: [String], zipURL: URL) {
            self.entries = entries
            self.zipURL = zipURL
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            title = "Zip Contents"

            tableView.delegate = self
            tableView.dataSource = self
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
            tableView.frame = view.bounds
            tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(tableView)
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return entries.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.textLabel?.text = entries[indexPath.row]
            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            // Implement logic to handle the selection of an entry within the ZIP file.
            // This could involve extracting the file, previewing it, etc.
            print("Selected entry: \(entries[indexPath.row])")
        }
    }
}

// MARK: - Associated Object Key

private var textFileKey: UInt8 = 0

// MARK: - Extensions

extension HomeViewController {
    func presentAlert(title: String?, message: String?) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    func presentTextInputAlert(title: String?, message: String?, textFieldPlaceholder: String?, completion: @escaping (String?) -> Void) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = textFieldPlaceholder
        }
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            completion(nil)
        }))
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            if let textFieldText = alertController.textFields?.first?.text {
                completion(textFieldText)
            } else {
                completion(nil)
            }
        }))
        present(alertController, animated: true, completion: nil)
    }

    func handleError(error: Error, withTitle title: String? = nil) {
        os_log("Error: %{public}@", log: OSLog.default, type: .error, error.localizedDescription)
        let alertController = UIAlertController(title: title ?? "Error", message: error.localizedDescription, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        } else {
            return false
        }
    }

    func getFileIcon(for url: URL) -> UIImage {
        let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, url.pathExtension as CFString, nil)?.takeRetainedValue()

        var systemIcon: UIImage
        if uti != nil {
            systemIcon = UIImage(systemName: "doc")! // Default document icon
            if UTTypeConformsTo(uti!, kUTTypeImage) {
                systemIcon = UIImage(systemName: "photo")!
            } else if UTTypeConformsTo(uti!, kUTTypeMovie) {
                systemIcon = UIImage(systemName: "film")!
            } else if UTTypeConformsTo(uti!, kUTTypeAudio) {
                systemIcon = UIImage(systemName: "music.note")!
            } else if UTTypeConformsTo(uti!, kUTTypeText) {
                systemIcon = UIImage(systemName: "doc.plaintext")!
            } else if UTTypeConformsTo(uti!, kUTTypeDirectory) {
                systemIcon = UIImage(systemName: "folder")!
            } else if UTTypeConformsTo(uti!, kUTTypePDF) {
                systemIcon = UIImage(systemName: "doc.pdf")!
            } else if UTTypeConformsTo(uti!, kUTTypeArchive) {
                systemIcon = UIImage(systemName: "archivebox")!
            }
        } else {
            systemIcon = UIImage(systemName: "questionmark.circle")! // Unknown file type icon
        }
        return systemIcon
    }

    func sortFiles(_ files: [URL], by sortOrder: HomeViewController.SortOrder) -> [URL] {
        switch sortOrder {
        case .name:
            return files.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        case .date:
            return files sorted {
                let date1 = try? FileManager.default.attributesOfItem(atPath: $0.path)[.fileCreationDate] as? Date ?? Date.distantPast
                let date2 = try? FileManager.default.attributesOfItem(atPath: $1.path)[.fileCreationDate] as? Date ?? Date.distantPast
                return date1.compare(date2) == .orderedAscending
            }
        case .size:
            return files.sorted {
                let size1 = try? FileManager.default.attributesOfItem(atPath: $0.path)[.fileSize] as? NSNumber ?? 0
                let size2 = try? FileManager.default.attributesOfItem(atPath: $1.path)[.fileSize] as? NSNumber ?? 0
                return size1.compare(size2) == .orderedAscending
            }
        }
    }

    func copyPickedFiles(urls: [URL], to destinationDirectory: URL) -> URL? {
        // Implement the logic to copy files from the picked URLs to the destination directory.
        // Handle potential errors during the copy process.
        // Return the destination URL if successful, or nil if not.
        for url in urls {
            let destinationURL = destinationDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                print("Error copying file: \(error)")
                return nil
            }
        }
        return destinationDirectory
    }
}

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa")!
}

// MARK: - Extensions

extension HomeViewController {
    func presentAlert(title: String?, message: String?) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    func presentTextInputAlert(title: String?, message: String?, textFieldPlaceholder: String?, completion: @escaping (String?) -> Void) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = textFieldPlaceholder
        }
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
            completion(nil)
        }))
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            if let textFieldText = alertController.textFields?.first?.text {
                completion(textFieldText)
            } else {
                completion(nil)
            }
        }))
        present(alertController, animated: true, completion: nil)
    }

    func handleError(error: Error, withTitle title: String? = nil) {
        os_log("Error: %{public}@", log: OSLog.default, type: .error, error.localizedDescription)
        let alertController = UIAlertController(title: title ?? "Error", message: error.localizedDescription, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        } else {
            return false
        }
    }

    func getFileIcon(for url: URL) -> UIImage {
        let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, url.pathExtension as CFString, nil)?.takeRetainedValue()

        var systemIcon: UIImage
        if uti != nil {
            systemIcon = UIImage(systemName: "doc")! // Default document icon
            if UTTypeConformsTo(uti!, kUTTypeImage) {
                systemIcon = UIImage(systemName: "photo")!
            } else if UTTypeConformsTo(uti!, kUTTypeMovie) {
                systemIcon = UIImage(systemName: "film")!
            } else if UTTypeConformsTo(uti!, kUTTypeAudio) {
                systemIcon = UIImage(systemName: "music.note")!
            } else if UTTypeConformsTo(uti!, kUTTypeText) {
                systemIcon = UIImage(systemName: "doc.plaintext")!
            } else if UTTypeConformsTo(uti!, kUTTypeDirectory) {
                systemIcon = UIImage(systemName: "folder")!
            } else if UTTypeConformsTo(uti!, kUTTypePDF) {
                systemIcon = UIImage(systemName: "doc.pdf")!
            } else if UTTypeConformsTo(uti!, kUTTypeArchive) {
                systemIcon = UIImage(systemName: "archivebox")!
            }
        } else {
            systemIcon = UIImage(systemName: "questionmark.circle")! // Unknown file type icon
        }
        return systemIcon
    }

    func sortFiles(_ files: [URL], by sortOrder: HomeViewController.SortOrder) -> [URL] {
        switch sortOrder {
        case .name:
            return files.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        case .date:
            return files.sorted {
                let date1 = try? FileManager.default.attributesOfItem(atPath: $0.path)[.fileCreationDate] as? Date ?? Date.distantPast
                let date2 = try? FileManager.default.attributesOfItem(atPath: $1.path)[.fileCreationDate] as? Date ?? Date.distantPast
                return date1.compare(date2) == .orderedAscending
            }
        case .size:
            return files.sorted {
                let size1 = try? FileManager.default.attributesOfItem(atPath: $0.path)[.fileSize] as? NSNumber ?? 0
                let size2 = try? FileManager.default.attributesOfItem(atPath: $1.path)[.fileSize] as? NSNumber ?? 0
                return size1.compare(size2) == .orderedAscending
            }
        }
    }

    func copyPickedFiles(urls: [URL], to destinationDirectory: URL) -> URL? {
        // Implement the logic to copy files from the picked URLs to the destination directory.
        // Handle potential errors during the copy process.
        // Return the destination URL if successful, or nil if not.
        for url in urls {
            let destinationURL = destinationDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                print("Error copying file: \(error)")
                return nil
            }
        }
        return destinationDirectory
    }
}