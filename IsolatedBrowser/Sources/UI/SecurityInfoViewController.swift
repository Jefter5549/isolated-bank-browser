import UIKit

final class SecurityInfoViewController: UIViewController {
    private let host: String

    init(host: String) {
        self.host = host
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

        // Shield Icon
        let iconContainer = UIView()
        iconContainer.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.15)
        iconContainer.layer.cornerRadius = 36
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconContainer)

        let shieldConfig = UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
        let shieldIcon = UIImageView(image: UIImage(systemName: "checkmark.shield.fill", withConfiguration: shieldConfig))
        shieldIcon.tintColor = .systemGreen
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
        certTitle.text = "Сертификаты НУЦ Минцифры РФ"
        certTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        certTitle.textColor = .label
        cardStack.addArrangedSubview(certTitle)

        let certDesc = UILabel()
        certDesc.text = "Сайт проверен и подтверждён с использованием корневых сертификатов Национального удостоверяющего центра Минцифры России (Russian Trusted Root CA)."
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
        tlsDesc.text = "Шифрование: TLS 1.2 / TLS 1.3 с совершенной прямой секретностью (PFS). Ваши персональные данные, пароли и реквизиты карт надёжно защищены."
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
