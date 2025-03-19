import UIKit

class HomeViewTableHandlers {
    // Your existing implementation of table view handlers
    // Ensure all table view handling methods are correctly implemented for iOS

    static func configureCell(_ cell: UITableViewCell, with file: File) {
        cell.textLabel?.text = file.name
        cell.detailTextLabel?.text = "\(file.size) bytes"
    }
}