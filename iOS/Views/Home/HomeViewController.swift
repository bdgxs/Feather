import UIKit
import ZIPFoundation
import Foundation
import os.log
import UniformTypeIdentifiers
import CoreData
import WebKit

// MARK: - Protocols

protocol FileHandlingDelegate: AnyObject {
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
    func loadFiles()
    var documentsDirectory: URL { get }
}

protocol DownloadDelegate: AnyObject {
    func downloadProgress(progress: Float)
    func downloadDidFinish(fileURL: URL)
    func downloadDidFail(with error: Error)
    func extractionProgress(progress: Float)
    func extractionDidFinish(directoryURL: URL)
    func extractionDidFail(with error: Error)
}

class HomeViewController: UIViewController {
    
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
    
    // App download and IPA handling
    private var appDownloader: AppDownload?
    private var downloadProgress: Float = 0.0
    private var extractionProgress: Float = 0.0
    private var currentDownloadTask: URLSessionDownloadTask?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    // CoreData
    private lazy var coreDataManager = CoreDataManager.shared
    
    let fileHandlers = HomeViewFileHandlers()
    let utilities = HomeViewUtilities()
    
    var documentsDirectory: URL {
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("files")
        createFilesDirectoryIfNeeded(at: directory)
        return directory
    }
    
    // Current directory path for navigation
    var currentDirectoryPath: URL
    
    enum SortOrder {
        case name, date, size
    }
    
    // UI Components
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
        setupActivityIndicator()
        setupProgressView()
        setupRefreshControl()
        setupMultiSelectButtons()
        loadFiles()
        configureTableView()
        registerForNotifications()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh files when view appears
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
        
        // Set title based on current directory
        title = currentDirectoryPath.lastPathComponent
        
        // Navigation bar setup
        let menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(showMenu))
        let uploadButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(importFile))
        let addButton = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"), style: .plain, target: self, action: #selector(addDirectory))
        
        navigationItem.rightBarButtonItems = [menuButton, uploadButton, addButton]
        
        // If not in root directory, add back button
        if currentDirectoryPath != documentsDirectory {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "arrow.left"),
                style: .plain,
                target: self,
                action: #selector(navigateToParentDirectory)
            )
        }
        
        // Search controller setup
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("Search Files", comment: "Search bar placeholder")
        navigationItem.searchController = searchController
        definesPresentationContext = true
        
        // Table view setup
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
        
        // Add multi-select button to left items if we're in root directory
        if currentDirectoryPath == documentsDirectory {
            navigationItem.leftBarButtonItem = multiSelectButton
        } else {
            // Add it to the right items if we're in a subdirectory
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
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
                    
                    // Show empty state if needed
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
                        return date1 > date2 // Most recent first
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
                        return size1 > size2 // Largest first
                    }
                } catch {
                    print("Error getting file sizes: \(error)")
                }
                return false
            }
            fileList = sortedURLs.map { $0.lastPathComponent }
        }
        
        // Always put directories first
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
        
        // Update filtered list if search is active
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
            loadFiles() // Refresh to update the list
            return
        }
        
        if isDirectory.boolValue {
            // Navigate to directory
            let directoryVC = HomeViewController(directoryPath: fileURL)
            navigationController?.pushViewController(directoryVC, animated: true)
            return
        }
        
        // Handle file based on extension
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
            // Try to determine file type by UTI
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
                    // Unknown file type - show preview if possible
                    let previewController = UIDocumentInteractionController(url: fileURL)
                    previewController.delegate = self
                    if !previewController.presentPreview(animated: true) {
                        // If preview not available, show options
                        previewController.presentOptionsMenu(from: view.bounds, in: view, animated: true)
                    }
                }
            } else {
                // Unknown file type - show options
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
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        
        // For iPad
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    // MARK: - File Type Handlers
    
    private func openTextFile(at fileURL: URL) {
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let textEditorVC = TextEditorViewController(fileURL: fileURL, text: text)
            textEditorVC.delegate = self
            let navController = UINavigationController(rootViewController: textEditorVC)
            present(navController, animated: true)
        } catch {
            // Try other encodings if UTF-8 fails
            do {
                let text = try String(contentsOf: fileURL, encoding: .isoLatin1)
                let textEditorVC = TextEditorViewController(fileURL: fileURL, text: text)
                textEditorVC.delegate = self
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
        let videoPlayer = VideoPlayerViewController(videoURL: fileURL)
        let navController = UINavigationController(rootViewController: videoPlayer)
        present(navController, animated: true)
    }
    
    private func openPDFFile(at fileURL: URL) {
        let pdfViewer = PDFViewerViewController(pdfURL: fileURL)
        let navController = UINavigationController(rootViewController: pdfViewer)
        present(navController, animated: true)
    }
    
    private func openHexEditor(for fileURL: URL) {
        let hexEditor = HexEditorViewController(fileURL: fileURL)
        let navController = UINavigationController(rootViewController: hexEditor)
        present(navController, animated: true)
    }
    
    private func handleZipFile(at fileURL: URL) {
        let alert = UIAlertController(
            title: NSLocalizedString("ZIP File", comment: "ZIP file alert title"),
            message: NSLocalizedString("What would you like to do with this ZIP file?", comment: "ZIP options message"),
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Extract", comment: "Extract action"), style: .default) { [weak self] _ in
            self?.extractZip(at: fileURL)
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("View Contents", comment: "View contents action"), style: .default) { [weak self] _ in
            self?.viewZipContents(at: fileURL)
        })
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        
        // For iPad
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    
    private func extractZip(at fileURL: URL) {
        // Create extraction destination
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let extractionDirectory = currentDirectoryPath.appendingPathComponent("\(fileName)_extracted")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: extractionDirectory.path) {
            do {
                try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Failed to Create Directory", comment: "Error title"))
                return
            }
        }
        
        // Show progress
        progressView.isHidden = false
        progressView.progress = 0
        
        // Extract in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.fileManager.unzipItem(at: fileURL, to: extractionDirectory, progress: { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.progressView.progress = Float(progress)
                    }
                })
                
                DispatchQueue.main.async {
                    self.progressView.isHidden = true
                    self.loadFiles()
                    self.utilities.showAlert(in: self, title: NSLocalizedString("Success", comment: "Success title"), message: NSLocalizedString("File extracted successfully", comment: "Extraction success message"))
                }
            } catch {
                DispatchQueue.main.async {
                    self.progressView.isHidden = true
                    self.utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Extraction Failed", comment: "Error title"))
                }
            }
        }
    }
    
    private func viewZipContents(at fileURL: URL) {
        let zipViewer = ZipContentsViewController(zipURL: fileURL)
        let navController = UINavigationController(rootViewController: zipViewer)
        present(navController, animated: true)
    }
    
    private func extractIPA(at fileURL: URL) {
        // Create extraction destination
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let extractionDirectory = currentDirectoryPath.appendingPathComponent("\(fileName)_extracted")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: extractionDirectory.path) {
            do {
                try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Failed to Create Directory", comment: "Error title"))
                return
            }
        }
        
        // Show progress
        progressView.isHidden = false
        progressView.progress = 0
        
        // Extract in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.fileManager.unzipItem(at: fileURL, to: extractionDirectory, progress: { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.progressView.progress = Float(progress)
                    }
                })
                
                // Parse IPA info
                self.parseIPAInfo(in: extractionDirectory)
                
                DispatchQueue.main.async {
                    self.progressView.isHidden = true
                    self.loadFiles()
                    self.utilities.showAlert(in: self, title: NSLocalizedString("Success", comment: "Success title"), message: NSLocalizedString("IPA extracted successfully", comment: "Extraction success message"))
                }
            } catch {
                DispatchQueue.main.async {
                    self.progressView.isHidden = true
                    self.utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Extraction Failed", comment: "Error title"))
                }
            }
        }
    }
    
    private func parseIPAInfo(in directory: URL) {
        // Find the Payload directory
        let payloadURL = directory.appendingPathComponent("Payload")
        
        do {
            let appFolders = try fileManager.contentsOfDirectory(at: payloadURL, includingPropertiesForKeys: nil)
            
            for appFolder in appFolders where appFolder.pathExtension == "app" {
                let infoPlistURL = appFolder.appendingPathComponent("Info.plist")
                
                if fileManager.fileExists(atPath: infoPlistURL.path) {
                    guard let infoPlist = NSDictionary(contentsOf: infoPlistURL) else { continue }
                    
                    // Extract app info
                    let bundleID = infoPlist["CFBundleIdentifier"] as? String ?? "Unknown"
                    let appName = infoPlist["CFBundleDisplayName"] as? String ?? infoPlist["CFBundleName"] as? String ?? "Unknown"
                    let version = infoPlist["CFBundleShortVersionString"] as? String ?? "Unknown"
                    let build = infoPlist["CFBundleVersion"] as? String ?? "Unknown"
                    
                    // Save to CoreData
                    DispatchQueue.main.async {
                        self.coreDataManager.saveAppInfo(
                            bundleID: bundleID,
                            name: appName,
                            version: version,
                            build: build,
                            extractedPath: directory.path
                        )
                    }
                    
                    break
                }
            }
        } catch {
            print("Error parsing IPA info: \(error)")
        }
    }
    
    private func showIPAInfo(for fileURL: URL) {
        let ipaInfoVC = IPAInfoViewController(ipaURL: fileURL)
        let navController = UINavigationController(rootViewController: ipaInfoVC)
        present(navController, animated: true)
    }
    // MARK: - UI Actions
    
    @objc private func showMenu() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        // Sort options
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Sort by Name", comment: "Sort option"), style: .default) { [weak self] _ in
            self?.sortOrder = .name
            self?.sortFiles()
            self?.fileListTableView.reloadData()
        })
        
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Sort by Date", comment: "Sort option"), style: .default) { [weak self] _ in
            self?.sortOrder = .date
            self?.sortFiles()
            self?.fileListTableView.reloadData()
        })
        
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Sort by Size", comment: "Sort option"), style: .default) { [weak self] _ in
            self?.sortOrder = .size
            self?.sortFiles()
            self?.fileListTableView.reloadData()
        })
        
        // Download app option
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Download App", comment: "Download option"), style: .default) { [weak self] _ in
            self?.showDownloadAppPrompt()
        })
        
        // Create new file option
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Create New File", comment: "Create file option"), style: .default) { [weak self] _ in
            self?.createNewFile()
        })
        
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        
        // For iPad
        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(actionSheet, animated: true)
    }
    
    @objc private func importFile() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        documentPicker.allowsMultipleSelection = true
        documentPicker.delegate = self
        present(documentPicker, animated: true)
    }
    
    @objc private func addDirectory() {
        let alert = UIAlertController(
            title: NSLocalizedString("New Folder", comment: "New folder title"),
            message: NSLocalizedString("Enter a name for the new folder", comment: "New folder message"),
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("Folder Name", comment: "Folder name placeholder")
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Create", comment: "Create button"), style: .default) { [weak self, weak alert] _ in
            guard let self = self, let folderName = alert?.textFields?.first?.text, !folderName.isEmpty else { return }
            
            let newFolderURL = self.currentDirectoryPath.appendingPathComponent(folderName)
            
            do {
                try self.fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
                self.loadFiles()
            } catch {
                self.utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Failed to Create Folder", comment: "Error title"))
            }
        })
        
        present(alert, animated: true)
    }
    
    @objc private func navigateToParentDirectory() {
        guard currentDirectoryPath != documentsDirectory else { return }
        
        let parentDirectory = currentDirectoryPath.deletingLastPathComponent()
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func refreshData() {
        loadFiles()
    }
    
    @objc private func toggleMultiSelectMode() {
        isMultiSelectMode = true
        fileListTableView.allowsMultipleSelection = true
        selectedFiles.removeAll()
        
        // Update navigation items
        navigationItem.leftBarButtonItem = cancelButton
        navigationItem.rightBarButtonItems = [actionButton]
        
        // Update title
        title = NSLocalizedString("Select Items", comment: "Multi-select mode title")
        
        // Reload to show checkmarks
        fileListTableView.reloadData()
    }
    
    @objc private func cancelMultiSelect() {
        isMultiSelectMode = false
        fileListTableView.allowsMultipleSelection = false
        selectedFiles.removeAll()
        
        // Restore navigation items
        setupUI()
        
        // Reload to hide checkmarks
        fileListTableView.reloadData()
    }
    
    @objc private func performBatchAction() {
        guard !selectedFiles.isEmpty else { return }
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Delete Selected", comment: "Delete action"), style: .destructive) { [weak self] _ in
            self?.deleteSelectedFiles()
        })
        
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Move Selected", comment: "Move action"), style: .default) { [weak self] _ in
            self?.moveSelectedFiles()
        })
        
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Share Selected", comment: "Share action"), style: .default) { [weak self] _ in
            self?.shareSelectedFiles()
        })
        
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        
        // For iPad
        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.barButtonItem = actionButton
        }
        
        present(actionSheet, animated: true)
    }
    
    private func deleteSelectedFiles() {
        let alert = UIAlertController(
            title: NSLocalizedString("Confirm Deletion", comment: "Confirm deletion title"),
            message: NSLocalizedString("Are you sure you want to delete the selected items? This cannot be undone.", comment: "Confirm deletion message"),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: "Delete button"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            var failedDeletions = 0
            
            for fileName in self.selectedFiles {
                let fileURL = self.currentDirectoryPath.appendingPathComponent(fileName)
                
                do {
                    try self.fileManager.removeItem(at: fileURL)
                } catch {
                    failedDeletions += 1
                    print("Failed to delete \(fileName): \(error)")
                }
            }
            
            if failedDeletions > 0 {
                self.utilities.showAlert(in: self, title: NSLocalizedString("Deletion Incomplete", comment: "Deletion incomplete title"), message: String(format: NSLocalizedString("Failed to delete %d items", comment: "Deletion incomplete message"), failedDeletions))
            }
            
            self.cancelMultiSelect()
            self.loadFiles()
        })
        
        present(alert, animated: true)
    }
    
    private func moveSelectedFiles() {
        let folderPicker = FolderPickerViewController(rootDirectory: documentsDirectory, currentDirectory: currentDirectoryPath)
        folderPicker.delegate = self
        let navController = UINavigationController(rootViewController: folderPicker)
        present(navController, animated: true)
    }
    
    private func shareSelectedFiles() {
        let fileURLs = selectedFiles.map { currentDirectoryPath.appendingPathComponent($0) }
        
        let activityVC = UIActivityViewController(activityItems: fileURLs, applicationActivities: nil)
        
        // For iPad
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.barButtonItem = actionButton
        }
        
        present(activityVC, animated: true)
    }
    
    private func createNewFile() {
        let alert = UIAlertController(
            title: NSLocalizedString("New File", comment: "New file title"),
            message: NSLocalizedString("Enter a name for the new file", comment: "New file message"),
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("File Name", comment: "File name placeholder")
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Create", comment: "Create button"), style: .default) { [weak self, weak alert] _ in
            guard let self = self, let fileName = alert?.textFields?.first?.text, !fileName.isEmpty else { return }
            
            let newFileURL = self.currentDirectoryPath.appendingPathComponent(fileName)
            
            do {
                try "".write(to: newFileURL, atomically: true, encoding: .utf8)
                self.loadFiles()
                
                // Open the new file for editing
                self.openTextFile(at: newFileURL)
            } catch {
                self.utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Failed to Create File", comment: "Error title"))
            }
        })
        
        present(alert, animated: true)
    }
    // MARK: - App Download
    
    private func showDownloadAppPrompt() {
        let alert = UIAlertController(
            title: NSLocalizedString("Download App", comment: "Download app title"),
            message: NSLocalizedString("Enter the App Store ID or URL of the app you want to download", comment: "Download app message"),
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("App ID or URL", comment: "App ID placeholder")
            textField.keyboardType = .URL
            textField.autocorrectionType = .no
            textField.autocapitalizationType = .none
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Download", comment: "Download button"), style: .default) { [weak self, weak alert] _ in
            guard let self = self, let appIdentifier = alert?.textFields?.first?.text, !appIdentifier.isEmpty else { return }
            
            self.downloadApp(identifier: appIdentifier)
        })
        
        present(alert, animated: true)
    }
    
    private func downloadApp(identifier: String) {
        // Extract app ID from URL if needed
        var appID = identifier
        
        if appID.contains("id") {
            if let idRange = appID.range(of: "id\\d+", options: .regularExpression) {
                appID = String(appID[idRange].dropFirst(2))
            }
        }
        
        // Show progress
        progressView.isHidden = false
        progressView.progress = 0
        
        // Start background task
        startBackgroundTask()
        
        // Initialize downloader
        appDownloader = AppDownload()
        appDownloader?.delegate = self
        
        // Start download
        appDownloader?.downloadApp(withID: appID, to: currentDirectoryPath)
    }
    
    private func startBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.cancelBackgroundTask()
        }
    }
    
    private func cancelBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    @objc private func appDidEnterBackground() {
        // If we're downloading, make sure background task is running
        if appDownloader != nil && appDownloader?.isDownloading == true {
            startBackgroundTask()
        }
    }
    
    @objc private func appWillEnterForeground() {
        // Cancel background task if app is in foreground
        cancelBackgroundTask()
    }
    
    // MARK: - UI Helpers
    
    private func showEmptyState() {
        let emptyLabel = UILabel()
        emptyLabel.text = NSLocalizedString("No files found", comment: "Empty state message")
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = UIFont.systemFont(ofSize: 18)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let emptyImageView = UIImageView(image: UIImage(systemName: "folder"))
        emptyImageView.tintColor = .secondaryLabel
        emptyImageView.contentMode = .scaleAspectFit
        emptyImageView.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView(arrangedSubviews: [emptyImageView, emptyLabel])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.tag = 100 // Tag for identification
        
        // Remove existing empty state if any
        if let existingStackView = view.viewWithTag(100) {
            existingStackView.removeFromSuperview()
        }
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            emptyImageView.heightAnchor.constraint(equalToConstant: 80),
            emptyImageView.widthAnchor.constraint(equalToConstant: 80),
            
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func hideEmptyState() {
        if let emptyStateView = view.viewWithTag(100) {
            emptyStateView.removeFromSuperview()
        }
    }
    
    private func getFileAttributes(for fileName: String) -> (isDirectory: Bool, size: Int64, modificationDate: Date) {
        let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
        var isDirectory: ObjCBool = false
        
        guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            return (false, 0, Date())
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let size = attributes[.size] as? Int64 ?? 0
            let modificationDate = attributes[.modificationDate] as? Date ?? Date()
            
            return (isDirectory.boolValue, size, modificationDate)
        } catch {
            print("Error getting file attributes: \(error)")
            return (isDirectory.boolValue, 0, Date())
        }
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func getFileIcon(for fileName: String, isDirectory: Bool) -> UIImage? {
        if isDirectory {
            return UIImage(systemName: "folder")
        }
        
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        
        switch fileExtension {
        case "txt", "log":
            return UIImage(systemName: "doc.text")
        case "pdf":
            return UIImage(systemName: "doc.text.viewfinder")
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return UIImage(systemName: "photo")
        case "mp4", "mov", "m4v":
            return UIImage(systemName: "film")
        case "mp3", "m4a", "wav":
            return UIImage(systemName: "music.note")
        case "zip", "rar", "7z":
            return UIImage(systemName: "archivebox")
        case "ipa":
            return UIImage(systemName: "app.badge")
        case "plist", "xml", "json":
            return UIImage(systemName: "doc.plaintext")
        case "html", "css", "js":
            return UIImage(systemName: "doc.richtext")
        case "swift", "m", "h", "c", "cpp":
            return UIImage(systemName: "chevron.left.forwardslash.chevron.right")
        default:
            return UIImage(systemName: "doc")
        }
    }
    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = searchController.isActive ? filteredFileList.count : fileList.count
        return count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let fileList = searchController.isActive ? filteredFileList : self.fileList
        guard indexPath.row < fileList.count else { return UITableViewCell() }
        
        let fileName = fileList[indexPath.row]
        let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
        let (isDirectory, size, modificationDate) = getFileAttributes(for: fileName)
        
        // Check if it's an IPA file
        if fileName.lowercased().hasSuffix(".ipa") {
            let cell = tableView.dequeueReusableCell(withIdentifier: "AppCell", for: indexPath) as! AppTableViewCell
            
            // Configure cell
            cell.configure(
                name: fileName.deletingPathExtension,
                fileSize: formatFileSize(size),
                modificationDate: formatDate(modificationDate),
                iconImage: getFileIcon(for: fileName, isDirectory: isDirectory)
            )
            
            // Check if we have app info in CoreData
            if let appInfo = coreDataManager.getAppInfo(forFileName: fileName) {
                cell.updateAppInfo(
                    name: appInfo.name ?? fileName.deletingPathExtension,
                    bundleID: appInfo.bundleID ?? "Unknown",
                    version: appInfo.version ?? "Unknown"
                )
            }
            
            // Set selection style
            cell.selectionStyle = .default
            
            // Set checkmark if in multi-select mode and selected
            if isMultiSelectMode {
                cell.accessoryType = selectedFiles.contains(fileName) ? .checkmark : .none
            } else {
                cell.accessoryType = .none
            }
            
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileTableViewCell
            
            // Configure cell
            cell.configure(
                name: fileName,
                isDirectory: isDirectory,
                fileSize: formatFileSize(size),
                modificationDate: formatDate(modificationDate),
                iconImage: getFileIcon(for: fileName, isDirectory: isDirectory)
            )
            
            // Set selection style
            cell.selectionStyle = .default
            
            // Set checkmark if in multi-select mode and selected
            if isMultiSelectMode {
                cell.accessoryType = selectedFiles.contains(fileName) ? .checkmark : .none
            } else {
                cell.accessoryType = isDirectory ? .disclosureIndicator : .none
            }
            
            return cell
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let fileList = searchController.isActive ? filteredFileList : self.fileList
        guard indexPath.row < fileList.count else { return }
        
        let fileName = fileList[indexPath.row]
        
        if isMultiSelectMode {
            if selectedFiles.contains(fileName) {
                if let index = selectedFiles.firstIndex(of: fileName) {
                    selectedFiles.remove(at: index)
                }
                tableView.cellForRow(at: indexPath)?.accessoryType = .none
            } else {
                selectedFiles.append(fileName)
                tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
            }
            
            // Enable/disable action button based on selection
            actionButton.isEnabled = !selectedFiles.isEmpty
            
            // Update title with count
            title = selectedFiles.isEmpty ? 
                NSLocalizedString("Select Items", comment: "Multi-select mode title") : 
                String(format: NSLocalizedString("%d Selected", comment: "Selected items count"), selectedFiles.count)
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
            openFile(at: indexPath)
        }
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let fileList = searchController.isActive ? filteredFileList : self.fileList
        guard indexPath.row < fileList.count else { return nil }
        
        let fileName = fileList[indexPath.row]
        let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
        
        // Delete action
        let deleteAction = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "Delete action")) { [weak self] (action, view, completionHandler) in
            guard let self = self else { return completionHandler(false) }
            
            let alert = UIAlertController(
                title: NSLocalizedString("Confirm Deletion", comment: "Confirm deletion title"),
                message: String(format: NSLocalizedString("Are you sure you want to delete '%@'?", comment: "Confirm deletion message"), fileName),
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel) { _ in
                completionHandler(false)
            })
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: "Delete button"), style: .destructive) { _ in
                do {
                    try self.fileManager.removeItem(at: fileURL)
                    self.loadFiles()
                    completionHandler(true)
                } catch {
                    self.utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Deletion Failed", comment: "Error title"))
                    completionHandler(false)
                }
            })
            
            self.present(alert, animated: true)
        }
        
        // Rename action
        let renameAction = UIContextualAction(style: .normal, title: NSLocalizedString("Rename", comment: "Rename action")) { [weak self] (action, view, completionHandler) in
            guard let self = self else { return completionHandler(false) }
            
            let alert = UIAlertController(
                title: NSLocalizedString("Rename File", comment: "Rename title"),
                message: NSLocalizedString("Enter a new name", comment: "Rename message"),
                preferredStyle: .alert
            )
            
            alert.addTextField { textField in
                textField.text = fileName
            }
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel) { _ in
                completionHandler(false)
            })
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Rename", comment: "Rename button"), style: .default) { _ in
                guard let newName = alert.textFields?.first?.text, !newName.isEmpty, newName != fileName else {
                    completionHandler(false)
                    return
                }
                
                let newFileURL = self.currentDirectoryPath.appendingPathComponent(newName)
                
                do {
                    try self.fileManager.moveItem(at: fileURL, to: newFileURL)
                    self.loadFiles()
                    completionHandler(true)
                } catch {
                    self.utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Rename Failed", comment: "Error title"))
                    completionHandler(false)
                }
            })
            
            self.present(alert, animated: true)
        }
        
        // Share action
        let shareAction = UIContextualAction(style: .normal, title: NSLocalizedString("Share", comment: "Share action")) { [weak self] (action, view, completionHandler) in
            guard let self = self else { return completionHandler(false) }
            
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            
            // For iPad
            if let popoverController = activityVC.popoverPresentationController {
                popoverController.sourceView = tableView.cellForRow(at: indexPath)
                popoverController.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
            }
            
            self.present(activityVC, animated: true)
            completionHandler(true)
        }
        
        // Customize action colors
        renameAction.backgroundColor = .systemBlue
        shareAction.backgroundColor = .systemGreen
        
        return UISwipeActionsConfiguration(actions: [deleteAction, renameAction, shareAction])
    }
    
    // MARK: - UITableViewDragDelegate
    
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let fileList = searchController.isActive ? filteredFileList : self.fileList
        guard indexPath.row < fileList.count else { return [] }
        
        let fileName = fileList[indexPath.row]
        let fileURL = currentDirectoryPath.appendingPathComponent(fileName)
        
        let itemProvider = NSItemProvider(object: fileURL as NSURL)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = fileName
        
        return [dragItem]
    }
    
    // MARK: - UITableViewDropDelegate
    
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }
        
        for item in coordinator.items {
            guard let sourceIndexPath = item.sourceIndexPath else { continue }
            
            // Only allow reordering if not searching and not in a subdirectory
            if searchController.isActive || currentDirectoryPath != documentsDirectory {
                return
            }
            
            // Update data source
            let movedItem = fileList.remove(at: sourceIndexPath.row)
            fileList.insert(movedItem, at: destinationIndexPath.row)
            
            // Update UI
            tableView.moveRow(at: sourceIndexPath, to: destinationIndexPath)
        }
    }
    
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        // Only allow reordering if not searching and not in a subdirectory
        if searchController.isActive || currentDirectoryPath != documentsDirectory {
            return UITableViewDropProposal(operation: .forbidden)
        }
        
        if session.localDragSession != nil {
            return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        
        return UITableViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
    }
    // MARK: - UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text else { return }
        filterContentForSearchText(searchText)
    }
    
    private func filterContentForSearchText(_ searchText: String) {
        if searchText.isEmpty {
            filteredFileList = fileList
        } else {
            filteredFileList = fileList.filter { fileName in
                return fileName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        fileListTableView.reloadData()
    }
    
    // MARK: - UIDocumentPickerDelegate
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        activityIndicator.startAnimating()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var importErrors = 0
            
            for url in urls {
                let fileName = url.lastPathComponent
                let destinationURL = self.currentDirectoryPath.appendingPathComponent(fileName)
                
                // Check if file already exists
                if self.fileManager.fileExists(atPath: destinationURL.path) {
                    // Generate unique name
                    let fileNameWithoutExtension = url.deletingPathExtension().lastPathComponent
                    let fileExtension = url.pathExtension
                    let newFileName = "\(fileNameWithoutExtension)_\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
                    let newDestinationURL = self.currentDirectoryPath.appendingPathComponent(newFileName)
                    
                    do {
                        try self.fileManager.copyItem(at: url, to: newDestinationURL)
                    } catch {
                        importErrors += 1
                        print("Error importing file: \(error)")
                    }
                } else {
                    do {
                        try self.fileManager.copyItem(at: url, to: destinationURL)
                    } catch {
                        importErrors += 1
                        print("Error importing file: \(error)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                self.loadFiles()
                
                if importErrors > 0 {
                    self.utilities.showAlert(in: self, title: NSLocalizedString("Import Incomplete", comment: "Import incomplete title"), message: String(format: NSLocalizedString("Failed to import %d files", comment: "Import incomplete message"), importErrors))
                }
            }
        }
    }
    
    // MARK: - UIDocumentInteractionControllerDelegate
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        // Refresh file list in case file was modified
        loadFiles()
    }
    
    // MARK: - FolderPickerDelegate
    
    func folderPicker(_ folderPicker: FolderPickerViewController, didSelectFolder folderURL: URL) {
        guard !selectedFiles.isEmpty else { return }
        
        var moveErrors = 0
        
        for fileName in selectedFiles {
            let sourceURL = currentDirectoryPath.appendingPathComponent(fileName)
            let destinationURL = folderURL.appendingPathComponent(fileName)
            
            // Check if file already exists at destination
            if fileManager.fileExists(atPath: destinationURL.path) {
                // Generate unique name
                let fileNameWithoutExtension = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
                let fileExtension = URL(fileURLWithPath: fileName).pathExtension
                let newFileName = "\(fileNameWithoutExtension)_\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
                let newDestinationURL = folderURL.appendingPathComponent(newFileName)
                
                do {
                    try fileManager.moveItem(at: sourceURL, to: newDestinationURL)
                } catch {
                    moveErrors += 1
                    print("Error moving file: \(error)")
                }
            } else {
                do {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                } catch {
                    moveErrors += 1
                    print("Error moving file: \(error)")
                }
            }
        }
        
        // Exit multi-select mode
        cancelMultiSelect()
        
        // Refresh file list
        loadFiles()
        
        if moveErrors > 0 {
            utilities.showAlert(in: self, title: NSLocalizedString("Move Incomplete", comment: "Move incomplete title"), message: String(format: NSLocalizedString("Failed to move %d files", comment: "Move incomplete message"), moveErrors))
        }
    }
    
    // MARK: - DownloadDelegate
    
    func downloadProgress(progress: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.progressView.progress = progress
            self?.downloadProgress = progress
        }
    }
    
    func downloadDidFinish(fileURL: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.progressView.progress = 1.0
            self.downloadProgress = 1.0
            
            // If it's an IPA file, extract it
            if fileURL.pathExtension.lowercased() == "ipa" {
                self.extractIPA(at: fileURL)
            } else {
                self.progressView.isHidden = true
                self.loadFiles()
                self.utilities.showAlert(in: self, title: NSLocalizedString("Download Complete", comment: "Download complete title"), message: NSLocalizedString("File downloaded successfully", comment: "Download complete message"))
            }
            
            // End background task
            self.cancelBackgroundTask()
            self.appDownloader = nil
        }
    }
    
    func downloadDidFail(with error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.progressView.isHidden = true
            self.utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Download Failed", comment: "Download failed title"))
            
            // End background task
            self.cancelBackgroundTask()
            self.appDownloader = nil
        }
    }
    
    func extractionProgress(progress: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.progressView.progress = progress
            self?.extractionProgress = progress
        }
    }
    
    func extractionDidFinish(directoryURL: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.progressView.isHidden = true
            self.loadFiles()
            self.utilities.showAlert(in: self, title: NSLocalizedString("Extraction Complete", comment: "Extraction complete title"), message: NSLocalizedString("App extracted successfully", comment: "Extraction complete message"))
        }
    }
    
    func extractionDidFail(with error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.progressView.isHidden = true
            self.utilities.handleError(in: self, error: error, withTitle: NSLocalizedString("Extraction Failed", comment: "Extraction failed title"))
        }
    }
    
    // MARK: - TextEditorDelegate
    
    func textEditorDidSave(_ editor: TextEditorViewController) {
        loadFiles()
    }
}

// MARK: - UITableView Extensions

extension HomeViewController: UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate {}

// MARK: - UISearchResultsUpdating Extension

extension HomeViewController: UISearchResultsUpdating {}

// MARK: - UIDocumentPickerDelegate Extension

extension HomeViewController: UIDocumentPickerDelegate {}

// MARK: - UIDocumentInteractionControllerDelegate Extension

extension HomeViewController: UIDocumentInteractionControllerDelegate {}

// MARK: - FolderPickerDelegate Extension

extension HomeViewController: FolderPickerDelegate {}

// MARK: - TextEditorDelegate Extension

extension HomeViewController: TextEditorDelegate {}

// MARK: - FileHandlingDelegate Extension

extension HomeViewController: FileHandlingDelegate {}
// MARK: - FileTableViewCell

class FileTableViewCell: UITableViewCell {
    
    // MARK: - UI Components
    
    private let fileIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let fileNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let fileSizeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        contentView.addSubview(fileIconImageView)
        contentView.addSubview(fileNameLabel)
        contentView.addSubview(fileSizeLabel)
        contentView.addSubview(dateLabel)
        
        NSLayoutConstraint.activate([
            fileIconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            fileIconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fileIconImageView.widthAnchor.constraint(equalToConstant: 40),
            fileIconImageView.heightAnchor.constraint(equalToConstant: 40),
            
            fileNameLabel.leadingAnchor.constraint(equalTo: fileIconImageView.trailingAnchor, constant: 12),
            fileNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            fileNameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            
            fileSizeLabel.leadingAnchor.constraint(equalTo: fileIconImageView.trailingAnchor, constant: 12),
            fileSizeLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 4),
            
            dateLabel.leadingAnchor.constraint(equalTo: fileSizeLabel.trailingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            dateLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 4)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(name: String, isDirectory: Bool, fileSize: String, modificationDate: String, iconImage: UIImage?) {
        fileNameLabel.text = name
        fileSizeLabel.text = fileSize
        dateLabel.text = modificationDate
        fileIconImageView.image = iconImage
        
        // Make directory names bold
        if isDirectory {
            fileNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        } else {
            fileNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        fileNameLabel.text = nil
        fileSizeLabel.text = nil
        dateLabel.text = nil
        fileIconImageView.image = nil
        accessoryType = .none
    }
}
// MARK: - AppTableViewCell

class AppTableViewCell: UITableViewCell {
    
    // MARK: - UI Components
    
    private let appIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        imageView.layer.cornerRadius = 10
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let appNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bundleIDLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let versionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let fileSizeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        contentView.addSubview(appIconImageView)
        contentView.addSubview(appNameLabel)
        contentView.addSubview(bundleIDLabel)
        contentView.addSubview(versionLabel)
        contentView.addSubview(fileSizeLabel)
        contentView.addSubview(dateLabel)
        
        NSLayoutConstraint.activate([
            appIconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            appIconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            appIconImageView.widthAnchor.constraint(equalToConstant: 50),
            appIconImageView.heightAnchor.constraint(equalToConstant: 50),
            
            appNameLabel.leadingAnchor.constraint(equalTo: appIconImageView.trailingAnchor, constant: 12),
            appNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            appNameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            
            bundleIDLabel.leadingAnchor.constraint(equalTo: appIconImageView.trailingAnchor, constant: 12),
            bundleIDLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 2),
            
            versionLabel.leadingAnchor.constraint(equalTo: bundleIDLabel.trailingAnchor, constant: 8),
            versionLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            versionLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 2),
            
            fileSizeLabel.leadingAnchor.constraint(equalTo: appIconImageView.trailingAnchor, constant: 12),
            fileSizeLabel.topAnchor.constraint(equalTo: bundleIDLabel.bottomAnchor, constant: 2),
            
            dateLabel.leadingAnchor.constraint(equalTo: fileSizeLabel.trailingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            dateLabel.topAnchor.constraint(equalTo: bundleIDLabel.bottomAnchor, constant: 2)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(name: String, fileSize: String, modificationDate: String, iconImage: UIImage?) {
        appNameLabel.text = name
        fileSizeLabel.text = fileSize
        dateLabel.text = modificationDate
        appIconImageView.image = iconImage
        
        // Hide app-specific info until we have it
        bundleIDLabel.isHidden = true
        versionLabel.isHidden = true
    }
    
    func updateAppInfo(name: String, bundleID: String, version: String) {
        appNameLabel.text = name
        bundleIDLabel.text = bundleID
        versionLabel.text = "v\(version)"
        
        // Show app-specific info
        bundleIDLabel.isHidden = false
        versionLabel.isHidden = false
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        appNameLabel.text = nil
        bundleIDLabel.text = nil
        versionLabel.text = nil
        fileSizeLabel.text = nil
        dateLabel.text = nil
        appIconImageView.image = nil
        accessoryType = .none
        
        // Hide app-specific info
        bundleIDLabel.isHidden = true
        versionLabel.isHidden = true
    }
}
// MARK: - HomeViewUtilities

class HomeViewUtilities {
    
    func handleError(in viewController: UIViewController, error: Error, withTitle title: String) {
        let message = error.localizedDescription
        showAlert(in: viewController, title: title, message: message)
        
        // Log error
        os_log("Error: %{public}@", log: OSLog.default, type: .error, message)
    }
    
    func showAlert(in viewController: UIViewController, title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: .default))
        viewController.present(alert, animated: true)
    }
    
    func showConfirmationAlert(in viewController: UIViewController, title: String, message: String, confirmTitle: String, cancelTitle: String = NSLocalizedString("Cancel", comment: "Cancel button"), confirmHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
        
        alert.addAction(UIAlertAction(title: confirmTitle, style: .default) { _ in
            confirmHandler()
        })
        
        viewController.present(alert, animated: true)
    }
}
// MARK: - HomeViewFileHandlers

class HomeViewFileHandlers {
    
    private let fileManager = FileManager.default
    
    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }
    
    func deleteFile(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
    
    func moveFile(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }
    
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
    
    func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }
    
    func getFileAttributes(for url: URL) -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            print("Error getting file attributes: \(error)")
            return nil
        }
    }
}
// MARK: - AppDownload

protocol DownloadDelegate: AnyObject {
    func downloadProgress(progress: Float)
    func downloadDidFinish(fileURL: URL)
    func downloadDidFail(with error: Error)
    func extractionProgress(progress: Float)
    func extractionDidFinish(directoryURL: URL)
    func extractionDidFail(with error: Error)
}

class AppDownload: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: DownloadDelegate?
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession!
    private var destinationDirectory: URL?
    private var isDownloading = false
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Download Methods
    
    func downloadApp(withID appID: String, to directory: URL) {
        guard !isDownloading else { return }
        
        isDownloading = true
        destinationDirectory = directory
        
        // First, fetch the iTunes metadata to get the download URL
        let metadataURL = URL(string: "https://itunes.apple.com/lookup?id=\(appID)")!
        
        let task = URLSession.shared.dataTask(with: metadataURL) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.isDownloading = false
                self.delegate?.downloadDidFail(with: error)
                return
            }
            
            guard let data = data else {
                self.isDownloading = false
                self.delegate?.downloadDidFail(with: NSError(domain: "AppDownloadError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let firstResult = results.first,
                   let trackName = firstResult["trackName"] as? String,
                   let bundleID = firstResult["bundleId"] as? String {
                    
                    // Now we have the app info, start the actual download
                    self.startDownload(appID: appID, appName: trackName, bundleID: bundleID)
                } else {
                    self.isDownloading = false
                    self.delegate?.downloadDidFail(with: NSError(domain: "AppDownloadError", code: 2, userInfo: [NSLocalizedDescriptionKey: "App not found"]))
                }
            } catch {
                self.isDownloading = false
                self.delegate?.downloadDidFail(with: error)
            }
        }
        
        task.resume()
    }
    
    private func startDownload(appID: String, appName: String, bundleID: String) {
        // Create a URL for the app download
        // Note: This is a placeholder. In a real app, you would need to use a proper API or service
        // that can provide IPA downloads, which is not officially supported by Apple
        let downloadURLString = "https://example.com/apps/\(appID)/download"
        guard let downloadURL = URL(string: downloadURLString) else {
            isDownloading = false
            delegate?.downloadDidFail(with: NSError(domain: "AppDownloadError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"]))
            return
        }
        
        downloadTask = session.downloadTask(with: downloadURL)
        downloadTask?.resume()
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        isDownloading = false
    }
}

// MARK: - URLSessionDownloadDelegate

extension AppDownload: URLSessionDownloadDelegate {
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destinationDirectory = destinationDirectory else {
            isDownloading = false
            delegate?.downloadDidFail(with: NSError(domain: "AppDownloadError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Destination directory not set"]))
            return
        }
        
        // Get suggested filename from the response
        var fileName = "app.ipa"
        if let suggestedFilename = downloadTask.response?.suggestedFilename {
            fileName = suggestedFilename
        } else if let url = downloadTask.originalRequest?.url?.lastPathComponent, !url.isEmpty {
            fileName = url
        }
        
        // Ensure it has .ipa extension
        if !fileName.lowercased().hasSuffix(".ipa") {
            fileName += ".ipa"
        }
        
        let destinationURL = destinationDirectory.appendingPathComponent(fileName)
        
        do {
            // Remove existing file if needed
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Move downloaded file to destination
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            isDownloading = false
            delegate?.downloadDidFinish(fileURL: destinationURL)
        } catch {
            isDownloading = false
            delegate?.downloadDidFail(with: error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        delegate?.downloadProgress(progress: progress)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            isDownloading = false
            delegate?.downloadDidFail(with: error)
        }
    }
}
// MARK: - TextEditorViewController

protocol TextEditorDelegate: AnyObject {
    func textEditorDidSave(_ editor: TextEditorViewController)
}

class TextEditorViewController: UIViewController {
    
    // MARK: - Properties
    
    private let fileURL: URL
    private var text: String
    private var isModified = false
    weak var delegate: TextEditorDelegate?
    
    // MARK: - UI Components
    
    private let textView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    // MARK: - Initialization
    
    init(fileURL: URL, text: String) {
        self.fileURL = fileURL
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureNavigationBar()
        
        // Set text
        textView.text = text
        textView.delegate = self
        
        // Set title
        title = fileURL.lastPathComponent
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Add text view
        view.addSubview(textView)
        
        // Set constraints
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func configureNavigationBar() {
        // Add save button
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveFile))
        
        // Add share button
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareFile))
        
        // Add find button
        let findButton = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(findInText))
        
        navigationItem.rightBarButtonItems = [saveButton, shareButton, findButton]
        
        // Add cancel button
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.leftBarButtonItem = cancelButton
    }
    // MARK: - Actions
    
    @objc private func saveFile() {
        do {
            try textView.text.write(to: fileURL, atomically: true, encoding: .utf8)
            isModified = false
            delegate?.textEditorDidSave(self)
            dismiss(animated: true)
        } catch {
            showAlert(title: NSLocalizedString("Save Failed", comment: "Save failed title"), message: error.localizedDescription)
        }
    }
    
    @objc private func shareFile() {
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        
        // For iPad
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItems?[1]
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func findInText() {
        let alertController = UIAlertController(
            title: NSLocalizedString("Find", comment: "Find title"),
            message: NSLocalizedString("Enter text to search for", comment: "Find message"),
            preferredStyle: .alert
        )
        
        alertController.addTextField { textField in
            textField.placeholder = NSLocalizedString("Search text", comment: "Search placeholder")
            textField.clearButtonMode = .whileEditing
            textField.autocapitalizationType = .none
        }
        
        let searchAction = UIAlertAction(title: NSLocalizedString("Find", comment: "Find button"), style: .default) { [weak self, weak alertController] _ in
            guard let self = self, let searchText = alertController?.textFields?.first?.text, !searchText.isEmpty else { return }
            
            self.performSearch(searchText)
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel)
        
        alertController.addAction(searchAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true)
    }
    
    private func performSearch(_ searchText: String) {
        guard let textRange = textView.text.range(of: searchText, options: .caseInsensitive) else {
            showAlert(title: NSLocalizedString("Not Found", comment: "Not found title"), message: NSLocalizedString("The text was not found", comment: "Not found message"))
            return
        }
        
        let nsRange = NSRange(textRange, in: textView.text)
        textView.selectedRange = nsRange
        textView.scrollRangeToVisible(nsRange)
    }
    
    @objc private func cancel() {
        if isModified {
            let alertController = UIAlertController(
                title: NSLocalizedString("Unsaved Changes", comment: "Unsaved changes title"),
                message: NSLocalizedString("Do you want to save your changes?", comment: "Unsaved changes message"),
                preferredStyle: .alert
            )
            
            let saveAction = UIAlertAction(title: NSLocalizedString("Save", comment: "Save button"), style: .default) { [weak self] _ in
                self?.saveFile()
            }
            
            let discardAction = UIAlertAction(title: NSLocalizedString("Discard", comment: "Discard button"), style: .destructive) { [weak self] _ in
                self?.dismiss(animated: true)
            }
            
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel)
            
            alertController.addAction(saveAction)
            alertController.addAction(discardAction)
            alertController.addAction(cancelAction)
            
            present(alertController, animated: true)
        } else {
            dismiss(animated: true)
        }
    }
// MARK: - ImageViewerViewController

class ImageViewerViewController: UIViewController {
    
    // MARK: - Properties
    
    private let imageURL: URL
    private var image: UIImage?
    
    // MARK: - UI Components
    
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    // MARK: - Initialization
    
    init(imageURL: URL) {
        self.imageURL = imageURL
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureNavigationBar()
        loadImage()
        
        // Set title
        title = imageURL.lastPathComponent
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Add scroll view
        view.addSubview(scrollView)
        
        // Add image view to scroll view
        scrollView.addSubview(imageView)
        
        // Set constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
        
        // Set up scroll view delegate
        scrollView.delegate = self
        
        // Add double tap gesture for zoom
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
    }
    
    private func configureNavigationBar() {
        // Add share button
        let shareButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareImage))
        
        // Add save button
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveToPhotos))
        
        navigationItem.rightBarButtonItems = [shareButton, saveButton]
        
        // Add done button
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismiss(_:)))
        navigationItem.leftBarButtonItem = doneButton
    }
    // MARK: - Image Loading
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let imageData = try Data(contentsOf: self.imageURL)
                if let image = UIImage(data: imageData) {
                    self.image = image
                    
                    DispatchQueue.main.async {
                        self.imageView.image = image
                        self.updateZoomScaleForSize(self.view.bounds.size)
                    }
                } else {
                    self.showErrorAlert(message: NSLocalizedString("Failed to load image", comment: "Image load error"))
                }
            } catch {
                self.showErrorAlert(message: error.localizedDescription)
            }
        }
    }
    
    private func updateZoomScaleForSize(_ size: CGSize) {
        guard let image = image, image.size.width > 0, image.size.height > 0 else { return }
        
        let widthScale = size.width / image.size.width
        let heightScale = size.height / image.size.height
        let minScale = min(widthScale, heightScale)
        
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = minScale * 3.0
        scrollView.zoomScale = minScale
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateZoomScaleForSize(view.bounds.size)
    }
    
    // MARK: - Actions
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let scrollSize = scrollView.frame.size
            
            let width = scrollSize.width / scrollView.maximumZoomScale
            let height = scrollSize.height / scrollView.maximumZoomScale
            let x = point.x - (width / 2.0)
            let y = point.y - (height / 2.0)
            
            let rect = CGRect(x: x, y: y, width: width, height: height)
            scrollView.zoom(to: rect, animated: true)
        }
    }
    
    @objc private func shareImage() {
        guard let image = image else { return }
        
        let activityVC = UIActivityViewController(activityItems: [image, imageURL], applicationActivities: nil)
        
        // For iPad
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItems?[0]
        }
        
        present(activityVC, animated: true)
    }
    @objc private func saveToPhotos() {
        guard let image = image else { return }
        
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            showErrorAlert(message: error.localizedDescription)
        } else {
            let alert = UIAlertController(
                title: NSLocalizedString("Saved", comment: "Save success title"),
                message: NSLocalizedString("Image has been saved to your photos", comment: "Save success message"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: .default))
            present(alert, animated: true)
        }
    }
    
    @objc private func dismiss(_ sender: UIBarButtonItem) {
        dismiss(animated: true)
    }
    
    // MARK: - Helper Methods
    
    private func showErrorAlert(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(
                title: NSLocalizedString("Error", comment: "Error title"),
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: .default))
            self.present(alert, animated: true)
        }
    }
}

// MARK: - UIScrollViewDelegate

extension ImageViewerViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Center the image when zooming
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: 0, right: 0)
    }
}
// MARK: - FolderPickerViewController

protocol FolderPickerDelegate: AnyObject {
    func folderPicker(_ folderPicker: FolderPickerViewController, didSelectFolder folderURL: URL)
}

class FolderPickerViewController: UIViewController {
    
    // MARK: - Properties
    
    private let rootDirectory: URL
    private var currentDirectory: URL
    private var folderList: [String] = []
    private let fileManager = FileManager.default
    weak var delegate: FolderPickerDelegate?
    
    // MARK: - UI Components
    
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    // MARK: - Initialization
    
    init(rootDirectory: URL, currentDirectory: URL) {
        self.rootDirectory = rootDirectory
        self.currentDirectory = currentDirectory
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureNavigationBar()
        loadFolders()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Register cell
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FolderCell")
        
        // Set delegates
        tableView.delegate = self
        tableView.dataSource = self
        
        // Add table view
        view.addSubview(tableView)
        
        // Set constraints
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func configureNavigationBar() {
        title = NSLocalizedString("Select Folder", comment: "Folder picker title")
        
        // Add cancel button
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.leftBarButtonItem = cancelButton
        
        // Add select button
        let selectButton = UIBarButtonItem(title: NSLocalizedString("Select", comment: "Select button"), style: .done, target: self, action: #selector(selectCurrentFolder))
        navigationItem.rightBarButtonItem = selectButton
        
        // Add new folder button
        let newFolderButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createNewFolder))
        navigationItem.rightBarButtonItems = [selectButton, newFolderButton]
    }
    // MARK: - Data Loading
    
    private func loadFolders() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            
            // Filter to only include directories
            folderList = contents.compactMap { url in
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                    return resourceValues.isDirectory == true ? url.lastPathComponent : nil
                } catch {
                    return nil
                }
            }.sorted()
            
            tableView.reloadData()
            
            // Update title
            title = currentDirectory.lastPathComponent
        } catch {
            showErrorAlert(message: error.localizedDescription)
        }
    }
    
    // MARK: - Actions
    
    @objc private func cancel() {
        dismiss(animated: true)
    }
    
    @objc private func selectCurrentFolder() {
        delegate?.folderPicker(self, didSelectFolder: currentDirectory)
        dismiss(animated: true)
    }
    
    @objc private func createNewFolder() {
        let alert = UIAlertController(
            title: NSLocalizedString("New Folder", comment: "New folder title"),
            message: NSLocalizedString("Enter a name for the new folder", comment: "New folder message"),
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("Folder Name", comment: "Folder name placeholder")
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel button"), style: .cancel))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Create", comment: "Create button"), style: .default) { [weak self, weak alert] _ in
            guard let self = self, let folderName = alert?.textFields?.first?.text, !folderName.isEmpty else { return }
            
            let newFolderURL = self.currentDirectory.appendingPathComponent(folderName)
            
            do {
                try self.fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
                self.loadFolders()
            } catch {
                self.showErrorAlert(message: error.localizedDescription)
            }
        })
        
        present(alert, animated: true)
    }
    // MARK: - Helper Methods
    
    private func navigateToFolder(at index: Int) {
        guard index < folderList.count else { return }
        
        let folderName = folderList[index]
        let folderURL = currentDirectory.appendingPathComponent(folderName)
        
        currentDirectory = folderURL
        loadFolders()
    }
    
    private func navigateUp() {
        // Don't go above root directory
        if currentDirectory.path != rootDirectory.path {
            currentDirectory = currentDirectory.deletingLastPathComponent()
            loadFolders()
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(
            title: NSLocalizedString("Error", comment: "Error title"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "OK button"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension FolderPickerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Add 1 for the "Parent Directory" option if we're not at the root
        return currentDirectory.path != rootDirectory.path ? folderList.count + 1 : folderList.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FolderCell", for: indexPath)
        
        if currentDirectory.path != rootDirectory.path && indexPath.row == 0 {
            // Parent directory option
            cell.textLabel?.text = NSLocalizedString("../ (Parent Directory)", comment: "Parent directory")
            cell.imageView?.image = UIImage(systemName: "arrow.up.doc.fill")
        } else {
            // Adjust index if we have parent directory option
            let folderIndex = currentDirectory.path != rootDirectory.path ? indexPath.row - 1 : indexPath.row
            
            if folderIndex < folderList.count {
                cell.textLabel?.text = folderList[folderIndex]
                cell.imageView?.image = UIImage(systemName: "folder")
            }
        }
        
        return cell
    }
}
// MARK: - UITableViewDelegate

extension FolderPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if currentDirectory.path != rootDirectory.path && indexPath.row == 0 {
            // Navigate to parent directory
            navigateUp()
        } else {
            // Adjust index if we have parent directory option
            let folderIndex = currentDirectory.path != rootDirectory.path ? indexPath.row - 1 : indexPath.row
            
            if folderIndex < folderList.count {
                navigateToFolder(at: folderIndex)
            }
        }
    }
}
