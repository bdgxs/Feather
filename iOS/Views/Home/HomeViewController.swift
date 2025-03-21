import UIKit
import ZIPFoundation
import Foundation
import os.log
import UniformTypeIdentifiers
import CoreData
import WebKit
import Nuke
import SWCompression
import AlertKit
import OpenSSL
import ImageIO

class HomeViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating, UIDocumentInteractionControllerDelegate, UITableViewDragDelegate, UITableViewDropDelegate, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    // MARK: - Properties

    private var fileList: [String] = []
    private var filteredFileList: [String] = []
    private let fileManager = FileManager.default
    private let searchController = UISearchController(searchResultsController: nil)
    private var sortOrder: SortOrder = .name
    private var lastSortOrder: SortOrder = .name
    private var isRefreshing = false
    private var selectedFiles: [String] = []
    private var isMultiSelectMode = false
    private var appDownloader: AppDownload?
    private var downloadProgress: Float = 0.0
    private var extractionProgress: Float = 0.0
    private var currentDownloadTask: URLSessionDownloadTask?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private lazy var coreDataManager = CoreDataManager.shared
    let fileHandlers = HomeViewFileHandlers()
    let utilities = HomeViewUtilities()
    var documentsDirectory: URL {
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("files")
        createFilesDirectoryIfNeeded(at: directory)
        return directory
    }
    var currentDirectoryPath: URL
    enum SortOrder { case name, date, size }
    let fileListTableView = UITableView()
    let activityIndicator = UIActivityIndicatorView(style: .large)
    let progressView = UIProgressView(progressViewStyle: .bar)
    let refreshControl = UIRefreshControl()
    let multiSelectButton = UIBarButtonItem(title: "Select", style: .plain, target: nil, action: nil)
    let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: nil, action: nil)
    let actionButton = UIBarButtonItem(barButtonSystemItem: .action, target: nil, action: nil)

    // MARK: - Initialization

    init(directoryPath: URL? = nil) {
        self.currentDirectoryPath = directoryPath ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("files")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.currentDirectoryPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("files")
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureTableView()
        setupSearchController()
        setupRefreshControl()
        setupMultiSelectButtons()
        registerForNotifications()
        loadFiles()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !isRefreshing {
            loadFiles()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cancelBackgroundTask()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = currentDirectoryPath.lastPathComponent
        let menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(showMenu))
        let uploadButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(importFile))
        let addButton = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"), style: .plain, target: self, action: #selector(addDirectory))
        navigationItem.rightBarButtonItems = [menuButton, uploadButton, addButton]
        if currentDirectoryPath != documentsDirectory {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "arrow.left"), style: .plain, target: self, action: #selector(navigateToParentDirectory))
        }
        view.addSubview(fileListTableView)
        fileListTableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fileListTableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            fileListTableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            fileListTableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            fileListTableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setupActivityIndicator() {
        view.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupProgressView() {
        progressView.progress = 0
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        ])
        progressView.isHidden = true
    }

    private func setupRefreshControl() {
        refreshControl.attributedTitle = NSAttributedString(string: NSLocalizedString("Pull to refresh", comment: "Pull to refresh text"))
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        fileListTableView.refreshControl = refreshControl
    }

    private func setupMultiSelectButtons() {
        multiSelectButton.target = self
        multiSelectButton.action = #selector(toggleMultiSelectMode)
        cancelButton.target = self
        cancelButton.action = #selector(cancelMultiSelect)
        actionButton.target = self
        actionButton.action = #selector(performBatchAction)
        actionButton.isEnabled = false
        if currentDirectoryPath == documentsDirectory {
            navigationItem.leftBarButtonItem = multiSelectButton
        } else {
            let rightItems = navigationItem.rightBarButtonItems ?? []
            navigationItem.rightBarButtonItems = rightItems + [multiSelectButton]
        }
    }

    private func configureTableView() {
        fileListTableView.delegate = self
        fileListTableView.dataSource = self
        fileListTableView.dragDelegate = self
        fileListTableView.dropDelegate = self
        fileListTableView.dragInteractionEnabled = true
        fileListTableView.allowsMultipleSelection = false
        fileListTableView.register(FileTableViewCell.self, forCellReuseIdentifier: "FileCell")
        fileListTableView.register(AppTableViewCell.self, forCellReuseIdentifier: "AppCell")
        fileListTableView.rowHeight = 70
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("Search Files", comment: "Search bar placeholder")
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }

    private func createFilesDirectoryIfNeeded(at directory: URL) {
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Directory Creation Failed", comment: "Error title"))
            }
        }
    }

    private func registerForNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    // MARK: - File Operations

    func loadFiles() {
        isRefreshing = true
        activityIndicator.startAnimating()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let fileURLs = try self.fileManager.contentsOfDirectory(at: self.currentDirectoryPath, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
                self.fileList = fileURLs.map { $0.lastPathComponent }
                self.sortFiles()
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.fileListTableView.reloadData()
                    self.refreshControl.endRefreshing()
                    self.isRefreshing = false
                    if self.fileList.isEmpty {
                        self.showEmptyState()
                    } else {
                        self.hideEmptyState()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.refreshControl.endRefreshing()
                    self.isRefreshing = false
                    self.utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Failed to Load Files", comment: "Error title"))
                }
            }
        }
    }

    private func sortFiles() {
        let fileURLs = fileList.map { currentDirectoryPath.appendingPathComponent($0) }
        switch sortOrder {
        case .name:
            fileList.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .date:
            let sortedURLs = fileURLs.sorted { url1, url2 -> Bool in
                do {
                    let values1 = try url1.resourceValues(forKeys: [.contentModificationDateKey])
                    let values2 = try url2.resourceValues(forKeys: [.contentModificationDateKey])
                    if let date1 = values1.contentModificationDate, let date2 = values2.contentModificationDate {
                        return date1 > date2
                    }
                } catch {
                    print("Error getting file dates: \(error)")
                }
                return false
            }
            fileList = sortedURLs.map { $0.lastPathComponent }
        case .size:
            let sortedURLs = fileURLs.sorted { url1, url2 -> Bool in
                do {
                    let values1 = try url1.resourceValues(forKeys: [.fileSizeKey])
                    let values2 = try url2.resourceValues(forKeys: [.fileSizeKey])
                    if let size1 = values1.fileSize, let size2 = values2.fileSize {
                        return size1 > size2
                    }
                } catch {
                    print("Error getting file sizes: \(error)")
                }
                return false
            }
            fileList = sortedURLs.map { $0.lastPathComponent }
        }
        let directoryFiles = fileList.filter { fileName in
            let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
            return isDirectory.boolValue
        }
        let nonDirectoryFiles = fileList.filter { fileName in
            let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
            return !isDirectory.boolValue
        }
        fileList = directoryFiles + nonDirectoryFiles
        if searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true) {
            filterContentForSearchText(searchController.searchBar.text!)
        } else {
            filteredFileList = fileList
        }
    }

    func openFile(at indexPath: IndexPath) {
        let fileList = searchController.isActive ? filteredFileList : self.fileList
        guard indexPath.row < fileList.count else { return }
        let fileName = fileList[indexPath.row]
        let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            utilities.showAlert(in: self, title: NSLocalizedString("Error", comment: "Error title"), message: NSLocalizedString("File no longer exists", comment: "File missing message"))
            loadFiles()
            return
        }
        if isDirectory.boolValue {
            let directoryVC = HomeViewController(directoryPath: fileURL)
            navigationController?.pushViewController(directoryVC, animated: true)
            return
        }
        let fileExtension = fileURL.pathExtension.lowercased()
        switch fileExtension {
        case "ipa":
            handleIPAFile(at: fileURL)
        case "txt", "log", "json", "xml", "plist", "html", "css", "js", "swift", "m", "h", "c", "cpp":
            openTextFile(at: fileURL)
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp":
            openImageFile(at: fileURL)
        case "mp4", "mov", "m4v", "3gp":
            openVideoFile(at: fileURL)
        case "pdf":
            openPDFFile(at: fileURL)
        case "zip":
            handleZipFile(at: fileURL)
        case "bin", "dat", "hex":
            openHexEditor(for: fileURL)
        default:
            if let uti = UTType(filenameExtension: fileExtension) {
                if uti.conforms(to: .text) {
                    openTextFile(at: fileURL)
                } else if uti.conforms(to: .image) {
                    openImageFile(at: fileURL)
                } else if uti.conforms(to: .movie) {
                    openVideoFile(at: fileURL)
                } else if uti.conforms(to: .pdf) {
                    openPDFFile(at: fileURL)
                } else if uti.conforms(to: .archive) {
                    handleZipFile(at: fileURL)
                } else {
                    let previewController = UIDocumentInteractionController(url: fileURL)
                    previewController.delegate = self
                    if !previewController.presentPreview(animated: true) {
                        previewController.presentOptionsMenu(from: view.bounds, in: view, animated: true)
                    }
                }
            } else {
                let previewController = UIDocumentInteractionController(url: fileURL)
                previewController.delegate = self
                previewController.presentOptionsMenu(from: view.bounds, in: view, animated: true)
            }
        }
    }

    private func handleIPAFile(at fileURL: URL) {
        let alert = UIAlertController(
            title: NSLocalizedString("IPA File", comment: "IPA file alert title"),
            message: NSLocalizedString("What would you like to do with this IPA file?", comment: "IPA options message"),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Extract", comment: "Extract action"), style: .default) { [weak self] _ in
            self?.extractIPA(at: fileURL)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("View Info", comment: "View info action"), style: .default) { [weak self] _ in
            self?.showIPAInfo(for: fileURL)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Edit Contents", comment: "Edit contents action"), style: .default) { [weak self] _ in
            self?.editIPAContents(at: fileURL)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    private func editIPAContents(at fileURL: URL) {
        extractIPA(at: fileURL) { [weak self] extractedDirectoryURL in
            if let extractedDirectoryURL = extractedDirectoryURL {
                let fileBrowserVC = HomeViewController(directoryPath: extractedDirectoryURL)
                self?.navigationController?.pushViewController(fileBrowserVC, animated: true)
            }
        }
    }

    private func extractIPA(at fileURL: URL, completion: ((URL?) -> Void)? = nil) {
        let progressAlert = showProgressAlert(title: "Extracting IPA", message: "Please wait...")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let destinationURL = self.currentDirectoryPath.appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent)
                try self.fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
                try ZIPFoundation.unzipItem(zipFileURL: fileURL, destination: destinationURL)
                DispatchQueue.main.async {
                    self.dismissProgressAlert(alert: progressAlert)
                    self.loadFiles()
                    completion?(destinationURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.dismissProgressAlert(alert: progressAlert)
                    self.utilities.handleError(in: self, error: error, withTitle: "IPA Extraction Failed")
                    completion?(nil)
                }
            }
        }
    }

    private func showIPAInfo(for fileURL: URL) {
        // Implement IPA info viewing logic
    }

    private func modifyIPA(at fileURL: URL) {
        // Implement IPA modification logic
    }

    // MARK: - File Type Handlers

    private func openTextFile(at fileURL: URL) {
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let textEditorVC = TextEditorViewController(fileURL: fileURL, text: text)
            let navController = UINavigationController(rootViewController: textEditorVC)
            present(navController, animated: true)
        } catch {
            do {
                let text = try String(contentsOf: fileURL, encoding: .isoLatin1)
                let textEditorVC = TextEditorViewController(fileURL: fileURL, text: text)
                let navController = UINavigationController(rootViewController: textEditorVC)
                present(navController, animated: true)
            } catch {
                utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Failed to Open Text File", comment: "Error title"))
            }
        }
    }

    private func openImageFile(at fileURL: URL) {
        let imageViewer = ImageViewerViewController(imageURL: fileURL)
        let navController = UINavigationController(rootViewController: imageViewer)
        present(navController, animated: true)
    }

    private func openVideoFile(at fileURL: URL) {
        let videoViewer = VideoViewerViewController(videoURL: fileURL)
        let navController = UINavigationController(rootViewController: videoViewer)
        present(navController, animated: true)
    }

    private func openPDFFile(at fileURL: URL) {
        let pdfViewer = PDFViewerViewController(pdfURL: fileURL)
        let navController = UINavigationController(rootViewController: pdfViewer)
        present(navController, animated: true)
    }

    private func handleZipFile(at fileURL: URL) {
        let alert = UIAlertController(title: "Zip File", message: "What would you like to do?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Unzip", style: .default) { [weak self] _ in
            self?.unzipFile(at: fileURL)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    func openHexEditor(for fileURL: URL) {
        let hexEditorVC = HexEditorViewController(fileURL: fileURL)
        let navController = UINavigationController(rootViewController: hexEditorVC)
        present(navController, animated: true)
    }

    func openPlistEditor(for fileURL: URL) {
        let plistEditorVC = PlistEditorViewController(fileURL: fileURL)
        let navController = UINavigationController(rootViewController: plistEditorVC)
        present(navController, animated: true)
    }

    func openImageEditor(for fileURL: URL) {
        let imageEditorVC = ImageEditorViewController(imageURL: fileURL)
        let navController = UINavigationController(rootViewController: imageEditorVC)
        present(navController, animated: true)
    }

    // MARK: - Encryption/Decryption

    func encryptFile(at fileURL: URL, password: String) {
        do {
            let fileData = try Data(contentsOf: fileURL)
            let encryptedData = try AES.encrypt(fileData, password: password)
            let encryptedFileURL = fileURL.appendingPathExtension("enc")
            try encryptedData.write(to: encryptedFileURL)
            utilities.showAlert(in: self, title: "Encryption Successful", message: "File encrypted successfully.")
        } catch {
            utilities.handleError(in: self, error: error, withTitle: "Encryption Failed")
        }
    }

    func decryptFile(at fileURL: URL, password: String) {
        do {
            let encryptedData = try Data(contentsOf: fileURL)
            let decryptedData = try AES.decrypt(encryptedData, password: password)
            let decryptedFileURL = fileURL.deletingPathExtension()
            try decryptedData.write(to: decryptedFileURL)
            utilities.showAlert(in: self, title: "Decryption Successful", message: "File decrypted successfully.")
        } catch {
            utilities.handleError(in: self, error: error, withTitle: "Decryption Failed")
        }
    }

    // MARK: - Search and Sorting

    func updateSearchResults(for searchController: UISearchController) {
        if let searchText = searchController.searchBar.text, !searchText.isEmpty {
            filteredFileList = fileList.filter { fileName in
                let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
                if fileManager.isDirectory(atPath: fileURL.path) {
                    return fileName.localizedCaseInsensitiveContains(searchText)
                } else {
                    do {
                        let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
                        return fileName.localizedCaseInsensitiveContains(searchText) || fileContent.localizedCaseInsensitiveContains(searchText)
                    } catch {
                        return fileName.localizedCaseInsensitiveContains(searchText)
                    }
                }
            }
        } else {
            filteredFileList = fileList
        }
        fileListTableView.reloadData()
    }

    // MARK: - Table View Delegate and Data Source

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchController.isActive ? filteredFileList.count : fileList.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let fileList = searchController.isActive ? filteredFileList : self.fileList
        let fileName = fileList[indexPath.row]
        let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)

        if fileURL.pathExtension.lowercased() == "ipa" {
            let cell = tableView.dequeueReusableCell(withIdentifier: "AppCell", for: indexPath) as! AppTableViewCell
            cell.fileNameLabel.text = fileName
            cell.fileImageView.image = UIImage(systemName: "app.gift")
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileTableViewCell
            cell.fileNameLabel.text = fileName
            cell.fileImageView.image = isDirectory.boolValue ? UIImage(systemName: "folder") : UIImage(systemName: "doc")
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        openFile(at: indexPath)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let fileList = searchController.isActive ? filteredFileList : self.fileList
        let fileName = fileList[indexPath.row]
        let fileURL = currentDirectoryPath.appendingPathComponent(fileName)

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (_, _, completionHandler) in
            self?.deleteFile(at: fileURL)
            completionHandler(true)
        }
        deleteAction.image = UIImage(systemName: "trash")
        deleteAction.backgroundColor = .systemRed

        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        return configuration
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let fileList = searchController.isActive ? filteredFileList : self.fileList
        let fileName = fileList[indexPath.row]
        let fileURL = currentDirectoryPath.appendingPathComponent(fileName)

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions in
            let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.showRenameAlert(for: fileURL)
            }

            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "
trash"), attributes: .destructive) { [weak self] _ in
                self?.deleteFile(at: fileURL)
            }

            let zipAction = UIAction(title: "Zip", image: UIImage(systemName: "zipper")) { [weak self] _ in
                self?.zipFile(at: fileURL)
            }

            let unzipAction = UIAction(title: "Unzip", image: UIImage(systemName: "box.and.arrow.down")) { [weak self] _ in
                self?.unzipFile(at: fileURL)
            }

            let shareAction = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.shareFile(at: fileURL)
            }

            return UIMenu(title: "", children: [renameAction, deleteAction, zipAction, unzipAction, shareAction])
        }
    }

    private func showRenameAlert(for fileURL: URL) {
        let alert = UIAlertController(title: "Rename File", message: "Enter new file name:", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = fileURL.lastPathComponent
        }
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self, weak alert] _ in
            if let newName = alert?.textFields?.first?.text {
                self?.renameFile(at: fileURL, newName: newName)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Drag and Drop

    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let fileList = searchController.isActive ? filteredFileList : self.fileList
        let fileName = fileList[indexPath.row]
        let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
        let itemProvider = NSItemProvider(url: fileURL)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = fileURL
        return [dragItem]
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        let destinationIndexPath: IndexPath
        if let indexPath = coordinator.destinationIndexPath {
            destinationIndexPath = indexPath
        } else {
            let row = tableView.numberOfRows(inSection: 0)
            destinationIndexPath = IndexPath(row: row, section: 0)
        }
        coordinator.items.forEach { item in
            item.dragItem.itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                if let urlData = urlData as? URL, let destinationURL = self.currentDirectoryPath.appendingPathComponent(self.fileList[destinationIndexPath.row]).appendingPathComponent(urlData.lastPathComponent) {
                    do {
                        try self.fileManager.moveItem(at: urlData, to: destinationURL)
                        DispatchQueue.main.async {
                            self.loadFiles()
                        }
                    } catch {
                        print("Error moving file: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Multi-Select Actions

    @objc private func toggleMultiSelectMode() {
        isMultiSelectMode.toggle()
        fileListTableView.allowsMultipleSelection = isMultiSelectMode
        if isMultiSelectMode {
            navigationItem.leftBarButtonItems = [cancelButton, actionButton]
        } else {
            navigationItem.leftBarButtonItem = multiSelectButton
        }
        fileListTableView.reloadData()
    }

    @objc private func cancelMultiSelect() {
        isMultiSelectMode = false
        fileListTableView.allowsMultipleSelection = false
        navigationItem.leftBarButtonItem = multiSelectButton
        selectedFiles.removeAll()
        fileListTableView.reloadData()
    }

    @objc private func performBatchAction() {
        // Implement batch actions for selected files
    }

    // MARK: - Background Tasks

    @objc private func appDidEnterBackground() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BackgroundTask") {
            self.cancelBackgroundTask()
        }
    }

    @objc private func appWillEnterForeground() {
        cancelBackgroundTask()
    }

    private func beginBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BackgroundTask") {
            self.cancelBackgroundTask()
        }
    }

    private func cancelBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - Helper Classes/Extensions

    class HomeViewFileHandlers { }
    class HomeViewUtilities {
        func showAlert(in viewController: UIViewController, title: String, message: String) {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
        }

        func handleError(in viewController: UIViewController, error: Error, withTitle title: String) {
            showAlert(in: viewController, title: title, message: error.localizedDescription)
        }
    }

    // MARK: - Hex Editor View Controller

    class HexEditorViewController: UIViewController, UISearchBarDelegate {
        let fileURL: URL
        let textView = UITextView()
        let searchBar = UISearchBar()

        init(fileURL: URL) {
            self.fileURL = fileURL
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
            setupSearchBar()
            loadData()
        }

        private func setupUI() {
            view.backgroundColor = .systemBackground
            textView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
                textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
        }

        private func setupSearchBar() {
            searchBar.delegate = self
            searchBar.placeholder = "Search Hex"
            searchBar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(searchBar)
            NSLayoutConstraint.activate([
                searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                searchBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                searchBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
            ])
        }

        private func loadData() {
            do {
                let data = try Data(contentsOf: fileURL)
                let hexString = data.map { String(format: "%02hhx", $0) }.joined(separator: " ")
                textView.text = hexString
            } catch {
                print("Error loading data: \(error)")
            }
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            if let searchText = searchBar.text {
                searchHex(searchText)
            }
            searchBar.resignFirstResponder()
        }

        private func searchHex(_ searchText: String) {
            // Implement hex search algorithm
        }
    }

    // MARK: - Plist Editor View Controller

    class PlistEditorViewController: UIViewController {
        let fileURL: URL
        let textView = UITextView()

        init(fileURL: URL) {
            self.fileURL = fileURL
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
            loadData()
        }

        private func setupUI() {
            view.backgroundColor = .systemBackground
            textView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
        }

        private func loadData() {
            do {
                let data = try Data(contentsOf: fileURL)
                if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    textView.text = plist.description
                }
            } catch {
                print("Error loading plist: \(error)")
            }
        }
    }

    // MARK: - Image Viewer View Controller

    class ImageViewerViewController: UIViewController {
        let imageURL: URL
        let imageView = UIImageView()

        init(imageURL: URL) {
            self.imageURL = imageURL
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
            loadImage()
        }

        private func setupUI() {
            view.backgroundColor = .systemBackground
            imageView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
        }

        private func loadImage() {
            Nuke.loadImage(with: imageURL, into: imageView)
        }
    }

    // MARK: - Video Viewer View Controller

    class VideoViewerViewController: UIViewController {
        let videoURL: URL
        let webView = WKWebView()

        init(videoURL: URL) {
            self.videoURL = videoURL
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
            loadVideo()
        }

        private func setupUI() {
            view.backgroundColor = .systemBackground
            webView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
        }

        private func loadVideo() {
            webView.loadFileURL(videoURL, allowingReadAccessTo: videoURL)
        }
    }

    // MARK: - PDF Viewer View Controller

    class PDFViewerViewController: UIViewController {
        let pdfURL: URL
        let webView = WKWebView()

        init(pdfURL: URL) {
            self.pdfURL = pdfURL
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
            loadPDF()
        }

        private func setupUI() {
            view.backgroundColor = .systemBackground
            webView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
        }

        private func loadPDF() {
            webView.loadFileURL(pdfURL, allowingReadAccessTo: pdfURL)
        }
    }

    // MARK: - Text Editor View Controller

    class TextEditorViewController: UIViewController, UITextViewDelegate {
        let fileURL: URL
        let textView = UITextView()

        init(fileURL: URL, text: String) {
            self.fileURL = fileURL
            super.init(nibName: nil, bundle: nil)
            textView.text = text
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
        }

        private func setupUI() {
            view.backgroundColor = .systemBackground
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.delegate = self
            view.addSubview(textView)
            NSLayoutConstraint.activate([
                textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            do {
                try textView.text.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Error saving text: \(error)")
            }
        }
    }

    // MARK: - Image Editor View Controller

    class ImageEditorViewController: UIViewController, UITextFieldDelegate {
        let imageURL: URL
        let imageView = UIImageView()
        let widthTextField = UITextField()
        let heightTextField = UITextField()
        let sizeTextField = UITextField()
        let encryptButton = UIButton(type: .system)
        let decryptButton = UIButton(type: .system)

        init(imageURL: URL) {
            self.imageURL = imageURL
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
            loadImage()
        }

        private func setupUI() {
            view.backgroundColor = .systemBackground

            imageView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(imageView)

            widthTextField.translatesAutoresizingMaskIntoConstraints = false
            widthTextField.placeholder = "Width (px)"
            widthTextField.borderStyle = .roundedRect
            widthTextField.keyboardType = .numberPad
            widthTextField.delegate = self
            view.addSubview(widthTextField)

            heightTextField.translatesAutoresizingMaskIntoConstraints = false
            heightTextField.placeholder = "Height (px)"
            heightTextField.borderStyle = .roundedRect
            heightTextField.keyboardType = .numberPad
            heightTextField.delegate = self
            view.addSubview(heightTextField)

            sizeTextField.translatesAutoresizingMaskIntoConstraints = false
            sizeTextField.placeholder = "Size (MB)"
            sizeTextField.borderStyle = .roundedRect
            sizeTextField.keyboardType = .decimalPad
            sizeTextField.delegate = self
            view.addSubview(sizeTextField)

            encryptButton.setTitle("Encrypt", for: .normal)
            encryptButton.addTarget(self, action: #selector(encryptImage), for: .touchUpInside)
            encryptButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(encryptButton)

            decryptButton.setTitle("Decrypt", for: .normal)
            decryptButton.addTarget(self, action: #selector(decryptImage), for: .touchUpInside)
            decryptButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(decryptButton)

            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                imageView.heightAnchor.constraint(equalToConstant: 300),

                widthTextField.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
                widthTextField.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                widthTextField.widthAnchor.constraint
                .constraint(equalToConstant: 100),

                heightTextField.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
                heightTextField.leadingAnchor.constraint(equalTo: widthTextField.trailingAnchor, constant: 10),
                heightTextField.widthAnchor.constraint(equalToConstant: 100),

                sizeTextField.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
                sizeTextField.leadingAnchor.constraint(equalTo: heightTextField.trailingAnchor, constant: 10),
                sizeTextField.widthAnchor.constraint(equalToConstant: 100),

                encryptButton.topAnchor.constraint(equalTo: widthTextField.bottomAnchor, constant: 20),
                encryptButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                encryptButton.widthAnchor.constraint(equalToConstant: 100),

                decryptButton.topAnchor.constraint(equalTo: widthTextField.bottomAnchor, constant: 20),
                decryptButton.leadingAnchor.constraint(equalTo: encryptButton.trailingAnchor, constant: 10),
                decryptButton.widthAnchor.constraint(equalToConstant: 100)
            ])
        }

        private func loadImage() {
            Nuke.loadImage(with: imageURL, into: imageView)
        }

        @objc private func encryptImage() {
            // Implement image encryption logic
        }

        @objc private func decryptImage() {
            // Implement image decryption logic
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            // Implement image resizing logic based on text field inputs
        }
    }

    // MARK: - App Download

    class AppDownload: NSObject, URLSessionDownloadDelegate {
        var downloadTask: URLSessionDownloadTask?
        var progressHandler: ((Float) -> Void)?
        var completionHandler: ((URL?, Error?) -> Void)?

        func downloadApp(from url: URL, to destination: URL) {
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            downloadTask = session.downloadTask(with: url)
            downloadTask?.resume()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
            progressHandler?(progress)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                completionHandler?(destination, nil)
            } catch {
                completionHandler?(nil, error)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                completionHandler?(nil, error)
            }
        }
    }
}

// MARK: - AES Encryption/Decryption

extension AES {
    static func encrypt(_ data: Data, password: String) throws -> Data {
        guard let keyData = password.data(using: .utf8) else { throw NSError(domain: "Invalid password", code: 0, userInfo: nil) }
        let key = keyData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let keyLength = kCCKeySizeAES256

        var iv = Data(count: kCCBlockSizeAES128)
        _ = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }

        var buffer = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var bufferSize = 0

        let result = data.withUnsafeBytes { dataBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding), key, keyLength, ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), dataBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count, &buffer, buffer.count, &bufferSize)
            }
        }

        guard result == kCCSuccess else { throw NSError(domain: "Encryption failed", code: Int(result), userInfo: nil) }
        return iv + Data(bytes: buffer, count: bufferSize)
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard let keyData = password.data(using: .utf8) else { throw NSError(domain: "Invalid password", code: 0, userInfo: nil) }
        let key = keyData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        let keyLength = kCCKeySizeAES256

        let iv = data.prefix(kCCBlockSizeAES128)
        let encryptedData = data.suffix(from: kCCBlockSizeAES128)

        var buffer = [UInt8](repeating: 0, count: encryptedData.count)
        var bufferSize = 0

        let result = encryptedData.withUnsafeBytes { encryptedBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding), key, keyLength, ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), encryptedBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), encryptedData.count, &buffer, buffer.count, &bufferSize)
            }
        }

        guard result == kCCSuccess else { throw NSError(domain: "Decryption failed", code: Int(result), userInfo: nil) }
        return Data(bytes: buffer, count: bufferSize)
    }
}
