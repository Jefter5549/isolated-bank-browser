import UIKit

final class DownloadsListViewController: UITableViewController, UIDocumentInteractionControllerDelegate {
    private var files: [DownloadedFile] = []
    private var documentInteractionController: UIDocumentInteractionController?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Загрузки"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Готово", style: .done, target: self, action: #selector(dismissSelf)
        )

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FileCell")
        tableView.tableFooterView = UIView()
        loadFiles()
    }

    private func loadFiles() {
        files = DownloadsManager.shared.listDownloads()
        tableView.reloadData()
        updateEmptyState()
    }

    private func updateEmptyState() {
        if files.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "Нет загруженных файлов"
            emptyLabel.textColor = .secondaryLabel
            emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
            emptyLabel.textAlignment = .center
            tableView.backgroundView = emptyLabel
        } else {
            tableView.backgroundView = nil
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    // MARK: - Table view data source
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "FileCell")
        let file = files[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = file.filename
        content.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
        content.textProperties.numberOfLines = 1

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let dateStr = formatter.string(from: file.date)

        content.secondaryText = "\(file.formattedSize) • \(dateStr)"
        content.secondaryTextProperties.font = .systemFont(ofSize: 12, weight: .regular)
        content.secondaryTextProperties.color = .secondaryLabel

        let ext = file.fileURL.pathExtension.lowercased()
        let iconName: String
        switch ext {
        case "pdf": iconName = "doc.richtext"
        case "doc", "docx": iconName = "doc.text"
        case "xls", "xlsx": iconName = "tablecells"
        case "zip", "rar", "7z": iconName = "archivebox"
        case "jpg", "jpeg", "png": iconName = "photo"
        default: iconName = "doc"
        }

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        content.image = UIImage(systemName: iconName, withConfiguration: symbolConfig)
        content.imageProperties.tintColor = .systemBlue

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let file = files[indexPath.row]

        documentInteractionController = UIDocumentInteractionController(url: file.fileURL)
        documentInteractionController?.delegate = self
        if !(documentInteractionController?.presentPreview(animated: true) ?? false) {
            let activity = UIActivityViewController(activityItems: [file.fileURL], applicationActivities: nil)
            if let cell = tableView.cellForRow(at: indexPath) {
                activity.popoverPresentationController?.sourceView = cell
                activity.popoverPresentationController?.sourceRect = cell.bounds
            }
            present(activity, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let file = files[indexPath.row]
            DownloadsManager.shared.deleteFile(at: file.fileURL)
            files.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            updateEmptyState()
        }
    }

    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        self
    }
}
