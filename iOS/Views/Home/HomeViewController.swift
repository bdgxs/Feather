import UIKit
import ZIPFoundation
import Foundation
import os.log
import UniformTypeIdentifiers

// MARK: - Protocols
protocol FileHandlingDelegate: AnyObject {
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
    func loadFiles()
    var documentsDirectory: URL { get }
}

class HomeViewController: UIViewController {
    
    // MARK: - Properties
    private var fileList: [String] = []
    private var filteredFileList: [String] = []
    private let fileManager = FileManager.default
    private let searchController = UISearchController(searchResultsController: nil)
    private var sortOrder: SortOrder = .name
    let fileHandlers = HomeViewFileHandlers()
    let utilities = HomeViewUtilities()
    
    var documentsDirectory: URL {
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("files")
        createFilesDirectoryIfNeeded(at: directory)
        return directory
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
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        let navItem = UINavigationItem(title: "Files")
        let menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(showMenu))
        let uploadButton = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(importFile))
        let addButton = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"), style: .plain, target: self, action: #selector(addDirectory))
        
        navItem.rightBarButtonItems = [menuButton, uploadButton, addButton]
        navigationController?.navigationBar.setItems([navItem], animated: false)
        
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search Files"
        navigationItem.searchController = searchController
        definesPresentationContext = true
        
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
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func configureTableView() {
        fileListTableView.delegate = self
        fileListTableView.dataSource = self
        fileListTableView.dragDelegate = self
        fileListTableView.dropDelegate = self
        fileListTableView.dragInteractionEnabled = true
        fileListTableView.register(FileTableViewCell.self, forCellReuseIdentifier: "FileCell")
        fileListTableView.rowHeight = 70
    }
    
    private func createFilesDirectoryIfNeeded(at directory: URL) {
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                utilities.handleError(in: self, error: error, withTitle: "Directory Creation Failed")
            }
        }
    }
    
    // MARK: - File Operations
    func loadFiles() {
        activityIndicator.startAnimating()
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            do {
                let files = try self.fileManager.contentsOfDirectory(atPath: self.documentsDirectory.path)
                DispatchQueue.main.async {
                    self.fileList = files
                    self.sortFiles()
                    self.fileListTableView.reloadData()
                    self.activityIndicator.stopAnimating()
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.utilities.handleError(in: self, error: error, withTitle: "Failed to Load Files")
                }
            }
        }
    }
    
    @objc private func importFile() {
        let documentTypes: [UTType] = [.zip, .item, .content, .data, .text, .image]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: documentTypes)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        present(documentPicker, animated: true, completion: nil)
    }
    
    func handleImportedFile(url: URL) {
        let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        
        activityIndicator.startAnimating()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    if url.pathExtension.lowercased() == "zip" {
                        try self.fileManager.unzipItem(at: url, to: self.documentsDirectory)
                    } else {
                        if self.fileManager.fileExists(atPath: destinationURL.path) {
                            try self.fileManager.removeItem(at: destinationURL)
                        }
                        try self.fileManager.copyItem(at: url, to: destinationURL)
                    }
                    
                    DispatchQueue.main.async {
                        self.activityIndicator.stopAnimating()
                        self.loadFiles()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.utilities.handleError(in: self, error: error, withTitle: "Import Failed")
                }
            }
        }
    }
    
    func deleteFile(at index: Int) {
        let fileToDelete = fileList[index]
        let fileURL = documentsDirectory.appendingPathComponent(fileToDelete)
        
        do {
            try fileManager.removeItem(at: fileURL)
            fileList.remove(at: index)
            fileListTableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
        } catch {
            utilities.handleError(in: self, error: error, withTitle: "Delete Failed")
        }
    }
    
    func sortFiles() {
        switch sortOrder {
        case .name:
            fileList.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .date:
            fileList.sort { file1, file2 in
                let url1 = documentsDirectory.appendingPathComponent(file1)
                let url2 = documentsDirectory.appendingPathComponent(file2)
                
                guard let date1 = fileManager.modificationDate(at: url1.path),
                      let date2 = fileManager.modificationDate(at: url2.path) else {
                    return file1.localizedCaseInsensitiveCompare(file2) == .orderedAscending
                }
                
                return date1 > date2
            }
        case .size:
            fileList.sort { file1, file2 in
                let url1 = documentsDirectory.appendingPathComponent(file1)
                let url2 = documentsDirectory.appendingPathComponent(file2)
                
                guard let size1 = fileManager.fileSize(at: url1.path),
                      let size2 = fileManager.fileSize(at: url2.path) else {
                    return file1.localizedCaseInsensitiveCompare(file2) == .orderedAscending
                }
                
                return size1 > size2
            }
        }
    }
    
    // MARK: - UI Actions
    @objc private func showMenu() {
        let alertController = UIAlertController(title: "Sort By", message: nil, preferredStyle: .actionSheet)
        
        let sortByNameAction = UIAlertAction(title: "Name", style: .default) { [weak self] _ in
            self?.sortOrder = .name
            self?.sortFiles()
            self?.fileListTableView.reloadData()
        }
        alertController.addAction(sortByNameAction)
        
        let sortByDateAction = UIAlertAction(title: "Date (Newest First)", style: .default) { [weak self] _ in
            self?.sortOrder = .date
            self?.sortFiles()
            self?.fileListTableView.reloadData()
        }
        alertController.addAction(sortByDateAction)
        
        let sortBySizeAction = UIAlertAction(title: "Size (Largest First)", style: .default) { [weak self] _ in
            self?.sortOrder = .size
            self?.sortFiles()
            self?.fileListTableView.reloadData()
        }
        alertController.addAction(sortBySizeAction)
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        // For iPad support
        if let popoverController = alertController.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(alertController, animated: true, completion: nil)
    }
    
    @objc private func addDirectory() {
        let alertController = UIAlertController(title: "New Directory", message: "Enter directory name:", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "Directory Name"
        }
        let createAction = UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let directoryName = alertController.textFields?.first?.text,
                  !directoryName.isEmpty else {
                return
            }
            
            let newDirectoryURL = self.documentsDirectory.appendingPathComponent(directoryName)
            
            do {
                try self.fileManager.createDirectory(at: newDirectoryURL, withIntermediateDirectories: false, attributes: nil)
                self.loadFiles()
            } catch {
                self.utilities.handleError(in: self, error: error, withTitle: "Directory Creation Failed")
            }
        }
        alertController.addAction(createAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }
    
    // MARK: - File Handling Methods
    func showFileOptions(for fileURL: URL) {
        let isDirectory = fileManager.isDirectory(at: fileURL)
        let fileName = fileURL.lastPathComponent
        
        let alertController = UIAlertController(title: fileName, message: nil, preferredStyle: .actionSheet)
        
        if isDirectory {
            // Directory options
            alertController.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
                self?.openDirectory(at: fileURL)
            })
        } else {
            // File options
            alertController.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
                self?.openFile(at: fileURL)
            })
            
            alertController.addAction(UIAlertAction(title: "Edit", style: .default) { [weak self] _ in
                self?.editFile(at: fileURL)
            })
            
            alertController.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
                self?.shareFile(at: fileURL)
            })
        }
        
        // Common options
        alertController.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.promptRename(for: fileURL)
        })
        
        alertController.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.promptDelete(for: fileURL)
        })
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad support
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(alertController, animated: true)
    }
    
    func openDirectory(at directoryURL: URL) {
        let directoryVC = HomeViewController()
        directoryVC.title = directoryURL.lastPathComponent
        // Set up a custom documentsDirectory property for the new VC
        navigationController?.pushViewController(directoryVC, animated: true)
    }
    
    func openFile(at fileURL: URL) {
        let pathExtension = fileURL.pathExtension.lowercased()
        
        switch pathExtension {
        case "txt", "log", "json", "md", "xml", "html", "css", "js":
            let textEditor = TextEditorViewController(fileURL: fileURL)
            navigationController?.pushViewController(textEditor, animated: true)
        case "plist":
            let plistEditor = PlistEditorViewController(fileURL: fileURL)
            navigationController?.pushViewController(plistEditor, animated: true)
        case "jpg", "jpeg", "png", "gif":
            let imageViewer = ImageViewerViewController(fileURL: fileURL)
            navigationController?.pushViewController(imageViewer, animated: true)
        case "pdf":
            let pdfViewer = PDFViewerViewController(fileURL: fileURL)
            navigationController?.pushViewController(pdfViewer, animated: true)
        default:
            // Use document interaction controller for other file types
            let documentInteractionController = UIDocumentInteractionController(url: fileURL)
            documentInteractionController.delegate = self
            documentInteractionController.presentPreview(animated: true)
    func editFile(at fileURL: URL) {
        let pathExtension = fileURL.pathExtension.lowercased()
        
        switch pathExtension {
        case "txt", "log", "json", "md", "xml", "html", "css", "js":
            let textEditor = TextEditorViewController(fileURL: fileURL)
            navigationController?.pushViewController(textEditor, animated: true)
        case "plist":
            let plistEditor = PlistEditorViewController(fileURL: fileURL)
            navigationController?.pushViewController(plistEditor, animated: true)
        default:
            let hexEditor = HexEditorViewController(fileURL: fileURL)
            navigationController?.pushViewController(hexEditor, animated: true)
        }
    }
    
    func shareFile(at fileURL: URL) {
        let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        
        // For iPad support
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        present(activityViewController, animated: true)
    }
    
    func promptRename(for fileURL: URL) {
        let alertController = UIAlertController(title: "Rename", message: "Enter new name:", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.text = fileURL.lastPathComponent
        }
        
        let renameAction = UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            guard let self = self, let newName = alertController.textFields?.first?.text, !newName.isEmpty else {
                return
            }
            
            let newURL = fileURL.deletingLastPathComponent().appendingPathComponent(newName)
            
            do {
                try self.fileManager.moveItem(at: fileURL, to: newURL)
                self.loadFiles()
            } catch {
                self.utilities.handleError(in: self, error: error, withTitle: "Rename Failed")
            }
        }
        
        alertController.addAction(renameAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alertController, animated: true)
    }
    
    func promptDelete(for fileURL: URL) {
        let alertController = UIAlertController(
            title: "Delete \(fileURL.lastPathComponent)?",
            message: "This action cannot be undone.",
            preferredStyle: .alert
        )
        
        let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            do {
                try self.fileManager.removeItem(at: fileURL)
                self.loadFiles()
            } catch {
                self.utilities.handleError(in: self, error: error, withTitle: "Delete Failed")
            }
        }
        
        alertController.addAction(deleteAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alertController, animated: true)
    }
}

// MARK: - UISearchResultsUpdating Extension
extension HomeViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        filterContentForSearchText(searchController.searchBar.text ?? "")
    }
    
    private func filterContentForSearchText(_ searchText: String) {
        if searchText.isEmpty {
            filteredFileList = fileList
        } else {
            filteredFileList = fileList.filter { $0.lowercased().contains(searchText.lowercased()) }
        }
        fileListTableView.reloadData()
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource Extensions
extension HomeViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchController.isActive ? filteredFileList.count : fileList.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileTableViewCell
        let fileName = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        let file = File(url: fileURL)
        cell.configure(with: file)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let fileName = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        showFileOptions(for: fileURL)
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let fileName = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (_, _, completionHandler) in
            self?.promptDelete(for: fileURL)
            completionHandler(true)
        }
        deleteAction.image = UIImage(systemName: "trash")
        
        let renameAction = UIContextualAction(style: .normal, title: "Rename") { [weak self] (_, _, completionHandler) in
            self?.promptRename(for: fileURL)
            completionHandler(true)
        }
        renameAction.image = UIImage(systemName: "pencil")
        renameAction.backgroundColor = .systemBlue
        
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction, renameAction])
        return configuration
    }
}
// MARK: - UITableViewDragDelegate Extension
extension HomeViewController: UITableViewDragDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let fileName = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        let itemProvider = NSItemProvider(contentsOf: fileURL)
        let dragItem = UIDragItem(itemProvider: itemProvider ?? NSItemProvider())
        dragItem.localObject = fileName
        return [dragItem]
    }
    
    func tableView(_ tableView: UITableView, dragSessionWillBegin session: UIDragSession) {
        // Optional: Add visual feedback when drag begins
    }
    
    func tableView(_ tableView: UITableView, dragSessionDidEnd session: UIDragSession) {
        // Optional: Clean up after drag ends
    }
}

// MARK: - UITableViewDropDelegate Extension
extension HomeViewController: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, canHandle session: UIDropSession) -> Bool {
        return session.hasItemsConforming(toTypeIdentifiers: [UTType.item.identifier])
    }
    
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        if session.localDragSession != nil {
            return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        return UITableViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
    }
    
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        let destinationIndexPath: IndexPath
        
        if let indexPath = coordinator.destinationIndexPath {
            destinationIndexPath = indexPath
        } else {
            let section = tableView.numberOfSections - 1
            let row = tableView.numberOfRows(inSection: section)
            destinationIndexPath = IndexPath(row: row, section: section)
        }
        
        switch coordinator.proposal.operation {
        case .move:
            guard let item = coordinator.items.first,
                  let sourceIndexPath = item.sourceIndexPath,
                  let sourceFileName = item.dragItem.localObject as? String else {
                return
            }
            
            // Handle reordering
            self.reorderItems(coordinator: coordinator, destinationIndexPath: destinationIndexPath, sourceIndexPath: sourceIndexPath)
            
        case .copy:
            // Handle items from outside the app
            for item in coordinator.items {
                item.dragItem.itemProvider.loadItem(forTypeIdentifier: UTType.item.identifier, options: nil) { (data, error) in
                    guard let url = data as? URL else { return }
                    
                    DispatchQueue.main.async {
                        self.handleImportedFile(url: url)
                    }
                }
            }
            
        default:
            return
        }
    }
    
    private func reorderItems(coordinator: UITableViewDropCoordinator, destinationIndexPath: IndexPath, sourceIndexPath: IndexPath) {
        guard let item = coordinator.items.first,
              let sourceFileName = item.dragItem.localObject as? String else {
            return
        }
        
        fileListTableView.performBatchUpdates({
            if searchController.isActive {
                let sourceItem = filteredFileList[sourceIndexPath.row]
                filteredFileList.remove(at: sourceIndexPath.row)
                filteredFileList.insert(sourceItem, at: destinationIndexPath.row)
                
                // Also update the main fileList
                if let sourceIndex = fileList.firstIndex(of: sourceItem),
                   let destIndex = fileList.firstIndex(of: filteredFileList[destinationIndexPath.row]) {
                    fileList.remove(at: sourceIndex)
                    fileList.insert(sourceItem, at: destIndex)
                }
            } else {
                let sourceItem = fileList[sourceIndexPath.row]
                fileList.remove(at: sourceIndexPath.row)
                fileList.insert(sourceItem, at: destinationIndexPath.row)
            }
            
            fileListTableView.deleteRows(at: [sourceIndexPath], with: .automatic)
            fileListTableView.insertRows(at: [destinationIndexPath], with: .automatic)
        })
        
        coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
    }
}

// MARK: - UIDocumentPickerDelegate Extension
extension HomeViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            handleImportedFile(url: url)
        }
    }
}

// MARK: - UIDocumentInteractionControllerDelegate Extension
extension HomeViewController: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
}

// MARK: - FileHandlingDelegate Extension
extension HomeViewController: FileHandlingDelegate {}

// MARK: - File Model
class File {
    let url: URL
    var name: String { return url.lastPathComponent }
    var size: UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? UInt64 ?? 0
    }
    var date: Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date ?? Date.distantPast
    }
    var isDirectory: Bool {
        return FileManager.default.isDirectory(at: url)
    }
    
    init(url: URL) {
        self.url = url
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var icon: UIImage {
        if isDirectory {
            return UIImage(systemName: "folder") ?? UIImage()
        }
        
        switch url.pathExtension.lowercased() {
        case "pdf":
            return UIImage(systemName: "doc.text") ?? UIImage()
        case "jpg", "jpeg", "png", "gif", "heic":
            return UIImage(systemName: "photo") ?? UIImage()
        case "mp4", "mov", "avi":
            return UIImage(systemName: "film") ?? UIImage()
        case "mp3", "wav", "aac", "m4a":
            return UIImage(systemName: "music.note") ?? UIImage()
        case "zip", "rar", "7z":
            return UIImage(systemName: "archivebox") ?? UIImage()
        case "plist", "xml":
            return UIImage(systemName: "list.bullet") ?? UIImage()
        case "txt", "rtf", "md":
            return UIImage(systemName: "doc.text") ?? UIImage()
        case "html", "css", "js":
            return UIImage(systemName: "doc.text.code") ?? UIImage()
        default:
            return UIImage(systemName: "doc") ?? UIImage()
        }
    }
}
// MARK: - FileTableViewCell
class FileTableViewCell: UITableViewCell {
    // UI Components
    private let fileIconImageView = UIImageView()
    private let fileNameLabel = UILabel()
    private let fileSizeLabel = UILabel()
    private let fileDateLabel = UILabel()
    private let accessoryIconView = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Configure icon
        fileIconImageView.contentMode = .scaleAspectFit
        fileIconImageView.tintColor = .systemBlue
        contentView.addSubview(fileIconImageView)
        
        // Configure labels
        fileNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        fileNameLabel.textColor = .label
        contentView.addSubview(fileNameLabel)
        
        fileSizeLabel.font = UIFont.systemFont(ofSize: 12)
        fileSizeLabel.textColor = .secondaryLabel
        contentView.addSubview(fileSizeLabel)
        
        fileDateLabel.font = UIFont.systemFont(ofSize: 12)
        fileDateLabel.textColor = .secondaryLabel
        contentView.addSubview(fileDateLabel)
        
        // Configure accessory
        accessoryIconView.image = UIImage(systemName: "chevron.right")
        accessoryIconView.tintColor = .tertiaryLabel
        accessoryIconView.contentMode = .scaleAspectFit
        contentView.addSubview(accessoryIconView)
        
        // Set up constraints
        fileIconImageView.translatesAutoresizingMaskIntoConstraints = false
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        fileSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        fileDateLabel.translatesAutoresizingMaskIntoConstraints = false
        accessoryIconView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            fileIconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            fileIconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            fileIconImageView.widthAnchor.constraint(equalToConstant: 40),
            fileIconImageView.heightAnchor.constraint(equalToConstant: 40),
            
            fileNameLabel.leadingAnchor.constraint(equalTo: fileIconImageView.trailingAnchor, constant: 12),
            fileNameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            fileNameLabel.trailingAnchor.constraint(equalTo: accessoryIconView.leadingAnchor, constant: -8),
            
            fileSizeLabel.leadingAnchor.constraint(equalTo: fileNameLabel.leadingAnchor),
            fileSizeLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 4),
            fileSizeLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
            
            fileDateLabel.leadingAnchor.constraint(equalTo: fileSizeLabel.trailingAnchor, constant: 16),
            fileDateLabel.centerYAnchor.constraint(equalTo: fileSizeLabel.centerYAnchor),
            fileDateLabel.trailingAnchor.constraint(equalTo: fileNameLabel.trailingAnchor),
            
            accessoryIconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            accessoryIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            accessoryIconView.widthAnchor.constraint(equalToConstant: 12),
            accessoryIconView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    func configure(with file: File) {
        fileNameLabel.text = file.name
        fileSizeLabel.text = file.formattedSize
        fileDateLabel.text = file.formattedDate
        fileIconImageView.image = file.icon
        
        // Add directory indicator
        if file.isDirectory {
            accessoryType = .disclosureIndicator
            accessoryIconView.isHidden = true
        } else {
            accessoryType = .none
            accessoryIconView.isHidden = false
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        fileNameLabel.text = nil
        fileSizeLabel.text = nil
        fileDateLabel.text = nil
        fileIconImageView.image = nil
    }
}

// MARK: - HomeViewFileHandlers
class HomeViewFileHandlers {
    private let fileManager = FileManager.default
    private let utilities = HomeViewUtilities()
    
    func uploadFile(viewController: FileHandlingDelegate) {
        let documentTypes: [UTType] = [.zip, .item, .content, .data, .text, .image]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: documentTypes)
        documentPicker.delegate = viewController as? UIDocumentPickerDelegate
        documentPicker.allowsMultipleSelection = true
        viewController.present(documentPicker, animated: true, completion: nil)
    }
    
    func createDirectory(at url: URL, withName name: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let directoryURL = url.appendingPathComponent(name)
        
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false, attributes: nil)
            completion(.success(directoryURL))
        } catch {
            completion(.failure(error))
        }
    }
    
    func deleteItem(at url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try fileManager.removeItem(at: url)
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    func renameItem(at url: URL, to newName: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        
        do {
            try fileManager.moveItem(at: url, to: newURL)
            completion(.success(newURL))
        } catch {
            completion(.failure(error))
        }
    }
    
    func copyItem(at sourceURL: URL, to destinationURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            completion(.success(destinationURL))
        } catch {
            completion(.failure(error))
        }
    }
    
    func moveItem(at sourceURL: URL, to destinationURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            completion(.success(destinationURL))
        } catch {
            completion(.failure(error))
        }
    }
    
    func unzipItem(at zipURL: URL, to destinationURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            try fileManager.unzipItem(at: zipURL, to: destinationURL)
            completion(.success(destinationURL))
        } catch {
            completion(.failure(error))
        }
    }
}
// MARK: - HomeViewUtilities
class HomeViewUtilities {
    func handleError(in viewController: UIViewController, error: Error, withTitle title: String) {
        let alertController = UIAlertController(
            title: title,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alertController, animated: true)
        
        // Log the error
        os_log("Error: %{public}@", log: OSLog.default, type: .error, error.localizedDescription)
    }
    
    func showAlert(in viewController: UIViewController, title: String, message: String, actions: [UIAlertAction] = []) {
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        if actions.isEmpty {
            alertController.addAction(UIAlertAction(title: "OK", style: .default))
        } else {
            for action in actions {
                alertController.addAction(action)
            }
        }
        
        viewController.present(alertController, animated: true)
    }
    
    func showActionSheet(in viewController: UIViewController, title: String?, message: String?, actions: [UIAlertAction]) {
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .actionSheet
        )
        
        for action in actions {
            alertController.addAction(action)
        }
        
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad support
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = viewController.view
            popoverController.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        viewController.present(alertController, animated: true)
    }
}

// MARK: - FileManager Extensions
extension FileManager {
    func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
    
    func fileSize(at path: String) -> UInt64? {
        do {
            let attributes = try attributesOfItem(atPath: path)
            return attributes[.size] as? UInt64
        } catch {
            return nil
        }
    }
    
    func modificationDate(at path: String) -> Date? {
        do {
            let attributes = try attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }
    
    func createDirectoryIfNeeded(at url: URL) throws {
        if !fileExists(atPath: url.path) {
            try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    func contentsOfDirectoryWithAttributes(at url: URL) throws -> [(url: URL, attributes: [FileAttributeKey: Any])] {
        let contents = try contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        return try contents.map { fileURL in
            let attributes = try attributesOfItem(atPath: fileURL.path)
            return (fileURL, attributes)
        }
    }
}

// MARK: - TextEditorViewController
class TextEditorViewController: UIViewController {
    private let fileURL: URL
    private let textView = UITextView()
    private let fileManager = FileManager.default
    
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
        loadTextContent()
    }
    
    private func setupUI() {
        title = fileURL.lastPathComponent
        view.backgroundColor = .systemBackground
        
        // Configure text view
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Add save button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTextContent)
        )
    }
    
    private func loadTextContent() {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            textView.text = content
        } catch {
            textView.text = "Error loading file: \(error.localizedDescription)"
            textView.isEditable = false
        }
    }
    
    @objc private func saveTextContent() {
        do {
            try textView.text.write(to: fileURL, atomically: true, encoding: .utf8)
            let alertController = UIAlertController(
                title: "Saved",
                message: "File has been saved successfully.",
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default))
            present(alertController, animated: true)
        } catch {
            let alertController = UIAlertController(
                title: "Save Failed",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default))
            present(alertController, animated: true)
        }
    }
}
// MARK: - PlistEditorViewController
class PlistEditorViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let fileURL: URL
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var plistData: [String: Any] = [:]
    private var keys: [String] = []
    
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
        loadPlistContent()
    }
    
    private func setupUI() {
        title = fileURL.lastPathComponent
        view.backgroundColor = .systemBackground
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PlistCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(savePlistContent)
        )
    }
    
    private func loadPlistContent() {
        do {
            let data = try Data(contentsOf: fileURL)
            var format = PropertyListSerialization.PropertyListFormat.xml
            plistData = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &format) as? [String: Any] ?? [:]
            keys = plistData.keys.sorted()
            tableView.reloadData()
        } catch {
            showAlert(title: "Error Loading Plist", message: error.localizedDescription)
        }
    }
    
    @objc private func savePlistContent() {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plistData, format: .xml, options: 0)
            try data.write(to: fileURL)
            showAlert(title: "Saved", message: "Plist file has been saved successfully.")
        } catch {
            showAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
    
    // MARK: - UITableViewDataSource
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return keys.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlistCell", for: indexPath)
        let key = keys[indexPath.row]
        let value = plistData[key]
        
        var configuration = cell.defaultContentConfiguration()
        configuration.text = key
        
        if let stringValue = value as? String {
            configuration.secondaryText = stringValue
        } else if let numberValue = value as? NSNumber {
            configuration.secondaryText = numberValue.stringValue
        } else if let arrayValue = value as? [Any] {
            configuration.secondaryText = "Array (\(arrayValue.count) items)"
        } else if let dictValue = value as? [String: Any] {
            configuration.secondaryText = "Dictionary (\(dictValue.count) items)"
        } else if let boolValue = value as? Bool {
            configuration.secondaryText = boolValue ? "true" : "false"
        } else if value == nil {
            configuration.secondaryText = "nil"
        } else {
            configuration.secondaryText = "Unsupported type"
        }
        
        cell.contentConfiguration = configuration
        return cell
    }
    
    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let key = keys[indexPath.row]
        let value = plistData[key]
        
        if let stringValue = value as? String {
            showEditStringAlert(for: key, value: stringValue)
        } else if let numberValue = value as? NSNumber {
            showEditNumberAlert(for: key, value: numberValue)
        } else if let boolValue = value as? Bool {
            toggleBoolValue(for: key, value: boolValue)
        } else {
            showAlert(title: "Unsupported Type", message: "Editing this type is not supported in this viewer.")
        }
    }
    
    private func showEditStringAlert(for key: String, value: String) {
        let alertController = UIAlertController(
            title: "Edit Value",
            message: "Key: \(key)",
            preferredStyle: .alert
        )
        
        alertController.addTextField { textField in
            textField.text = value
        }
        
        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self, let newValue = alertController.textFields?.first?.text else { return }
            self.plistData[key] = newValue
            self.tableView.reloadData()
        }
        
        alertController.addAction(saveAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alertController, animated: true)
    }
    
    private func showEditNumberAlert(for key: String, value: NSNumber) {
        let alertController = UIAlertController(
            title: "Edit Value",
            message: "Key: \(key)",
            preferredStyle: .alert
        )
        
        alertController.addTextField { textField in
            textField.text = value.stringValue
            textField.keyboardType = .numbersAndPunctuation
        }
        
        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self, let text = alertController.textFields?.first?.text else { return }
            
            if let intValue = Int(text) {
                self.plistData[key] = intValue
            } else if let doubleValue = Double(text) {
                self.plistData[key] = doubleValue
            } else {
                self.showAlert(title: "Invalid Number", message: "Please enter a valid number.")
                return
            }
            
            self.tableView.reloadData()
        }
        
        alertController.addAction(saveAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alertController, animated: true)
    }
    
    private func toggleBoolValue(for key: String, value: Bool) {
        plistData[key] = !value
        tableView.reloadData()
    }
}
// MARK: - ImageViewerViewController
class ImageViewerViewController: UIViewController {
    private let fileURL: URL
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    
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
        loadImage()
    }
    
    private func setupUI() {
        title = fileURL.lastPathComponent
        view.backgroundColor = .systemBackground
        
        // Configure scroll view
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        // Configure image view
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
        
        // Add share button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareImage)
        )
        
        // Add double tap gesture recognizer
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
    }
    
    private func loadImage() {
        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            showErrorAlert(message: "Failed to load image.")
            return
        }
        
        imageView.image = image
    }
    
    @objc private func shareImage() {
        guard let image = imageView.image else { return }
        
        let activityViewController = UIActivityViewController(
            activityItems: [image, fileURL],
            applicationActivities: nil
        )
        
        // For iPad support
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityViewController, animated: true)
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let scrollSize = scrollView.frame.size
            let size = CGSize(
                width: scrollSize.width / scrollView.maximumZoomScale,
                height: scrollSize.height / scrollView.maximumZoomScale
            )
            let origin = CGPoint(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2
            )
            scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }
    
    private func showErrorAlert(message: String) {
        let alertController = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
}

// MARK: - UIScrollViewDelegate Extension for ImageViewerViewController
extension ImageViewerViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageInScrollView()
    }
    
    private func centerImageInScrollView() {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        
        scrollView.contentInset = UIEdgeInsets(
            top: offsetY,
            left: offsetX,
            bottom: 0,
            right: 0
        )
    }
}

// MARK: - PDFViewerViewController
class PDFViewerViewController: UIViewController {
    private let fileURL: URL
    private let webView = WKWebView()
    
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
        loadPDF()
    }
    
    private func setupUI() {
        title = fileURL.lastPathComponent
        view.backgroundColor = .systemBackground
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Add share button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(sharePDF)
        )
    }
    
    private func loadPDF() {
        webView.load(URLRequest(url: fileURL))
    }
    
    @objc private func sharePDF() {
        let activityViewController = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        
        // For iPad support
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityViewController, animated: true)
    }
}
// MARK: - HexEditorViewController
class HexEditorViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let fileURL: URL
    private let tableView = UITableView()
    private var fileData: Data?
    private let bytesPerRow = 16
    
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
        loadFileData()
    }
    
    private func setupUI() {
        title = fileURL.lastPathComponent
        view.backgroundColor = .systemBackground
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(HexTableViewCell.self, forCellReuseIdentifier: "HexCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func loadFileData() {
        do {
            fileData = try Data(contentsOf: fileURL)
            tableView.reloadData()
        } catch {
            showErrorAlert(message: "Failed to load file data: \(error.localizedDescription)")
        }
    }
    
    private func showErrorAlert(message: String) {
        let alertController = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
    
    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let data = fileData else { return 0 }
        return Int(ceil(Double(data.count) / Double(bytesPerRow)))
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HexCell", for: indexPath) as! HexTableViewCell
        
        guard let data = fileData else { return cell }
        
        let startOffset = indexPath.row * bytesPerRow
        let endOffset = min(startOffset + bytesPerRow, data.count)
        let rowData = data[startOffset..<endOffset]
        
        cell.configure(withOffset: startOffset, data: rowData, bytesPerRow: bytesPerRow)
        return cell
    }
    
    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }
}

// MARK: - HexTableViewCell
class HexTableViewCell: UITableViewCell {
    private let offsetLabel = UILabel()
    private let hexLabel = UILabel()
    private let asciiLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Configure offset label
        offsetLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        offsetLabel.textColor = .secondaryLabel
        offsetLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(offsetLabel)
        
        // Configure hex label
        hexLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        hexLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hexLabel)
        
        // Configure ASCII label
        asciiLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        asciiLabel.textColor = .secondaryLabel
        asciiLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(asciiLabel)
        
        NSLayoutConstraint.activate([
            offsetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            offsetLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            offsetLabel.widthAnchor.constraint(equalToConstant: 80),
            
            hexLabel.leadingAnchor.constraint(equalTo: offsetLabel.trailingAnchor, constant: 8),
            hexLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            asciiLabel.leadingAnchor.constraint(equalTo: hexLabel.trailingAnchor, constant: 16),
            asciiLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            asciiLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    func configure(withOffset offset: Int, data: Data, bytesPerRow: Int) {
        // Format offset
        offsetLabel.text = String(format: "0x%08X", offset)
        
        // Format hex representation
        var hexString = ""
        var asciiString = ""
        
        for (index, byte) in data.enumerated() {
            hexString += String(format: "%02X ", byte)
            
            // Add space after 8 bytes for better readability
            if index == 7 {
                hexString += " "
            }
            
            // Format ASCII representation
            if byte >= 32 && byte <= 126 { // Printable ASCII range
                asciiString += String(UnicodeScalar(byte))
            } else {
                asciiString += "."
            }
        }
        
        // Pad hex string to align all rows
        let missingBytes = bytesPerRow - data.count
        if missingBytes > 0 {
            for i in 0..<missingBytes {
                hexString += "   "
                // Add extra space after 8 bytes
                if data.count + i == 7 {
                    hexString += " "
                }
            }
        }
        
        hexLabel.text = hexString
        asciiLabel.text = asciiString
    }
}

// MARK: - ZIPFoundation Implementation
// This is a simplified version of ZIPFoundation for the purpose of this example
// In a real app, you would use the actual ZIPFoundation library
extension FileManager {
    func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        // This is a placeholder for the actual ZIPFoundation implementation
        // In a real app, you would use the ZIPFoundation library's unzipItem method
        
        // For demonstration purposes, we'll create a simple directory structure
        // to simulate unzipping a file
        
        let tempDirectory = destinationURL.appendingPathComponent(UUID().uuidString)
        try createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Create a README.txt file in the unzipped directory
        let readmeURL = tempDirectory.appendingPathComponent("README.txt")
        let readmeContent = "This is a simulated unzipped file from \(sourceURL.lastPathComponent)."
        try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
        
        // Create a sample directory in the unzipped directory
        let sampleDirURL = tempDirectory.appendingPathComponent("sample_directory")
        try createDirectory(at: sampleDirURL, withIntermediateDirectories: true, attributes: nil)
        
        // Create a sample file in the sample directory
        let sampleFileURL = sampleDirURL.appendingPathComponent("sample_file.txt")
        let sampleContent = "This is a sample file in the unzipped directory."
        try sampleContent.write(to: sampleFileURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - WKWebView Import
import WebKit

// MARK: - AppDelegate
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        
        let homeViewController = HomeViewController()
        let navigationController = UINavigationController(rootViewController: homeViewController)
        
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
        
        return true
    }
}
