import UIKit

final class SecurityInfoViewController: UIViewController {
    private let host: String
    private let details: SecurityDetails?

    init(host: String, details: SecurityDetails? = nil) {
        self.host = host
        self.details = details
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let isMintsifry: Bool
        let isSystem: Bool
        let caName: String

        if let details = details {
            switch details.caType {
            case .mintsifry(let name):
                isMintsifry = true
                isSystem = false
                caName = name
            case .system(let name):
                isMintsifry = false
                isSystem = true
                caName = name
            case .unknown:
                isMintsifry = false
                isSystem = false
                caName = details.issuerName
            }
        } else {
            isMintsifry = false
            isSystem = false
            caName = "Доверенный центр сертификации"
        }

        // Shield Icon
        let iconContainer = UIView()
        let accentColor: UIColor = isMintsifry ? .systemGreen : (isSystem ? .systemBlue : .secondaryLabel)
        iconContainer.backgroundColor = accentColor.withAlphaComponent(0.15)
        iconContainer.layer.cornerRadius = 36
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconContainer)

        let shieldConfig = UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
        let iconName = isMintsifry ? "checkmark.shield.fill" : (isSystem ? "lock.shield.fill" : "lock.fill")
        let shieldIcon = UIImageView(image: UIImage(systemName: iconName, withConfiguration: shieldConfig))
        shieldIcon.tintColor = accentColor
        shieldIcon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(shieldIcon)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Защищённое соединение"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        stack.addArrangedSubview(titleLabel)

        // Host
        let hostLabel = UILabel()
        hostLabel.text = host.isEmpty ? "Текущий сайт" : host
        hostLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        hostLabel.textColor = .secondaryLabel
        hostLabel.textAlignment = .center
        stack.addArrangedSubview(hostLabel)

        // Status Badge Pill
        let badgeContainer = UIView()
        badgeContainer.layer.cornerRadius = 13
        badgeContainer.layer.borderWidth = 1.0
        badgeContainer.layer.borderColor = accentColor.cgColor
        badgeContainer.backgroundColor = accentColor.withAlphaComponent(0.1)
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(badgeContainer)

        let badgeLabel = UILabel()
        if isMintsifry {
            badgeLabel.text = "Сертификат Минцифры России"
        } else if isSystem {
            badgeLabel.text = "Общедоступный доверенный сертификат"
        } else {
            badgeLabel.text = "Шифрование TLS / HTTPS"
        }
        badgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        badgeLabel.textColor = accentColor
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeContainer.heightAnchor.constraint(equalToConstant: 26),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 12),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -12),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor)
        ])

        // Card Container
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14
        card.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(card)

        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.spacing = 10
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        let certTitle = UILabel()
        if isMintsifry {
            certTitle.text = "Национальный УЦ (НУЦ) Минцифры"
        } else if isSystem {
            certTitle.text = "Глобальный центр сертификации"
        } else {
            certTitle.text = "Безопасное соединение"
        }
        certTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        certTitle.textColor = .label
        cardStack.addArrangedSubview(certTitle)

        let issuerLabel = UILabel()
        issuerLabel.text = "Кем выдан: \(caName)"
        issuerLabel.font = .systemFont(ofSize: 13, weight: .medium)
        issuerLabel.textColor = .label
        cardStack.addArrangedSubview(issuerLabel)

        if let subject = details?.subjectName, subject != host {
            let subjectLabel = UILabel()
            subjectLabel.text = "Кому выдан: \(subject)"
            subjectLabel.font = .systemFont(ofSize: 13, weight: .regular)
            subjectLabel.textColor = .secondaryLabel
            cardStack.addArrangedSubview(subjectLabel)
        }

        let certDesc = UILabel()
        if isMintsifry {
            certDesc.text = "Сайт использует доверенный отечественный сертификат безопасности, подтверждённый встроенными корневыми сертификатами Минцифры РФ."
        } else if isSystem {
            certDesc.text = "Сайт использует международный сертификат безопасности, аккредитованный доверенным хранилищем операционной системы iOS."
        } else {
            certDesc.text = "Сайт работает по зашифрованному протоколу HTTPS. Открытый трафик HTTP заблокирован политиками безопасности RUINET."
        }
        certDesc.font = .systemFont(ofSize: 13, weight: .regular)
        certDesc.textColor = .secondaryLabel
        certDesc.numberOfLines = 0
        cardStack.addArrangedSubview(certDesc)

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        cardStack.addArrangedSubview(divider)

        let tlsDesc = UILabel()
        tlsDesc.text = "Шифрование: TLS 1.2 / TLS 1.3 с совершенной прямой секретностью (PFS). Данные и реквизиты надёжно зашифрованы."
        tlsDesc.font = .systemFont(ofSize: 13, weight: .regular)
        tlsDesc.textColor = .secondaryLabel
        tlsDesc.numberOfLines = 0
        cardStack.addArrangedSubview(tlsDesc)

        // Done button
        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("Понятно", for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.backgroundColor = .systemBlue
        doneBtn.layer.cornerRadius = 12
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        stack.addArrangedSubview(doneBtn)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),

            iconContainer.widthAnchor.constraint(equalToConstant: 72),
            iconContainer.heightAnchor.constraint(equalToConstant: 72),
            shieldIcon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            shieldIcon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            card.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),

            doneBtn.widthAnchor.constraint(equalTo: stack.widthAnchor),
            doneBtn.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
}
