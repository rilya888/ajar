# Выпуск: от исходников до нотаризованного DMG

Весь конвейер — `Tools/release.sh`, одна команда без единого шага в Xcode:

```
Tools/release.sh
```

Результат в `build/release/dist/` (в git не попадает): `Ajar-<version>.dmg` и `appcast.xml`. Это ровно те два файла, которые уходят на хостинг.

Mac App Store в этом проекте не рассматривается: App Sandbox допускает IOKit только по конечному списку категорий, датчика крышки среди них нет. Подробности — в `docs/ARCHITECTURE.md`.

## Что уже настроено (не переделывать)

| Что | Значение | Где лежит |
|---|---|---|
| Сертификат | `Developer ID Application: OLEKSANDR RYLKOV (D89KDAZ648)` | login keychain |
| Team ID | `D89KDAZ648` | `DEVELOPMENT_TEAM` в Release-конфигурации приложения |
| Профиль нотаризации | `ajar` | login keychain, создан `xcrun notarytool store-credentials` |
| Приватный ключ Sparkle (EdDSA) | — | login keychain, создан `generate_keys` из Sparkle |
| Публичный ключ Sparkle | `E14fWzNiA4pszm2U/KfPM3EePAf12JDzISmJ2+l+trk=` | `Info.plist`, ключ `SUPublicEDKey` |
| Фид обновлений | `https://quietunit.com/ajar/appcast.xml` | `Info.plist`, ключ `SUFeedURL` |

**Team ID менять нельзя.** Он уходит и в подпись, и в цепочку доверия Sparkle: смена после релиза ломает автообновление у всех уже установленных копий.

**Приватного ключа Sparkle нет ни в репозитории, ни в бэкапе.** Если он потеряется, обновить установленные копии будет нечем — единственный выход будет просить пользователей переустановить приложение руками. Экспорт для бэкапа: Keychain Access → генерик-пароль с сервисом `https://sparkle-project.org`, аккаунт `ed25519`, «Show password», сохранить в менеджер паролей владельца.

Проверка, что нотаризация ещё авторизована: `xcrun notarytool history --keychain-profile ajar`.

## Что делает `Tools/release.sh`

1. `xcodebuild archive` — схема Ajar, конфигурация Release, Hardened Runtime включён, App Sandbox выключен.
2. `xcodebuild -exportArchive`, method `developer-id` — здесь `.app` получает боевую подпись с защищённой меткой времени.
3. Проверки **до** отправки в Apple: `codesign --verify --deep --strict`, наличие флага `runtime`, отсутствие `app-sandbox` в entitlements. Скрипт падает, если что-то из этого не так.
4. `notarytool submit --wait` по `.app` (в zip) → `stapler staple`.
5. DMG: `Ajar.app` + симлинк на `/Applications` + фон `docs/release/dmg-background.png`, раскладка окна ставится Finder'ом через AppleScript, затем сжатие в UDZO.
6. DMG подписывается отдельно, нотаризуется отдельно, степлится отдельно.
7. `generate_appcast` из Sparkle монтирует готовый DMG, читает из него версию, подписывает файл ключом EdDSA из связки ключей и пишет `appcast.xml`.

Два промпта на свежей машине, оба разово:

- **Automation → Finder** на шаге 5. Откажете — DMG всё равно соберётся и будет валиден, просто откроется списком без фона.
- **Доступ к ключу Sparkle** на шаге 7 (`generate_appcast` — не тот бинарь, который ключ создал). Нажать «Always Allow».

## Проверка перед публикацией

1. `spctl -a -vvv -t install build/release/dist/Ajar-<version>.dmg` → `accepted, source=Notarized Developer ID`. Скрипт печатает это сам последним шагом.
2. `codesign -d --entitlements - Ajar.app` → нет `app-sandbox`, есть `runtime`.
3. **Скачать DMG браузером** (не скопировать по файловой системе — карантинный атрибут ставится только при скачивании) и открыть на **другом пользователе** macOS. Ни одного предупреждения Gatekeeper. Это единственная честная проверка нотаризации.
4. Полный smoke-чек-лист — `docs/release/checklist.md`.

## Sparkle

- `appcast.xml` лежит рядом с DMG, по адресу из `SUFeedURL`.
- Автопроверка включена (`SUEnableAutomaticChecks`), интервал — дефолтный сутки, отдельного ключа не заведено намеренно.
- Приложение — `LSUIElement`, поэтому диалог обновления открывается за чужими окнами. `Ajar/App/Updater.swift` включает «gentle reminders» и поднимает окно на передний план; без этого Sparkle пишет об этом варнинг при каждом старте.
- Проверять обновление обязательно **реально**: собрать версию N, поставить её, собрать N+1, положить его appcast на место фида, убедиться, что приложение находит, скачивает, ставит и перезапускается. Сломанный апдейтер невозможно починить апдейтом.

### Как выпустить следующую версию

1. Поднять `MARKETING_VERSION` в `Ajar.xcodeproj/project.pbxproj` (и `CURRENT_PROJECT_VERSION`, если хочется отдельный номер сборки).
2. `Tools/release.sh`.
3. Положить **старый** DMG рядом с новым в `build/release/dist/` перед шагом appcast, если нужен фид с историей версий — `generate_appcast` собирает запись по каждому DMG в каталоге.
4. Залить `Ajar-<version>.dmg` и `appcast.xml` в `quietunit.com/ajar/`.

## Хостинг

`quietunit.com/ajar/` — статика, деплой у владельца локальным `npm run build` + `rsync` (CI нет, push в git ничего не деплоит). DMG и appcast кладутся туда же, где уже лежат `shortcuts/*.shortcut`. Скачивание анонимное и бесплатное, привязки к покупке нет: платная только лицензия.

## Публикация (владелец)

- [ ] `Tools/release.sh`, дождаться `accepted, source=Notarized Developer ID`.
- [ ] Залить `Ajar-1.0.dmg` и `appcast.xml` в `quietunit.com/ajar/`. Проверить `curl -I https://quietunit.com/ajar/appcast.xml` → 200 (сейчас 404).
- [ ] Снять гифку жеста и поставить её на лендинг — сценарий съёмки в `docs/TODO.md`.
- [ ] Закрыть оставшиеся пункты Paddle live (одобрение домена, KYC, `PUBLIC_PADDLE_TOKEN`) — список в `docs/TODO.md`.
- [ ] Живая контрольная покупка на $9 своей картой, ключ из письма вставить в пейволл собранного релиза.
- [ ] Прогнать `docs/release/checklist.md` на чистом пользователе macOS с DMG, скачанным через браузер.
- [ ] Проверить обновление Sparkle с 1.0 на тестовую 1.0.1 — см. выше.
- [ ] Только после этого — Show HN и рассылка блогам.
