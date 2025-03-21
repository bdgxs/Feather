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

    private func filterContentForSearchText(_ searchText: String) {
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
        fileListTableView.reloadData()
    }

    private func showProgressAlert(title: String, message: String) -> UIAlertController {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let activityIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        activityIndicator.style = .large
        activityIndicator.startAnimating()
        alert.view.addSubview(activityIndicator)
        present(alert, animated: true, completion: nil)
        return alert
    }

    private func dismissProgressAlert(alert: UIAlertController) {
        alert.dismiss(animated: true, completion: nil)
    }

    private func unzipFile(at fileURL: URL) {
        do {
            let destinationURL = currentDirectoryPath.appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent)
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.unzipItem(at: fileURL, to: destinationURL)
            loadFiles()
        } catch {
            utilities.handleError(in: self, error: error, withTitle: "Unzip Failed")
        }
    }

    private func deleteFile(at fileURL: URL) {
        do {
            try fileManager.removeItem(at: fileURL)
            loadFiles()
        } catch {
            utilities.handleError(in: self, error: error, withTitle: "Delete Failed")
        }
    }

    private func renameFile(at fileURL: URL, newName: String) {
        let newURL = fileURL.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try fileManager.moveItem(at: fileURL, to: newURL)
            loadFiles()
        } catch {
            utilities.handleError(in: self, error: error, withTitle: "Rename Failed")
        }
    }

    @objc private func showMenu() {
        let menuAlert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let sortByNameAction = UIAlertAction(title: "Sort by Name", style: .default) { [weak self] _ in
            self?.sortOrder = .name
            self?.sortFiles()
        }
        let sortByDateAction = UIAlertAction(title: "Sort by Date", style: .default) { [weak self] _ in
            self?.sortOrder = .date
            self?.sortFiles()
        }
        let sortBySizeAction = UIAlertAction(title: "Sort by Size", style: .default) { [weak self] _ in
            self?.sortOrder = .size
            self?.sortFiles()
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        menuAlert.addAction(sortByNameAction)
        menuAlert.addAction(sortByDateAction)
        menuAlert.addAction(sortBySizeAction)
        menuAlert.addAction(cancelAction)
        
        present(menuAlert, animated: true, completion: nil)
    }

    @objc private func importFile() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }

    @objc private func addDirectory() {
        let alertController = UIAlertController(title: "New Folder", message: "Enter the name of the new folder", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "Folder Name"
        }
        
        let createAction = UIAlertAction(title: "Create", style: .default) { [weak self, weak alertController] _ in
            guard let self = self, let textField = alertController?.textFields?.first, let folderName = textField.text, !folderName.isEmpty else { return }
            let newFolderURL = self.currentDirectoryPath.appendingPathComponent(folderName)
            do {
                try self.fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
                self.loadFiles()
            } catch {
                self.utilities.handleError(in: self, error: error, withTitle: "Failed to Create Folder")
            }
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        alertController.addAction(createAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true, completion: nil)
    }

    @objc private func navigateToParentDirectory() {
        let parentDirectory = currentDirectoryPath.deletingLastPathComponent()
        let parentVC = HomeViewController(directoryPath: parentDirectory)
        navigationController?.pushViewController(parentVC, animated: true)
    }

    @objc private func refreshData() {
        loadFiles()
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
            filterContentForSearchText(searchText)
        } else {
            filteredFileList = fileList
            fileListTableView.reloadData()
        }
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

        let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
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
    let itemProvider = NSItemProvider(contentsOf: fileURL)
    let dragItem = UIDragItem(itemProvider: itemProvider!)
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
            if let urlData = urlData as? URL {
                let destinationURL = self.currentDirectoryPath.appendingPathComponent(self.fileList[destinationIndexPath.row]).appendingPathComponent(urlData.lastPathComponent)
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

class FileTableViewCell: UITableViewCell {
    let fileNameLabel = UILabel()
    let fileImageView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }

    private func setupCell() {
        fileImageView.translatesAutoresizingMaskIntoConstraints = false
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fileImageView)
        contentView.addSubview(fileNameLabel)
        
        NSLayoutConstraint.activate([
            fileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            fileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fileImageView.widthAnchor.constraint(equalToConstant: 40),
            fileImageView.heightAnchor.constraint(equalToConstant: 40),
            
            fileNameLabel.leadingAnchor.constraint(equalTo: fileImageView.trailingAnchor, constant: 15),
            fileNameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fileNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15)
        ])
    }

    func configure(with fileName: String) {
        fileNameLabel.text = fileName
        fileImageView.image = UIImage(systemName: "doc")
    }
}

class AppTableViewCell: UITableViewCell {
    let fileNameLabel = UILabel()
    let fileImageView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }

    private func setupCell() {
        fileImageView.translatesAutoresizingMaskIntoConstraints = false
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fileImageView)
        contentView.addSubview(fileNameLabel)

        NSLayoutConstraint.activate([
            fileImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            fileImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fileImageView.widthAnchor.constraint(equalToConstant: 40),
            fileImageView.heightAnchor.constraint(equalToConstant: 40),
            
            fileNameLabel.leadingAnchor.constraint(equalTo: fileImageView.trailingAnchor, constant: 15),
            fileNameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fileNameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15)
        ])
    }

    func configure(with fileName: String) {
        fileNameLabel.text = fileName
        fileImageView.image = UIImage(systemName: "app")
    }
}

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

// MARK: - AES Encryption/Decryption using CommonCrypto

struct AES {
    static func encrypt(_ data: Data, password: String) throws -> Data {
        // Implementation using CommonCrypto
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        // Implementation using CommonCrypto
    }
}

// MARK: - App Download

class AppDownload: NSObject, URLSessionDownloadDelegate {
    var downloadTask: URLSessionDownloadTask?
    var progressHandler: ((Float) -> Void)?
    var completionHandler: ((URL?, Error?) -> Void)?
    var destination: URL?

    func downloadApp(from url: URL, to destination: URL) {
        self.destination = destination
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
            guard let destination = destination else { return }
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