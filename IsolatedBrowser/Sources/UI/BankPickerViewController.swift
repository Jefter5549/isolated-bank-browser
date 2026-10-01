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
        
        navigationItem.leftBarButtonItem = editButtonItem
        let addBtn = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain,
                                   target: self, action: #selector(showAddService))
        let doneBtn = UIBarButtonItem(title: "Готово", style: .done,
                                    target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [doneBtn, addBtn]
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Bank")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return preferences.services.count
        case 2: return 2
        case 3: return 1
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "При запуске"
        case 1: return "Сервисы"
        case 2: return "Управление"
        case 3: return "Сеть и безопасность"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "Этот сервис открывается при запуске приложения. Возврат из другого приложения не прерывает текущую страницу."
        case 1: return "Нажмите на сервис, чтобы открыть его. Нажмите на звезду, чтобы открывать этот сервис по умолчанию. В режиме правки можно менять порядок и удалять сервисы."
        case 2: return "Вы можете добавить любой веб-сервис или интернет-банк, а также вернуть стандартный список."
        case 3: return "При запуске проверяет статус VPN и приостанавливает сетевые запросы до закрытия уведомления."
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Bank", for: indexPath)

        if indexPath.section == 3 {
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

        if indexPath.section == 2 {
            var content = cell.defaultContentConfiguration()
            cell.selectionStyle = .default
            cell.accessoryView = nil
            if indexPath.row == 0 {
                content.text = "Добавить сервис..."
                content.image = UIImage(systemName: "plus.circle.fill")
                content.imageProperties.tintColor = .systemBlue
                cell.accessoryType = .disclosureIndicator
            } else {
                content.text = "Сбросить к стандартным сервисам"
                content.image = UIImage(systemName: "arrow.counterclockwise.circle.fill")
                content.imageProperties.tintColor = .systemRed
                content.textProperties.color = .systemRed
                cell.accessoryType = .none
            }
            cell.contentConfiguration = content
            return cell
        }

        cell.selectionStyle = .default
        let bank = indexPath.section == 0 ? preferences.defaultBank : preferences.services[indexPath.row]
        let isDefault = preferences.defaultBank.id == bank.id
        var content = cell.defaultContentConfiguration()
        content.text = bank.name
        content.secondaryText = indexPath.section == 0 ? "Стартовый сервис" : bank.service
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0

        let iconName = indexPath.section == 0 ? "house.fill" : bank.displayIconName
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
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 3 { return }

        if indexPath.section == 2 {
            if indexPath.row == 0 {
                showAddService()
            } else {
                confirmResetServices()
            }
            return
        }

        let bank = indexPath.section == 0 ? preferences.defaultBank : preferences.services[indexPath.row]
        if isEditing && indexPath.section == 1 {
            showEditService(bank)
        } else {
            dismiss(animated: true) { [onOpen] in onOpen(bank) }
        }
    }

    // MARK: - Reordering & Deletion
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard sourceIndexPath.section == 1, destinationIndexPath.section == 1 else { return }
        preferences.reorderServices(from: sourceIndexPath.row, to: destinationIndexPath.row)
        tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
    }

    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
                            toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        if proposedDestinationIndexPath.section < 1 {
            return IndexPath(row: 0, section: 1)
        } else if proposedDestinationIndexPath.section > 1 {
            return IndexPath(row: preferences.services.count - 1, section: 1)
        }
        return proposedDestinationIndexPath
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && indexPath.section == 1 {
            let bank = preferences.services[indexPath.row]
            preferences.removeService(id: bank.id)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
            onDefaultChanged()
        }
    }

    // MARK: - Actions
    private func setDefault(_ bank: Bank) {
        preferences.defaultBank = bank
        onDefaultChanged()
        tableView.reloadData()
        UISelectionFeedbackGenerator().selectionChanged()
        UIAccessibility.post(notification: .announcement, argument: "\(bank.name) выбран стартовым сервисом")
    }

    @objc private func showAddService() {
        let editor = EditServiceViewController(mode: .add) { [weak self] newBank in
            self?.preferences.addService(newBank)
            self?.tableView.reloadData()
        }
        let nav = UINavigationController(rootViewController: editor)
        present(nav, animated: true)
    }

    private func showEditService(_ bank: Bank) {
        let editor = EditServiceViewController(mode: .edit(bank)) { [weak self] updatedBank in
            self?.preferences.updateService(updatedBank)
            self?.tableView.reloadData()
            self?.onDefaultChanged()
        }
        let nav = UINavigationController(rootViewController: editor)
        present(nav, animated: true)
    }

    private func confirmResetServices() {
        let alert = UIAlertController(
            title: "Сбросить сервисы?",
            message: "Будет восстановлен исходный список сервисов с Госуслугами по умолчанию.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Сбросить", style: .destructive) { [weak self] _ in
            self?.preferences.resetServicesToDefaults()
            self?.tableView.reloadData()
            self?.onDefaultChanged()
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }
}

// MARK: - Edit / Add Service Modal
final class EditServiceViewController: UIViewController {
    enum Mode {
        case add
        case edit(Bank)
    }

    private let mode: Mode
    private let onSave: (Bank) -> Void

    private let nameField = UITextField()
    private let serviceField = UITextField()
    private let urlField = UITextField()

    private var selectedIcon: String = "building.columns.fill"
    private var selectedColorHex: String = "#1270E0"

    private let iconPreview = UIImageView()
    private let availableIcons: [String] = [
        "doc.text.fill", "building.columns.fill", "creditcard.fill", "shield.fill",
        "flame.fill", "cart.fill", "bag.fill", "globe", "house.fill",
        "star.fill", "lock.fill", "cross.case.fill", "airplane", "car.fill",
        "person.fill", "sparkles"
    ]

    private let availableColors: [(name: String, hex: String)] = [
        ("Синий", "#1270E0"), ("Зеленый", "#21A038"), ("Красный", "#EF3124"),
        ("Оранжевый", "#FF9500"), ("Желтый", "#FFCC00"), ("Индиго", "#5856D6"),
        ("Фиолетовый", "#AF52DE"), ("Бирюзовый", "#30B0C7"), ("Серый", "#636366")
    ]

    init(mode: Mode, onSave: @escaping (Bank) -> Void) {
        self.mode = mode
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        if case .edit(let bank) = mode {
            selectedIcon = bank.displayIconName
            selectedColorHex = bank.iconTintHex ?? "#1270E0"
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        
        switch mode {
        case .add:
            title = "Новый сервис"
        case .edit:
            title = "Редактировать"
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Отмена", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(save))

        setupUI()
    }

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        // Icon Preview Card
        let previewCard = UIView()
        previewCard.backgroundColor = .secondarySystemGroupedBackground
        previewCard.layer.cornerRadius = 12
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        iconPreview.translatesAutoresizingMaskIntoConstraints = false
        iconPreview.contentMode = .scaleAspectFit
        previewCard.addSubview(iconPreview)
        NSLayoutConstraint.activate([
            previewCard.heightAnchor.constraint(equalToConstant: 90),
            iconPreview.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor),
            iconPreview.centerYAnchor.constraint(equalTo: previewCard.centerYAnchor),
            iconPreview.widthAnchor.constraint(equalToConstant: 52),
            iconPreview.heightAnchor.constraint(equalToConstant: 52)
        ])
        stack.addArrangedSubview(previewCard)
        updatePreview()

        // Form Fields Container
        let formContainer = UIView()
        formContainer.backgroundColor = .secondarySystemGroupedBackground
        formContainer.layer.cornerRadius = 12
        formContainer.translatesAutoresizingMaskIntoConstraints = false

        let formStack = UIStackView()
        formStack.axis = .vertical
        formStack.spacing = 1
        formStack.translatesAutoresizingMaskIntoConstraints = false
        formContainer.addSubview(formStack)

        NSLayoutConstraint.activate([
            formStack.topAnchor.constraint(equalTo: formContainer.topAnchor, constant: 8),
            formStack.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor, constant: 16),
            formStack.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor, constant: -16),
            formStack.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor, constant: -8)
        ])

        nameField.placeholder = "Название (например, ФНС России)"
        serviceField.placeholder = "Описание (например, Личный кабинет)"
        urlField.placeholder = "Адрес сайта (например, nalog.gov.ru)"
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.keyboardType = .URL

        if case .edit(let bank) = mode {
            nameField.text = bank.name
            serviceField.text = bank.service
            urlField.text = bank.address
        }

        for (idx, field) in [nameField, serviceField, urlField].enumerated() {
            field.heightAnchor.constraint(equalToConstant: 44).isActive = true
            formStack.addArrangedSubview(field)
            if idx < 2 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                formStack.addArrangedSubview(sep)
            }
        }
        stack.addArrangedSubview(formContainer)

        // Icons Picker Section
        let iconLabel = UILabel()
        iconLabel.text = "ИКОНКА"
        iconLabel.font = .preferredFont(forTextStyle: .caption1)
        iconLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(iconLabel)

        let iconScroll = UIScrollView()
        iconScroll.showsHorizontalScrollIndicator = false
        iconScroll.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let iconStack = UIStackView()
        iconStack.axis = .horizontal
        iconStack.spacing = 10
        iconStack.translatesAutoresizingMaskIntoConstraints = false
        iconScroll.addSubview(iconStack)
        NSLayoutConstraint.activate([
            iconStack.topAnchor.constraint(equalTo: iconScroll.topAnchor),
            iconStack.leadingAnchor.constraint(equalTo: iconScroll.leadingAnchor),
            iconStack.trailingAnchor.constraint(equalTo: iconScroll.trailingAnchor),
            iconStack.bottomAnchor.constraint(equalTo: iconScroll.bottomAnchor),
            iconStack.heightAnchor.constraint(equalTo: iconScroll.heightAnchor)
        ])

        for sym in availableIcons {
            let btn = UIButton(type: .system)
            btn.setImage(UIImage(systemName: sym), for: .normal)
            btn.tintColor = .label
            btn.layer.cornerRadius = 10
            btn.backgroundColor = .secondarySystemGroupedBackground
            btn.widthAnchor.constraint(equalToConstant: 48).isActive = true
            btn.addAction(UIAction { [weak self] _ in
                self?.selectedIcon = sym
                self?.updatePreview()
            }, for: .touchUpInside)
            iconStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(iconScroll)

        // Colors Picker Section
        let colorLabel = UILabel()
        colorLabel.text = "ЦВЕТ ИКОНКИ"
        colorLabel.font = .preferredFont(forTextStyle: .caption1)
        colorLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(colorLabel)

        let colorScroll = UIScrollView()
        colorScroll.showsHorizontalScrollIndicator = false
        colorScroll.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let colorStack = UIStackView()
        colorStack.axis = .horizontal
        colorStack.spacing = 12
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        colorScroll.addSubview(colorStack)
        NSLayoutConstraint.activate([
            colorStack.topAnchor.constraint(equalTo: colorScroll.topAnchor),
            colorStack.leadingAnchor.constraint(equalTo: colorScroll.leadingAnchor),
            colorStack.trailingAnchor.constraint(equalTo: colorScroll.trailingAnchor),
            colorStack.bottomAnchor.constraint(equalTo: colorScroll.bottomAnchor),
            colorStack.heightAnchor.constraint(equalTo: colorScroll.heightAnchor)
        ])

        for (_, hex) in availableColors {
            let btn = UIButton(type: .custom)
            btn.backgroundColor = UIColor(hex: hex)
            btn.layer.cornerRadius = 18
            btn.widthAnchor.constraint(equalToConstant: 36).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
            btn.addAction(UIAction { [weak self] _ in
                self?.selectedColorHex = hex
                self?.updatePreview()
            }, for: .touchUpInside)
            colorStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(colorScroll)
    }

    private func updatePreview() {
        iconPreview.image = UIImage(systemName: selectedIcon)
        iconPreview.tintColor = UIColor(hex: selectedColorHex) ?? .systemBlue
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func save() {
        guard let rawName = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else {
            showError("Укажите название сервиса")
            return
        }

        guard var rawURL = urlField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            showError("Укажите адрес сайта (URL)")
            return
        }

        if !rawURL.lowercased().hasPrefix("http://") && !rawURL.lowercased().hasPrefix("https://") {
            rawURL = "https://" + rawURL
        }

        guard let parsedURL = URL(string: rawURL), let host = parsedURL.host?.lowercased(), !host.isEmpty else {
            showError("Некорректный адрес сайта")
            return
        }

        let desc = serviceField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalDesc = desc.isEmpty ? host : desc

        let id: String
        let isCustom: Bool
        switch mode {
        case .add:
            id = "custom." + UUID().uuidString.prefix(8).lowercased()
            isCustom = true
        case .edit(let existing):
            id = existing.id
            isCustom = existing.isCustom
        }

        let newBank = Bank(
            id: id,
            name: rawName,
            service: finalDesc,
            domain: host,
            address: parsedURL.absoluteString,
            iconName: selectedIcon,
            iconTintHex: selectedColorHex,
            isCustom: isCustom
        )

        onSave(newBank)
        dismiss(animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Ошибка", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Extensions
extension Bank {
    var displayIconName: String {
        if let icon = iconName, !icon.isEmpty {
            return icon
        }
        if id == "gosuslugi" { return "doc.text.fill" }
        return "building.columns"
    }

    var tintColor: UIColor {
        if let hex = iconTintHex, let color = UIColor(hex: hex) {
            return color
        }
        switch id {
        case "gosuslugi": return .systemBlue
        case "alfa": return .systemRed
        case "sber": return .systemGreen
        case "tbank": return .systemOrange
        case "kub": return .systemTeal
        case "gpb": return .systemIndigo
        default: return .systemBlue
        }
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgb & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}
