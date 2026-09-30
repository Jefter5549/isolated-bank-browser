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
        title = "Сервисы"
        view.tintColor = .systemBlue
        navigationController?.view.tintColor = .systemBlue
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done,
                                                           target: self, action: #selector(close))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Bank")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return Bank.all.count
        case 2: return 1
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "При запуске"
        case 1: return "Быстрый доступ"
        case 2: return "Сеть и безопасность"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "Этот сервис открывается при запуске приложения. Возврат из другого приложения не прерывает текущую страницу."
        case 1: return "Нажмите на сервис, чтобы открыть его. Нажмите на звезду, чтобы открывать этот сервис по умолчанию."
        case 2: return "При запуске проверяет статус VPN и приостанавливает сетевые запросы до закрытия уведомления."
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Bank", for: indexPath)
        if indexPath.section == 2 {
            var content = cell.defaultContentConfiguration()
            content.text = "Предупреждать о VPN при запуске"
            content.secondaryText = "Приостанавливает загрузку страницы при активном VPN"
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.numberOfLines = 0
            content.image = UIImage(systemName: "network.badge.shield.half.filled")
            content.imageProperties.tintColor = .systemOrange
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = "settings.warnOnVPN"
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = preferences.warnOnVPN
            toggle.addAction(UIAction { [weak self] _ in
                self?.preferences.warnOnVPN = toggle.isOn
            }, for: .valueChanged)
            cell.accessoryView = toggle
            return cell
        }

        cell.selectionStyle = .default
        let bank = indexPath.section == 0 ? preferences.defaultBank : Bank.all[indexPath.row]
        let isDefault = preferences.defaultBank == bank
        var content = cell.defaultContentConfiguration()
        content.text = bank.name
        content.secondaryText = indexPath.section == 0 ? "Стартовый сервис" : bank.service
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        let iconName: String
        if indexPath.section == 0 {
            iconName = "house.fill"
        } else if bank.id == "gosuslugi" {
            iconName = "person.badge.shield.checkmark.fill"
        } else {
            iconName = "building.columns"
        }
        content.image = UIImage(systemName: iconName)
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
            star.accessibilityLabel = "\(bank.name): стартовый сервис"
            star.accessibilityValue = isDefault ? "Выбран" : "Не выбран"
            star.accessibilityHint = "Выбрать этот сервис для открытия при запуске"
            star.accessibilityIdentifier = "defaultBank.\(bank.id)"
            star.addAction(UIAction { [weak self] _ in self?.setDefault(bank) }, for: .touchUpInside)
            cell.accessoryView = star
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section != 2 else { return }
        let bank = indexPath.section == 0 ? preferences.defaultBank : Bank.all[indexPath.row]
        tableView.deselectRow(at: indexPath, animated: true)
        dismiss(animated: true) { [onOpen] in onOpen(bank) }
    }

    private func setDefault(_ bank: Bank) {
        preferences.defaultBank = bank
        onDefaultChanged()
        tableView.reloadData()
        UISelectionFeedbackGenerator().selectionChanged()
        UIAccessibility.post(notification: .announcement, argument: "\(bank.name) выбран стартовым сервисом")
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
