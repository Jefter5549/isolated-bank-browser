# Работа с Isolated Bank Browser

## Назначение и устройство

Нативный браузер для iPhone/iPad на Swift 5, UIKit и WKWebView, minimum iOS 15.
Заявленная цель — доверять встроенным российским CA внутри приложения без установки сертификатов в системное хранилище.
Внешних пакетных зависимостей, backend и тестовых targets в текущем проекте нет.

- `IsolatedBrowser/Sources/App/AppDelegate.swift`: точка входа, инициализация менеджера доверия.
- `IsolatedBrowser/Sources/App/SceneDelegate.swift`: окно и UINavigationController с BrowserViewController.
- `IsolatedBrowser/Sources/UI/BrowserViewController.swift`: адресная строка, Google-поиск, банковские закладки, навигация, обновление, share sheet, KVO, WebKit delegates и передача TLS challenge менеджеру доверия. Начальная страница — `https://direct.creditural.ru/`.
- `IsolatedBrowser/Sources/Security/CustomTrustManager.swift`: singleton, CA из Base64 и bundle, оценка SecTrust.
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

При изменениях Swift выполнить сборку. При изменениях поведения WebKit/UI дополнительно проверить на симуляторе или устройстве затронутые сценарии: адрес/поиск, переходы назад/вперёд, обновление, закладки, share sheet на iPad, окна JavaScript и обработку ошибок.
Камера и банковские интеграции требуют отдельной проверки на подходящем устройстве. Не считать компиляцию подтверждением работы входа, 2FA или платежей.
Для изменений TLS нужны позитивные и негативные проверки: корректная цепочка и hostname, недоверенная цепочка, неверный hostname и просроченный сертификат.
Отчёт должен различать чтение кода, успешную сборку и фактически выполненные проверки приложения.

## Обнаруженные ограничения исходной версии

Это наблюдения по коду на `b32af10`, а не завершённый аудит безопасности:

- `CustomTrustManager.evaluate` после неуспешной SSL-проверки переключается на Basic X.509; аргумент `host` не используется. Далее возможен успех только по подстрокам subject summary (`vtb`, `sberbank` и др.) после провала проверки цепочки. Не считать это безопасной валидацией TLS и не расширять такой fallback.
- `requestMediaCapturePermissionFor` возвращает `.grant` без проверки origin; это решение WebKit, а не отмена системных разрешений iOS.
- Info.plist разрешает arbitrary loads, включая web content.
- Используется стандартная конфигурация WKWebView без явного non-persistent data store и разделения сессий по банкам. Изоляция CA от системы не означает приватность или изоляцию банковских сессий друг от друга.
- User-Agent зафиксирован под iOS 17.5.
- В Info.plist указаны версия `1.0.1` и build `2`, хотя сообщение исходного коммита упоминает `v1.0.2`.

При исправлениях сохранять область доверия внутри приложения; не устанавливать CA в системное хранилище. Не добавлять обходы TLS-проверок для устранения ошибок загрузки.

## Рабочий процесс

Основная ветка upstream — `master`; начальная личная ветка пользователя — `garshany/work`.
Перед изменениями проверить текущую ветку и `git status`, сохранять чужие изменения.
Использовать существующий UIKit-подход и стиль Swift; не переносить приложение на другой UI framework без задачи.
Текст интерфейса и пояснения пользователю — на русском. При искажении кириллицы в поисковом индексе сверять оригинальный UTF-8 файл перед правкой.
