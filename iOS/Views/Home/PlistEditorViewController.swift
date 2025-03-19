import UIKit

class PlistEditorViewController: UIViewController, UITextViewDelegate {
    private var fileURL: URL
    private var textView: UITextView!
    private var toolbar: UIToolbar!
    private var hasUnsavedChanges = false
    private var autoSaveTimer: Timer?

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
        loadFileContent()
        startAutoSaveTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if hasUnsavedChanges {
            promptSaveChanges()
        } else {
            navigationController?.popViewController(animated: true)
        }
        stopAutoSaveTimer()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Setup text view
        textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.delegate = self
        view.addSubview(textView)

        // Setup toolbar
        toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveChanges))
        let copyButton = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(copyContent))
        let findReplaceButton = UIBarButtonItem(title: "Find/Replace", style: .plain, target: self, action: #selector(promptFindReplace))
        let undoButton = UIBarButtonItem(barButtonSystemItem: .undo, target: self, action: #selector(undoAction))
        let redoButton = UIBarButtonItem(barButtonSystemItem: .redo, target: self, action: #selector(redoAction))
        toolbar.items = [saveButton, copyButton, findReplaceButton, undoButton, redoButton, UIBarButtonItem.flexibleSpace()]
        view.addSubview(toolbar)

        // Setup constraints
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func loadFileContent() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileContent = try String(contentsOf: self.fileURL)
                DispatchQueue.main.async {
                    self.textView.text = fileContent
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentAlert(title: "Error", message: "Failed to load file content: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func saveChanges() {
        guard let newText = textView.text else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try newText.write(to: self.fileURL, atomically: true, encoding: .utf8)
                self.hasUnsavedChanges = false
                DispatchQueue.main.async {
                    self.presentAlert(title: "Success", message: "File saved successfully.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentAlert(title: "Error", message: "Failed to save file: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func copyContent() {
        UIPasteboard.general.string = textView.text
        presentAlert(title: "Copied", message: "Content copied to clipboard.")
    }

    @objc private func undoAction() {
        textView.undoManager?.undo()
    }

    @objc private func redoAction() {
        textView.undoManager?.redo()
    }

    @objc private func promptFindReplace() {
        let alert = UIAlertController(title: "Find and Replace", message: "Enter text to find and replace:", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Find"
        }
        alert.addTextField { textField in
            textField.placeholder = "Replace"
        }
        alert.addAction(UIAlertAction(title: "Replace", style: .default, handler: { [weak self] _ in
            guard let findText = alert.textFields?[0].text, let replaceText = alert.textFields?[1].text else { return }
            self?.findAndReplace(findText: findText, replaceText: replaceText)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func findAndReplace(findText: String, replaceText: String) {
        textView.text = textView.text.replacingOccurrences(of: findText, with: replaceText)
        hasUnsavedChanges = true
    }

    private func promptSaveChanges() {
        let alert = UIAlertController(title: "Unsaved Changes", message: "You have unsaved changes. Do you want to save them before leaving?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self] _ in
            self?.saveChanges()
            self?.navigationController?.popViewController(animated: true)
        }))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive, handler: { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func startAutoSaveTimer() {
        autoSaveTimer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(autoSaveChanges), userInfo: nil, repeats: true)
    }

    private func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    @objc private func autoSaveChanges() {
        if hasUnsavedChanges {
            saveChanges()
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    func textViewDidChange(_ textView: UITextView) {
        hasUnsavedChanges = true
    }
}