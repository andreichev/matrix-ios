# Подготовка iOS

Актуально на 26.09.2026. Нативный клиент использует микрофон, AVAudioSession и Background Modes -> Audio + Voice over IP. Оба режима указаны в Info.plist: `audio` и `voip`. Voice over IP нужен уже для CallKit, а не только для будущего PushKit. Добавлен CallKit для явно открываемых звонков на iPhone; обновление требует сборки и ручной проверки на устройстве. В симуляторе используется прежний аудиорежим без CallKit. В Info.plist есть описания доступа к микрофону/локальной сети и NSAllowsLocalNetworking для разработки. Push-регистрации, APNs-entitlements и PushKit пока нет.

## Сейчас

1. Открыть `Matrix Workspace.xcodeproj`, target `Matrix Workspace`, Signing & Capabilities. Проверить свою Team и Automatically manage signing. Существующий Bundle ID: `com.andreichev.matrix`; окончательно выбрать его до публикации.
2. Запустить клиент на симуляторе и своём iPhone. Push-capabilities пока не нужны; режимы Audio и Voice over IP уже указаны. Apple Developer Portal и App Store Connect агент не изменяет.
3. Перед распространением определить поддерживаемую iOS (сейчас в исходном проекте 26.5), добавить иконку и создать приложение в App Store Connect с этим Bundle ID. Архивирование и загрузка вручную: Product -> Archive -> Organizer -> Distribute App.

## Вместе с реализацией звонков и push

В target -> Signing & Capabilities -> + Capability:

| Настройка | Когда и зачем |
| --- | --- |
| Push Notifications | При добавлении APNs/PushKit. Xcode настроит entitlement и provisioning; не фиксировать вручную production/development в общем файле. |
| Background Modes -> Audio, AirPlay, and Picture in Picture | Для активного аудиозвонка в фоне. Сам флаг не заменяет настройку AVAudioSession и обработку системных прерываний. |
| Background Modes -> Voice over IP | Уже включён для CallKit. Без `voip` в UIBackgroundModes запрос звонка может отклоняться с `requesttransaction error 1` (unentitled). Не для удержания общего WebSocket приложения в фоне. |
| Background Modes -> Remote notifications | Только если реализуем фоновые обновления по обычным silent push. Для баннеров и как замена PushKit не нужен. |
| Associated Domains | Позже, если понадобятся Universal Links. Потребует файла apple-app-site-association на нашем домене. |
| App Groups / Keychain Sharing | Только при появлении расширения Share Extension и конкретной необходимости обмена. Обычное хранение Keychain внутри одного приложения не требует включать Keychain Sharing. |

CallKit и PushKit являются frameworks, отдельную галочку «CallKit» искать не нужно. `NSMicrophoneUsageDescription` и запрос при присоединении уже добавлены. Камеру, геолокацию и доступ ко всем фотографиям заранее не запрашиваем.

Для текущего этапа требуются Background Modes -> Audio и Voice over IP; оба включены в проекте. После изменения Info.plist пересобрать и установить приложение на iPhone. Проверить системные кнопки, фон, блокировку, Bluetooth и обычный телефонный вызов по списку в README. Удержание и системный повторный набор пока отключены; входящий при закрытом приложении появится только после PushKit/APNs.

Входящий VoIP push должен своевременно передаваться в CallKit. Регистрация двух видов токенов (обычный APNs и VoIP) отдельная, с привязкой к сессии устройства, обновлением и удалением при выходе. Просроченные, отменённые и повторные приглашения обрабатываются отдельно. Фоновые режимы не обещают постоянную работу приложения или безусловную доставку уведомлений.

## Что подготовить для сервера

- APNs authentication key `.p8` из Apple Developer -> Certificates, Identifiers & Profiles -> Keys с подходящими правами APNs; сохранить Key ID и Team ID. Проверить область действия ключа для нужного приложения/окружения.
- `.p8` хранить только в защищённых серверных секретах, не в iOS bundle, репозитории или переписке. Bundle ID, Team ID и Key ID сами по себе не являются приватным ключом.
- При реализации различать sandbox-токены из development-сборок и production-токены TestFlight/App Store. Для VoIP используются отдельный device token, push type `voip` и topic `<bundle-id>.voip`.
- APNs-ключ не является distribution-сертификатом для подписи приложения. Подписью управляет Xcode отдельно. Сейчас сервер менять и ключи устанавливать не требуется.

## Firebase и будущий Android

Текущее название сервиса Google: **Firebase Cloud Messaging (FCM)**. Рекомендуемый минимум:

- iOS: APNs напрямую для обычных уведомлений, APNs + PushKit/CallKit для звонков. Firebase SDK не нужен.
- Android с Google Play services: FCM для доставки уведомлений; Android без Google services потребует отдельного решения.
- Backend: общие события Матрицы, отдельные способы доставки Web Push / APNs / FCM. Firebase не нужен для WebRTC и не передаёт звук звонка.

Firebase-проект можно создать позже вместе с Android. Сначала выбрать Android package name; затем зарегистрировать приложение и настроить FCM HTTP v1 и серверную авторизацию. Серверные service-account credentials нельзя помещать в мобильное приложение.

FCM можно использовать и для обычных iOS-уведомлений, но он всё равно доставляет их через APNs и требует настройки Apple. Наш план VoIP предусматривает прямой APNs/PushKit, поэтому ради одинакового названия push-сервиса добавлять Firebase в iOS сейчас не стоит.

## Источники

- [Apple: unentitled и отсутствие voip в UIBackgroundModes](https://developer.apple.com/documentation/callkit/cxerrorcoderequesttransactionerror-swift.struct/code/unentitled).
- [Apple: один CXProvider на приложение](https://developer.apple.com/documentation/callkit/cxprovider).
- [Apple: активация аудиосессии CallKit](https://developer.apple.com/documentation/callkit/cxproviderdelegate/provider(_:didactivate:)).
- [WebRTC: ручное аудио и callbacks внешней активации](https://webrtc.googlesource.com/src/+/e8d5724cc5ee0b593a996477c7230bba3dc4d7bc/sdk/objc/components/audio/RTCAudioSession.h).
- [Apple: настройка PushKit](https://developer.apple.com/documentation/pushkit/supporting-pushkit-notifications-in-your-app).
- [Apple: обработка VoIP и CallKit](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit).
- [Apple: фоновые уведомления](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).
- [Apple: APNs token-based authentication](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns).
- [Firebase: Cloud Messaging](https://firebase.google.com/docs/cloud-messaging).
- [Firebase: Apple и APNs](https://firebase.google.com/docs/cloud-messaging/ios/get-started).
