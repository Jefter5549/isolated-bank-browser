import UIKit

final class BankPickerViewController: UITableViewController {
    private let preferences: BrowserPreferences
    private let onOpen: (Bank) -> Void
    private let onDefaultChanged: () -> Void

    init(preferences: BrowserPreferences, onOpen: @escaping (Bank) -> Void,
         onDefaultChanged: @escaping () -> Void) {
        self.preferences = preferences
        self.onOpen = onOpen
        self.onDefaultChanged = onDefaultChanged
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Банки"
        view.tintColor = .systemBlue
        navigationController?.view.tintColor = .systemBlue
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done,
                                                           target: self, action: #selector(close))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Bank")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : Bank.all.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "При запуске" : "Открыть банк"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "Этот банк открывается при новом запуске приложения. Возврат из другого приложения не прерывает текущую страницу." : "Нажмите на банк, чтобы открыть его. Нажмите на звезду, чтобы открывать этот банк по умолчанию."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Bank", for: indexPath)
        let bank = indexPath.section == 0 ? preferences.defaultBank : Bank.all[indexPath.row]
        let isDefault = preferences.defaultBank == bank
        var content = cell.defaultContentConfiguration()
        content.text = bank.name
        content.secondaryText = indexPath.section == 0 ? "Банк по умолчанию" : bank.service
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage(systemName: indexPath.section == 0 ? "house.fill" : "building.columns")
        content.imageProperties.tintColor = bank.tintColor
        cell.contentConfiguration = content
        cell.accessibilityIdentifier = "bank.\(indexPath.section).\(bank.id)"
        if indexPath.section == 0 {
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.accessoryType = .none
            let star = UIButton(type: .system)
            star.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
            star.setImage(UIImage(systemName: isDefault ? "star.fill" : "star"), for: .normal)
            star.tintColor = isDefault ? .systemOrange : .tertiaryLabel
            star.accessibilityLabel = "\(bank.name): банк по умолчанию"
            star.accessibilityValue = isDefault ? "Выбран" : "Не выбран"
            star.accessibilityHint = "Выбрать этот банк для открытия при запуске"
            star.accessibilityIdentifier = "defaultBank.\(bank.id)"
            star.addAction(UIAction { [weak self] _ in self?.setDefault(bank) }, for: .touchUpInside)
            cell.accessoryView = star
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let bank = indexPath.section == 0 ? preferences.defaultBank : Bank.all[indexPath.row]
        tableView.deselectRow(at: indexPath, animated: true)
        dismiss(animated: true) { [onOpen] in onOpen(bank) }
    }

    private func setDefault(_ bank: Bank) {
        preferences.defaultBank = bank
        onDefaultChanged()
        tableView.reloadData()
        UISelectionFeedbackGenerator().selectionChanged()
        UIAccessibility.post(notification: .announcement, argument: "\(bank.name) выбран по умолчанию")
    }

    @objc private func close() { dismiss(animated: true) }
}

extension Bank {
    var tintColor: UIColor {
        switch id {
        case "alfa": return .systemRed
        case "sber": return .systemGreen
        case "tbank": return .systemOrange
        case "kub": return .systemTeal
        case "gpb": return .systemIndigo
        default: return .systemBlue
        }
    }
}
