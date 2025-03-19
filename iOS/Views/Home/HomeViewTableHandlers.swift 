import UIKit
 

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
  let fileName = searchController.isActive ? filteredFileList[indexPath.row] : fileList[indexPath.row]
  let fileURL = documentsDirectory.appendingPathComponent(fileName)
  showFileOptions(for: fileURL)
  }
 }