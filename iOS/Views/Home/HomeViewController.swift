import UIKit
import ZIPFoundation
import Foundation

class HomeViewController: UIViewController, UISearchResultsUpdating, UITableViewDragDelegate, UITableViewDropDelegate, UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate, UITextViewDelegate {
    
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
                print("Error loading files: \(error)")
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                }
            }
        }
    }

    @objc private func importFile() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .item])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true, completion: nil)
    }

    func handleImportedFile(url: URL) {
        let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                if url.startAccessingSecurityScopedResource() {
                    if url.pathExtension == "zip" {
                        try self.fileManager.unzipItem(at: url, to: destinationURL, progress: nil)
                    } else {
                        try self.fileManager.copyItem(at: url, to: destinationURL)
                    }
                    url.stopAccessingSecurityScopedResource()
                    DispatchQueue.main.async {
                        self.loadFiles()
                    }
                }
            } catch {
                print("Error handling file: \(error)")
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
            print("Error deleting file: \(error)")
        }
    }

    func sortFiles() {
        switch sortOrder {
        case .name:
            fileList.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .date:
            // Implement sorting by date
            fileList.sort { 
                let url1 = documentsDirectory.appendingPathComponent($0)
                let url2 = documentsDirectory.appendingPathComponent($1)
                return try! fileManager.attributesOfItem(atPath: url1.path)[.creationDate] as? Date ?? Date() < try! fileManager.attributesOfItem(atPath: url2.path)[.creationDate] as? Date ?? Date()
            }
        case .size:
            // Implement sorting by size
            fileList.sort {
                let url1 = documentsDirectory.appendingPathComponent($0)
                let url2 = documentsDirectory.appendingPathComponent($1)
                return try! fileManager.attributesOfItem(atPath: url1.path)[.size] as? UInt64 ?? 0 < try! fileManager.attributesOfItem(atPath: url2.path)[.size] as? UInt64 ?? 0
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
        let sortByDateAction = UIAlertAction(title: "Date", style: .default) { [weak self] _ in
            self?.sortOrder = .date
            self?.sortFiles()
            self?.fileListTableView.reloadData()
        }
        alertController.addAction(sortByDateAction)
        let sortBySizeAction = UIAlertAction(title: "Size", style: .default) { [weak self] _ in
            self?.sortOrder = .size
            self?.sortFiles()
            self?.fileListTableView.reloadData()
        }
        alertController.addAction(sortBySizeAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    @objc private func addDirectory() {
        let alertController = UIAlertController(title: "New Directory", message: "Enter directory name:", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "Directory Name"
        }
        let createAction = UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let directoryName = alertController.textFields?.first?.text, !directoryName.isEmpty else {
                return
            }
            let newDirectoryURL = self?.documentsDirectory.appendingPathComponent(directoryName)
            do {
                try self?.fileManager.createDirectory(at: newDirectoryURL!, withIntermediateDirectories: false, attributes: nil)
                self?.loadFiles()
            } catch {
                print("Error creating directory: \(error)")
            }
        }
        alertController.addAction(createAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

    // MARK: - Search Updating
    func updateSearchResults(for searchController: UISearchController) {
        filterContentForSearchText(searchController.searchBar.text!)
    }

    private func filterContentForSearchText(_ searchText: String) {
        if searchText.isEmpty {
            filteredFileList = fileList
        } else {
            filteredFileList = fileList.filter { $0.lowercased().contains(searchText.lowercased()) }
        }
        fileListTableView.reloadData()
    }

    // MARK: - TableView Data Source & Delegate
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

    // MARK: - Document Picker Delegate
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedFileURL = urls.first else { return }
        handleImportedFile(url: selectedFileURL)
    }

    // MARK: - Helper Functions
    private func createFilesDirectoryIfNeeded(at directory: URL) {
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating directory: \(error)")
            }
        }
    }
}