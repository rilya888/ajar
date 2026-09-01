# Block 00 — Project foundation

Зависимости: нет.

## Задача

Пустой, но запускающийся каркас: менюбар-приложение без песочницы, с папками под будущие блоки, тестовым таргетом и git-репозиторием.

## Объём

- `Ajar.xcodeproj`, таргеты `Ajar` (macOS 14.0) и `AjarTests` (XCTest, TEST_HOST на Ajar.app).
- Проект собирать с file-system-synchronized groups — чтобы следующие блоки добавляли файлы, не правя `pbxproj`.
- Настройки таргета: `App Sandbox = NO`, `Hardened Runtime = YES`, `LSUIElement = YES`, `LSApplicationCategoryType = public.app-category.utilities`, code sign = Sign to Run Locally.
- Bundle ID — временный `com.ajarmac.ajar`. Финальный зависит от решения по имени (`docs/TODO.md`), менять в Block 11.
- `Ajar/App/AjarApp.swift` — `MenuBarExtra` с SF Symbol `laptopcomputer` и попапом-заглушкой.
- `Ajar/App/AppState.swift` — пустой `@Observable` корень.
- Пустые папки по структуре из `CLAUDE.md`: `Sensor/`, `Zones/`, `Actions/`, `Lifecycle/`, `Licensing/`, `UI/`, `Resources/`.
- `git init`, `.gitignore` (build/, DerivedData, .DS_Store, *.xcuserstate).
- Один smoke-тест, чтобы `xcodebuild test` был зелёным с самого начала.

## Ручной чек-лист

1. Приложение запускается, иконка в меню-баре видна, иконки в доке нет.
2. `codesign -d --entitlements - Ajar.app` не содержит `app-sandbox`.

## Acceptance

- `xcodebuild build` и `xcodebuild test` проходят.
- Чек-лист пройден, результаты записаны в STATUS.md.

## Коммит

`chore(project): bootstrap unsandboxed menubar app skeleton`
