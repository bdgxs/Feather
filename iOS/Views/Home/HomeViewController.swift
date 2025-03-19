import UIKit
 import ZIPFoundation
 import Foundation
 

 class HomeViewController: UIViewController, UISearchResultsUpdating, UITableViewDragDelegate, UITableViewDropDelegate, UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate, UITextViewDelegate {
  
  // MARK: - Properties
  private var fileList: [String] =
  private var filteredFileList: [String] =
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
  let addButton = UIBarButtonItem(image:
  UIImage(systemName: "folder.badge.plus"), style: .plain, target: self, action: #selector(addDirectory)) // Add Directory button
 

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
  fileListTableView.register(FileTableViewCell.self, forCellReuseIdentifier: "FileCell")
  }
 

  private func createFilesDirectoryIfNeeded(at directory: URL) {
  if !fileManager.fileExists(atPath: directory.path) {
  do {
  try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
  } catch {
  print("Error creating directory: \(error)")
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
  print("Error loading files: \(error)")
  DispatchQueue.main.async {
  self.activityIndicator.stopAnimating()
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
  let progressHandler: Progress?
  = nil // Adjust to match expected type
  try self.fileManager.unzipItem(at: url, to: destinationURL, progress: progressHandler)
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
  // Need to implement file date retrieval and
  break
  case .size:
  // Need to implement file size retrieval and sorting
  break
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
 

  let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
  alertController.addAction(cancelAction)
 

  present(alertController, animated: true, completion: nil)
  }
 }
 

 // MARK: - Extensions
 extension HomeViewController: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
  guard let selectedFileURL = urls.first else {
  return
  }
 

  handleImportedFile(url: selectedFileURL)
  }
 }
 

 extension FileManager {
  func fileSize(at path: String) -> UInt64? {
  do {
  let attr = try attributesOfItem(atPath: path)
  return attr[.size] as? UInt64
  } catch {
  return nil
  }
  }
 

  func creationDate(at path: String) -> Date? {
  do {
  let attr = try attributesOfItem(atPath: path)
  return attr[.creationDate] as? Date
  } catch {
  return nil
  }
  }
 }
 

 // MARK: - TableView Extensions
 

 extension HomeViewController: UITableViewDelegate, UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
  return searchController.isActive ?
  filteredFileList.count : fileList.count
  }
 

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
  let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as!
  FileTableViewCell
  let fileName = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
  let fileURL = documentsDirectory.appendingPathComponent(fileName)
  let file = File(url: fileURL)
  cell.configure(with: file)
  return cell
  }
 

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
  let fileName = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
  let fileURL = documentsDirectory.appendingPathComponent(fileName)
  showFileOptions(for: fileURL)
  }
 }
 

 // MARK: - File Handling Extensions
 

 extension HomeViewController: FileHandlingDelegate {
 

 }
 

 extension HomeViewController {
  func showFileOptions(for fileURL: URL) {
  let alertController = UIAlertController(title: fileURL.lastPathComponent, message: nil, preferredStyle: .actionSheet)
 

  let openAction = UIAlertAction(title: "Open", style: .default) { [weak self] _ in
  self?.openFile(at: fileURL)
  }
  alertController.addAction(openAction)
 

  let renameAction = UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
  self?.promptRename(for: fileURL)
  }
  alertController.addAction(renameAction)
 

  let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
  self?.promptDelete(for: fileURL)
  }
  alertController.addAction(deleteAction)
 

  let shareAction = UIAlertAction(title: "Share", style: .default) { [weak self] _ in
  self?.fileHandlers.shareFile(viewController: self!, fileURL: fileURL)
  }
  alertController.addAction(shareAction)
 

  let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
  alertController.addAction(cancelAction)
 

  present(alertController, animated: true, completion: nil)
  }
 

  func openFile(at fileURL: URL) {
  let fileExtension = fileURL.pathExtension
 

  switch fileExtension {
  case "txt", "swift", "html", "js", "css", "json":
  let textEditorVC = TextEditorViewController(fileURL: fileURL)
  navigationController?.pushViewController(textEditorVC, animated: true)
  case "hex":
  FileOperations.hexEditFile(at: fileURL, in: self)
  case "plist":
  let plistVC = PlistEditorViewController(fileURL: fileURL)
  navigationController?.pushViewController(plistVC, animated: true)
  default:
  utilities.showAlert(config: AlertConfig(title: "Cannot Open File", message: "File type not supported for opening.", style: .alert, actions: [AlertActionConfig(title: "OK", style: .default, handler: nil)], preferredAction: nil, completionHandler: nil), in: self)
  }
  }
 

  func promptRename(for fileURL: URL) {
  let alertController = UIAlertController(title: "Rename File", message: "Enter new name:", preferredStyle: .alert)
  alertController.addTextField { textField in
  textField.text = fileURL.lastPathComponent
  }
  let renameAction = UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
  guard let newName = alertController.textFields?.first?.text, !newName.isEmpty else {
  return
  }
  self?.fileHandlers.renameFile(viewController: self!, fileURL: fileURL, newName: newName) { result in
  switch result {
  case .success(_):
  break
  case .failure(let error):
  self?.utilities.handleError(in: self!, error: error, withTitle: "Rename Failed")
  }
  }
  }
  alertController.addAction(renameAction)
  alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
  present(alertController, animated: true, completion: nil)
  }
 

  func promptDelete(for fileURL: URL) {
  utilities.showAlert(config: AlertConfig(title: "Delete File", message: "Are you sure you want to delete this file?", style: .alert, actions: [
  AlertActionConfig(title: "Delete", style: .destructive) { [weak self] in
  guard let self = self else { return }
  let fileName = fileURL.lastPathComponent
  if let index = self.fileList.firstIndex(of: fileName) {
  self.deleteFile(at: index)
  }
  },
  AlertActionConfig(title: "Cancel", style: .cancel, handler: nil)
  ], preferredAction: nil, completionHandler: nil), in: self)
  }
 }
 

 // MARK: - Search Updating
 

 extension HomeViewController: UISearchResultsUpdating {
  func updateSearchResults(for searchController: UISearchController) {
  filterContentForSearchText(searchController.searchBar.text!)
  }
 

  private func filterContentForSearchText(_ searchText: String, scope: String = "All") {
  if searchText.isEmpty {
  filteredFileList = fileList
  } else {
  filteredFileList = fileList.filter { file in
  return file.localizedCaseInsensitiveContains(searchText)
  }
  }
  fileListTableView.reloadData()
  }
 }
 

 // MARK: - Drag and Drop
 

 extension HomeViewController: UITableViewDragDelegate, UITableViewDropDelegate {
  func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
  let fileName = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
  let fileURL = documentsDirectory.appendingPathComponent(fileName)
  let itemProvider = NSItemProvider(fileURL: fileURL)
  let dragItem = UIDragItem(itemProvider: itemProvider)
  dragItem.localObject = fileName
  return [dragItem]
  }
 

  func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
  let destinationIndexPath: IndexPath
  if let indexPath = coordinator.destinationIndexPath {
  destinationIndexPath = indexPath
  } else {
  let newRow = tableView.numberOfRows(inSection: 0)
  destinationIndexPath = IndexPath(row: newRow, section: 0)
  }
 

  coordinator.items.forEach { dropItem in
  guard let sourceFileName = dropItem.localObject as? String else { return }
  let sourceURL = documentsDirectory.appendingPathComponent(sourceFileName)
  let destinationFileName = searchController.isActive ? filteredFileList[destinationIndexPath
row] : fileList[destinationIndexPath.row]
            let destinationURL = documentsDirectory.appendingPathComponent(destinationFileName)
            
            if sourceURL != destinationURL {
                do {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                    
                    if searchController.isActive {
                        
                        let sourceIndex = fileList.firstIndex(of: sourceFileName)!
                        let destinationIndex = fileList.firstIndex(of: destinationFileName)!
                        fileList.remove(at: sourceIndex)
                        fileList.insert(sourceFileName, at: destinationIndex)
                        
                        filteredFileList.remove(at: dropItem.sourceIndexPath!.row)
                        filteredFileList.insert(sourceFileName, at: destinationIndexPath.row)
                    } else {
                        fileList.remove(at: dropItem.sourceIndexPath!.row)
                        fileList.insert(sourceFileName, at: destinationIndexPath.row)
                    }
                    
                    tableView.beginUpdates()
                    tableView.deleteRows(at: [dropItem.sourceIndexPath!], with: .automatic)
                    tableView.insertRows(at: [destinationIndexPath], with: .automatic)
                    tableView.endUpdates()
                } catch {
                    print("Error moving file: \(error)")
                }
            }
            coordinator.drop(dropItem.dragItem, toRowAt: destinationIndexPath)
        }
    }