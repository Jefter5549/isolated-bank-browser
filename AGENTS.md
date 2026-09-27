# Работа с Isolated Bank Browser

## Назначение и устройство

Нативный браузер для iPhone/iPad на Swift 5, UIKit и WKWebView, minimum iOS 15.
Заявленная цель — доверять встроенным российским CA внутри приложения без установки сертификатов в системное хранилище.
Внешних пакетных зависимостей, backend и тестовых targets Xcode нет. TLS-регрессии запускаются отдельным macOS Swift executable из `Tests/TLS/main.swift`.

- `IsolatedBrowser/Sources/App/AppDelegate.swift`: точка входа, инициализация менеджера доверия.
- `IsolatedBrowser/Sources/App/SceneDelegate.swift`: окно и BrowserTabCoordinator с UINavigationController. Координатор удерживает отдельный BrowserViewController для каждой из максимум 12 вкладок; переключение не перезагружает страницы. Новая вкладка открывает банк по умолчанию, закрытие последней создаёт новую. Адреса вкладок и активная вкладка сохраняются в BrowserSessionStore и восстанавливаются после запуска; фоновые вкладки загружаются при выборе. История, формы и JS opener после перезапуска не восстанавливаются. Cookies и данные сайтов общие, в постоянном WKWebsiteDataStore.default(). JS popup использует конфигурацию WebKit и получает HTTP/WS blocker до первой загрузки.
- `IsolatedBrowser/Sources/UI/BrowserViewController.swift`: адресная строка, Google-поиск, банковские закладки, навигация, обновление, share sheet, KVO, WebKit delegates и передача TLS challenge менеджеру доверия. Начальная страница берётся из `BrowserPreferences.defaultBank`; для новой установки — КУБ. Выбор хранится в UserDefaults, смена банка в браузере не меняет предпочтение.
- `IsolatedBrowser/Sources/Security/CustomTrustManager.swift`: singleton, CA из Base64 и bundle, строгая оценка SecTrust с hostname, обработка authentication challenge.
- `IsolatedBrowser/Sources/Models/Bank.swift`: каталог банков и сохранение банка по умолчанию. `BrowserAddress.swift`: адрес/поисковый запрос.
- `IsolatedBrowser/Sources/UI/BankPickerViewController.swift`: открытие банка и выбор стартового банка отдельной кнопкой-звездой.
- `IsolatedBrowser/Sources/Security/SecureWebContent.swift`: HTTP/WS content blocker для всех ресурсов; компилируется и устанавливается до первого запроса. При ошибке компиляции сетевые загрузки не начинаются.
- `IsolatedBrowser/Sources/Security/HTTPSNavigationPolicy.swift`: общий запрет HTTP-навигации, включая redirects и popups.
- `IsolatedBrowser/Sources/Resources/`: Info.plist, assets и два DER-сертификата.
- `project.yml`: исходная конфигурация XcodeGen, target/scheme `IsolatedBrowser`, bundle ID `space.jefter.isolatedbrowser`.
- `.github/workflows/build-ipa.yml`: генерация проекта, Release archive без подписи, упаковка и загрузка IPA.

## Подготовка и проверка

Нужны Xcode с iOS SDK и XcodeGen. Команды выполняются из корня репозитория:

```sh
xcodegen generate
xcodebuild -project IsolatedBrowser.xcodeproj \
  -scheme IsolatedBrowser -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO
```

Для проверки сборки IPA повторять archive/package команды из workflow. IPA не подписан; успешная сборка не означает возможность установки без подписи.
CI запускается на push и pull_request к `master`/`main`, а также вручную.
Сгенерированный `.xcodeproj` не отслеживается исходным репозиторием и пока не исключён `.gitignore`: не добавлять его случайно в коммиты. Менять конфигурацию через `project.yml`.
Не коммитить build outputs, IPA, provisioning profiles, ключи, банковские данные и пользовательские сессии.

Для TLS-регрессий на macOS: `bash scripts/test-tls.sh` (Xcode CLI, OpenSSL 3, Python 3). `OPENSSL_BIN` задаёт путь к OpenSSL 3; `--live` дополнительно проверяет публичный HTTPS через URLSession. Тесты генерируют временные CA/ключи и не меняют Keychain. Это не заменяет проверку WKWebView на iOS.

Вкладки и JS popup: `bash scripts/test-tabs.sh` (macOS Catalyst, XcodeGen; отдельный тестовый bundle, сохранение формы, opener, закрытие последней вкладки).

Проверки настроек и адресов: `bash scripts/test-browser.sh`. Проверки реального WKWebView на macOS: `bash scripts/test-web-content.sh` (локальный сервер и временный тестовый bundle). Последние проверяют positive control и блокировку HTTP/WS для image/script/style/frame/fetch/websocket.

При изменениях Swift выполнить сборку. При изменениях поведения WebKit/UI дополнительно проверить на симуляторе или устройстве затронутые сценарии: адрес/поиск, переходы назад/вперёд, обновление, закладки, share sheet на iPad, окна JavaScript и обработку ошибок.
Камера и банковские интеграции требуют отдельной проверки на подходящем устройстве. Не считать компиляцию подтверждением работы входа, 2FA или платежей.
Для изменений TLS нужны позитивные и негативные проверки: корректная цепочка и hostname, недоверенная цепочка, неверный hostname и просроченный сертификат.
Отчёт должен различать чтение кода, успешную сборку и фактически выполненные проверки приложения.

## Обнаруженные ограничения исходной версии

Это наблюдения по коду, а не завершённый аудит безопасности:

- Обходы TLS из `b32af10` удалены: запрещено возвращать Basic X.509 или доверие по имени сертификата. При отказе или отсутствии serverTrust challenge отменяется.
- `requestMediaCapturePermissionFor` возвращает `.grant` без проверки origin; это решение WebKit, а не отмена системных разрешений iOS.
- Глобальные arbitrary loads запрещены. Для доменов банков из каталога и их поддоменов настроены точечные ATS-исключения, позволяющие WKWebView принять строго проверенную цепочку встроенного CA. TLS 1.2 и PFS сохранены. HTTP/WS блокируются content rules до загрузки любых ресурсов; навигация дополнительно проверяет HTTPSNavigationPolicy. Не отключать строгую SecTrust-проверку и не начинать загрузки до установки правил.
- Используется стандартная конфигурация WKWebView без явного non-persistent data store и разделения сессий по банкам. Изоляция CA от системы не означает приватность или изоляцию банковских сессий друг от друга.
- User-Agent зафиксирован под iOS 17.5.
- В Info.plist указаны версия `1.1.0` и build `3`.

При исправлениях сохранять область доверия внутри приложения; не устанавливать CA в системное хранилище. Не добавлять обходы TLS-проверок для устранения ошибок загрузки.

## Рабочий процесс

Основная ветка upstream — `master`; начальная личная ветка пользователя — `garshany/work`.
Перед изменениями проверить текущую ветку и `git status`, сохранять чужие изменения.
Использовать существующий UIKit-подход и стиль Swift; не переносить приложение на другой UI framework без задачи.
Текст интерфейса и пояснения пользователю — на русском. При искажении кириллицы в поисковом индексе сверять оригинальный UTF-8 файл перед правкой.
