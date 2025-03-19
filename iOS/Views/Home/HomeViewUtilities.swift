import UIKit
import os.log // Import os.log for logging

// MARK: - Error Handling Enhancements

/// Custom error hierarchy for file operations.
enum FileAppError: Error {
    case fileNotFound(String)          // File not found at path
    case fileAlreadyExists(String)      // File already exists
    case invalidFileName(String)        // File name contains invalid characters
    case invalidFileType(String)        // File type not supported
    case permissionDenied(String)       // Permission denied for operation
    case directoryCreationFailed(String) // Directory creation failed
    case fileCreationFailed(String)    // File creation failed
    case fileRenameFailed(String, String) // Renaming file failed (old, new)
    case fileDeleteFailed(String)      // Deleting file failed
    case fileMoveFailed(String, String)   // Moving file failed (old, new)
    case fileUnzipFailed(String, String, Error?) // Unzipping failed (file, dest, error)
    case fileZipFailed(String, String, Error?)   // Zipping failed (file, dest, error)
    case dylibListingFailed(String, Error?) // Listing dylibs failed (path, error)
    case unknown(Error)                // An unexpected error occurred
}

// MARK: - Alert Configuration

/// Structure to encapsulate alert configurations.
struct AlertConfig {
    let title: String?
    let message: String?
    let style: UIAlertController.Style
    let actions: [AlertActionConfig]
    let preferredAction: Int? // Index of preferred action
    let completionHandler: (() -> Void)?
}

struct AlertActionConfig {
    let title: String?
    let style: UIAlertAction.Style
    let handler: (() -> Void)?
}

// MARK: - HomeViewUtilities Class

class HomeViewUtilities {

    private let logger: Logger // Inject a logger dependency

    init(logger: Logger = Logger(subsystem: "com.example.FileApp", category: "Utilities")) {
        self.logger = logger
    }

    // MARK: - Error Handling

    /// Handles and presents an error to the user.
    ///
    /// - Parameters:
    ///   - viewController: The view controller to present the alert in.
    ///   - error: The error to handle.
    ///   - title: The title for the error alert.
    func handleError(in viewController: UIViewController, error: Error, withTitle title: String) {
        var message: String

        if let fileError = error as? FileAppError {
            switch fileError {
            case .fileNotFound(let fileName):
                message = "File not found: \(fileName). Please check the file name and try again."
                logger.info("File not found: \(fileName).")
            case .fileAlreadyExists(let fileName):
                message = "A file with the name \(fileName) already exists. Please choose a different name."
                logger.info("File already exists: \(fileName).")
            case .unknown(let underlyingError):
                message = "An unknown error occurred: \(underlyingError.localizedDescription)"
                logger.error("Unknown error: \(underlyingError.localizedDescription)")
            default:
                message = error.localizedDescription
            }
        } else {
            message = error.localizedDescription
            logger.error("Unexpected error: \(error.localizedDescription)")
        }

        // Present alert on main thread
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            viewController.present(alert, animated: true, completion: nil)
        }
    }

    // MARK: - Alert Presentation

    /// Presents a basic alert using the provided configuration.
    ///
    /// - Parameters:
    ///   - config: The alert configuration.
    ///   - viewController: The view controller to present the alert in.
    func showAlert(config: AlertConfig, in viewController: UIViewController) {
        let alert = UIAlertController(title: config.title, message: config.message, preferredStyle: config.style)

        for (index, actionConfig) in config.actions.enumerated() {
            let action = UIAlertAction(title: actionConfig.title, style: actionConfig.style) { _ in
                actionConfig.handler?()
            }
            alert.addAction(action)
            if let preferredIndex = config.preferredAction, preferredIndex == index {
                alert.preferredAction = alert.actions[preferredIndex]
            }
        }

        DispatchQueue.main.async {
            viewController.present(alert, animated: true, completion: config.completionHandler)
        }
    }

    /// Presents a confirmation alert with "OK" and "Cancel" actions.
    ///
    /// - Parameters:
    ///   - title: The title for the alert.
    ///   - message: The message for the alert.
    ///   - okHandler: Handler to be executed when the "OK" action is tapped.
    ///   - cancelHandler: Handler to be executed when the "Cancel" action is tapped.
    ///   - viewController: The view controller to present the alert in.
    func showConfirmationAlert(title: String?, message: String?, okHandler: (() -> Void)?, cancelHandler: (() -> Void)?, in viewController: UIViewController) {
        let okAction = AlertActionConfig(title: "OK", style: .default, handler: okHandler)
        let cancelAction = AlertActionConfig(title: "Cancel", style: .cancel, handler: cancelHandler)
        let config = AlertConfig(title: title, message: message, style: .alert, actions: [okAction, cancelAction], preferredAction: nil, completionHandler: nil)
        showAlert(config: config, in: viewController)
    }

    /// Presents an alert with a text field for user input.
    ///
    /// - Parameters:
    ///   - title: The title for the alert.
    ///   - message: The message for the alert.
    ///   - textFieldHandler: Handler to configure the text field.
    ///   - okHandler: Handler to be executed when the "OK" action is tapped, with the text field's text.
    ///   - cancelHandler: Handler to be executed when the "Cancel" action is tapped.
    ///   - viewController: The view controller to present the alert in.
    func showInputAlert(title: String?, message: String?, textFieldHandler: ((UITextField) -> Void)?, okHandler: ((String?) -> Void)?, cancelHandler: (() -> Void)?, in viewController: UIViewController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField(configurationHandler: textFieldHandler)
        
        let okAction = AlertActionConfig(title: "OK", style: .default) {
            let textField = alert.textFields?.first
            okHandler?(textField?.text)
        }
        let cancelAction = AlertActionConfig(title: "Cancel", style: .cancel, handler: cancelHandler)
        let config = AlertConfig(title: title, message: message, style: .alert, actions: [okAction, cancelAction], preferredAction: nil, completionHandler: nil)

        for actionConfig in config.actions {
            let action = UIAlertAction(title: actionConfig.title, style: actionConfig.style) { _ in
                actionConfig.handler?()
            }
            alert.addAction(action)
        }

        DispatchQueue.main.async {
            viewController.present(alert, animated: true, completion: config.completionHandler)
        }
    }

    // MARK: - Haptic Feedback

    /// Generates haptic feedback using UIImpactFeedbackGenerator.
    ///
    /// - Parameter style: The style of the impact feedback.
    func generateHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Generates haptic feedback using UINotificationFeedbackGenerator.
    ///
    /// - Parameter type: The type of the notification feedback.
    func generateNotificationFeedback(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    /// Generates haptic feedback using UISelectionFeedbackGenerator.
    func generateSelectionFeedback() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}