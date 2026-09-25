# Matrix iOS

Нативный UIKit-каркас на основе структуры MoveAndPray. Пока приложение показывает только стартовый экран: без WebView, авторизации, сети, звонков, уведомлений и запросов разрешений. CI и сторонних зависимостей нет.

## Запуск

Открыть `Matrix Workspace.xcodeproj`, выбрать схему `Matrix Workspace` и запустить на симуляторе. Для физического устройства проверить Team в Signing & Capabilities и включить Developer Mode на iPhone, если Xcode попросит.

Существующие настройки проекта сохранены: Bundle ID `com.andreichev.matrix`, автоматическая подпись, Team, iPhone/iPad, минимальная iOS **26.5**. Перед первым тестированием сотрудниками согласовать минимальную версию: каркас не требует именно 26.5, но совместимость будущего WebRTC-клиента ещё предстоит проверить.

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
  MainFiles/     AppDelegate, SceneDelegate, сборка корневого экрана
  Controllers/   Controller, View; позднее Interactor и модели конкретных экранов
  Services/      Будущие сервисы авторизации, сети, звонков и уведомлений
  Helpers/       Небольшие общие утилиты; сейчас только L10n
  Resources/     Info.plist, Assets, launch screen, русские и английские тексты
```

Экраны создаются программно, `Main.storyboard` удалён. `LaunchScreen.storyboard` остаётся только системным экраном запуска. Стартовый экран поддерживает светлую/тёмную тему и Dynamic Type. Иконка приложения пока не заполнена.

- [Правила архитектуры](context/IOS-ARCHITECTURE.md).
- [Подготовка Apple, capabilities и уведомлений](context/ios-setup.md).

Сборки и публикация выполняются вручную из Xcode. Перед TestFlight понадобятся запись приложения в App Store Connect, иконка, проверенная подпись и реально работающий функционал; этот каркас не является готовой сборкой для внешнего тестирования.
