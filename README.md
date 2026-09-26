# Matrix iOS

Первый нативный этап: UIKit-клиент для проверки групповых аудиозвонков с существующей Матрицей. WebView и бизнес-функции CRM пока не подключены. CI нет, сборки распространяются вручную через Xcode.

## Возможности

- Вход на указанный сервер, Keychain, единое обновление токенов и выход с отзывом серверной сессии.
- Доступные чаты и текущие звонки. Нужны членство в чате и разрешение звонков от администратора.
- Явное присоединение, постраничная галерея подключений, микрофон и выход.
- Нативные mediasoup/WebRTC, существующий WebSocket-протокол, SFU/TURN. Токен в Authorization, не в URL. Прямого доступа к API SFU нет.
- Переподключение сигнализации, ICE restart, обновление участников. При выходе микрофон выключается сразу, при восстановлении сохраняется mute.
- AVAudioSession для разговора и Bluetooth HFP, режим background audio. Фоновые сценарии ещё требуют проверки на физическом iPhone.

**Не реализованы:** CallKit, PushKit/APNs, системные входящие звонки, история, WebView/мост и share extension. Входящие видны только в открытом списке звонков. Это ещё не полноценная замена PWA.

## Запуск

Открыть `Matrix Workspace.xcodeproj`, схема `Matrix Workspace`. Для iPhone проверить Team в Signing & Capabilities и включить Developer Mode, если Xcode попросит.

Bundle ID `com.andreichev.matrix`, автоматическая подпись, Team и минимальная iOS **26.5** сохранены. До распространения согласовать поддержку более старых iPhone.

1. Backend и SFU запускает разработчик. Для этого этапа изменения backend или миграции не требуются.
2. В симуляторе доступен `http://localhost:8080`. HTTP разрешён кодом только для loopback в Debug. Для удалённых серверов и Release нужен HTTPS с доверенным сертификатом; проверка TLS не отключается.
3. На физическом iPhone localhost означает телефон. Нужен доступный ему HTTPS-сервер; SFU должен объявлять доступный телефону IP, а медиапорты и TURN должны быть доступны.
4. Войти сотрудником, выбрать чат и нажать «Присоединиться». На втором устройстве открыть тот же звонок в web. Не тестировать на рабочих чатах без согласования: start отправляет их участникам настоящие приглашения.
5. Назад и выход с экрана завершают подключение. Сворачивание приложения само по себе не вызывает выход.

До входа сетевых запросов нет. Адрес сервера вводится пользователем, пароль не сохраняется. Если отзыв сессии после локального выхода не подтверждён, показывается предупреждение; сессию можно завершить через «Устройства» другого клиента.

```sh
xcodebuild \
  -project 'Matrix Workspace.xcodeproj' \
  -scheme 'Matrix Workspace' \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Структура

```text
Matrix Workspace/
  MainFiles/                 AppDelegate, SceneDelegate, AppCoordinator
  Controllers/
    Login/                   Controller, View, Interactor
    CallsList/               Controller, View, Interactor
    Call/                    Controller, View, Interactor, ParticipantCell
  Services/
    Auth/                    AuthService, KeychainStore
    Network/                 HTTPClient, ServerAddress
    Calls/                   CallSocket, модели, SfuAudioSession, MediaWorker
  Helpers/                   JSONValue
  Resources/                 Info.plist, Assets, LaunchScreen
Tests/                       XCTest
test-support/                Локальная SFU/Chromium-проверка
```

View создаются кодом: lazy closure-based subviews, `setupStyle`, `addSubviews` только для иерархии, `makeConstraints` только для constraints. Блокирующие операции C++ вынесены на отдельную последовательную очередь; UI и координация явно помечены MainActor.

Зависимость: [Mediasoup-Client-Swift](https://github.com/VLprojects/mediasoup-client-swift), строго `0.13.2`, зафиксирована в Package.resolved. Xcode загружает бинарные Mediasoup/WebRTC XCFramework. Это сторонняя обёртка. Перед выпуском проверить актуальность библиотеки, лицензии/Privacy Manifest и требования App Store. Прототип пока на русском; иконка не заполнена.

## Тесты

Cmd+U: протокол, Keychain/ротация токенов и загрузка нативного Opus. Для тестов Keychain нужна обычная подпись симулятора: не задавать `CODE_SIGNING_ALLOWED=NO`.

Интеграционный тест запускается отдельно с собственным SFU и Chromium с синтетическим звуком. Нужны соседние matrix-sfu и matrix-mobile, установленные зависимости matrix-sfu и его Chromium. Основной backend и рабочая БД не используются:

```sh
../matrix-sfu/node_modules/.bin/tsx test-support/native-sfu.mts
```

В другом терминале:

```sh
xcodebuild -project 'Matrix Workspace.xcodeproj' \
  -scheme 'Matrix Workspace' \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  MATRIX_SFU_TEST_URL=http://127.0.0.1:38761 test
```

Без переменной интеграционный тест пропускается. После проверки остановить fixture через Ctrl+C; перед новым прогоном перезапустить. Fixture слушает только loopback. Проверка RTP в симуляторе не заменяет проверку слышимости, AirPods, телефонных прерываний, блокировки и смены сети на iPhone.

- [Правила архитектуры](context/IOS-ARCHITECTURE.md).
- [Подготовка Apple, capabilities и уведомлений](context/ios-setup.md).

Перед TestFlight нужны иконка, запись приложения в App Store Connect, проверенная подпись и ручная проверка на iPhone. Сборка пока предназначена для локальной разработки.
