import UIKit

class HomeViewUtilities {
    // Your existing implementation of utility functions
    // Ensure all utility methods are compatible with iOS

    static func showAlert(title: String, message: String, in viewController: UIViewController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        viewController.present(alert, animated: true, completion: nil)
    }
}