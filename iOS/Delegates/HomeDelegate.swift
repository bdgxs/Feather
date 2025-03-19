import Foundation

protocol HomeDelegate: AnyObject {
    func didAddFile(file: String)
    func didRemoveFile(file: String)
    func didUpdateFile(file: String)
}