# AGENTS.md — BalanceWatch

Этот файл — точка входа для AI-агентов и разработчиков. Прочитай его
целиком перед любым изменением в репозитории.

## Что это за проект

**BalanceWatch** — самостоятельное (watch-only) приложение для учёта
личных финансов под **watchOS 10+**. Это клиент экосистемы Balance:
те же сущности и тот же протокол синхронизации используют iOS/macOS-,
Android- и web-клиенты, а синхронизируются все они через self-hosted
сервер BalanceServer.

Проект выделен из монорепозитория Balance: туда входили таргет
`BalanceWatch` и общий код, который этот таргет компилировал. Здесь
этот код живёт как **копия** (см. раздел «Общий контракт»).

- UI: SwiftUI, только системные компоненты.
- Хранилище: SwiftData, только локально (`cloudKitDatabase: .none`).
- Синхронизация: HTTP(S) к BalanceServer, сессия хранится в Keychain.
- Внешних зависимостей (SPM/CocoaPods) нет — не добавляй их без явной
  необходимости.

## Структура

```text
BalanceWatch/
├── AGENTS.md
├── README.md
├── .github/workflows/build.yml   # CI: сборка для симулятора и устройства
├── BalanceWatch.xcodeproj/        # один таргет и одна схема — BalanceWatch
└── BalanceWatch/
    ├── App/
    │   ├── BalanceWatchApp.swift          # @main, ModelContainer, тема
    │   ├── WatchRootView.swift            # главный экран: баланс, месяц, навигация
    │   ├── WatchAddTransactionView.swift  # добавление операции
    │   └── WatchFeatures.swift            # аналитика, операции, бюджеты,
    │                                      # категории, корректировка баланса, настройки
    ├── Models/        # SwiftData-модели и системные категории
    ├── Shared/        # BalanceModelContainer, AppTheme,
    │                  # CategoryDesignOptions, ServerSync (ServerAccountStore)
    ├── Utilities/     # FinanceCalculations, форматирование валют и дат
    ├── Views/Components/CategoryIconView.swift
    └── Assets.xcassets
```

### Xcode-проект

`project.pbxproj` использует **папки, синхронизируемые с файловой
системой** (`PBXFileSystemSynchronizedRootGroup`, objectVersion 77,
нужен Xcode 16+). Любой файл, положенный в `BalanceWatch/`, сам
попадает в таргет:

- чтобы добавить файл, просто создай его в нужной папке, `project.pbxproj`
  трогать не нужно;
- `project.pbxproj` редактируй только ради build settings;
- не клади в `BalanceWatch/` файлы, которые не должны попасть в
  бандл (скрипты, документацию, тестовые данные).

Ключевые build settings: `SDKROOT = watchos`, `WATCHOS_DEPLOYMENT_TARGET = 10.0`,
`INFOPLIST_KEY_WKWatchOnly = YES`, `GENERATE_INFOPLIST_FILE = YES` (своего
Info.plist нет — ключи задаются через `INFOPLIST_KEY_*`), bundle id
`com.tolamironcenko.Balance.watchkitapp`, `SWIFT_VERSION = 5.0`.

## Правила разработки

### 1. Где что менять

| Что | Где |
| --- | --- |
| Экраны часов | `App/` |
| Модель данных | `Models/` + `Shared/BalanceModelContainer.swift` |
| Финансовые правила | `Utilities/FinanceCalculations.swift` |
| Авторизация и синхронизация | `Shared/ServerSync.swift` |
| Переиспользуемые view | `Views/Components/` |

Не дублируй доменную логику во view: расчёты — в `FinanceCalculations`,
сеть — в `ServerAccountStore`.

### 2. SwiftData

Схема зарегистрирована в `BalanceModelContainer.schema`:
`FinanceTransaction`, `MonthlyBudget`, `CustomCategory`, `SyncTombstone`.

- У пользователей уже есть локальные базы. Не удаляй и не переименовывай
  persisted-поля без стратегии миграции; новые поля делай со значением
  по умолчанию или опциональными.
- Если основное хранилище не открылось, `make()` откатывается на
  in-memory контейнер `BalanceRecovery`. Не убирай этот fallback.
- CloudKit не используется и не должен включаться: единственный
  источник синхронизации — BalanceServer.

### 3. Изменение и удаление записей

- Любое изменение синхронизируемой сущности обязано обновлять
  `syncUpdatedAt`, иначе изменение не уйдёт на сервер.
- Удаляй синхронизируемые сущности через
  `modelContext.deleteForSync(...)`, а не через `modelContext.delete(...)`:
  первый вариант пишет tombstone в `SyncDeletionStore`, и удаление
  доходит до других устройств.
- Операции и бюджеты хранят snapshot категории (имя, иконка, emoji,
  цвет). При переименовании пользовательской категории связанные
  операции и бюджеты нужно обновить — сохраняй это поведение.

### 4. Финансовые правила

Центральные правила — в `FinanceCalculations`:

- общий баланс = доходы − расходы;
- операции с `isBalanceAdjustment == true` входят в общий баланс, но
  **не** входят в периодическую аналитику (месяц/3 мес./12 мес.);
- расходы группируются по `categoryName`.

Эти правила **одинаковы во всех клиентах Balance** (Apple, Android, web).
Не меняй их только здесь.

### 5. Синхронизация (общий контракт)

`ServerAccountStore.shared` — единственная точка входа для авторизации и
синхронизации (`register`, `login`, `logout`, `sync`). Эндпоинты — `v1/...`
на BalanceServer; sync устроен как push изменений после последнего push
(транзакции → категории → бюджеты → tombstones), затем pull по `cursor`
пачками (`syncBatchSize`, `hasMore`).

- Формат JSON (`SyncChange`, `SyncRequest`, `SyncResponse`, payload'ы
  сущностей), семантика cursor/sequence и auth-заголовки — **общий
  контракт со всеми клиентами и сервером**. Изменение здесь без
  изменения сервера и остальных клиентов сломает синхронизацию.
- При смене URL сервера сессия очищается, cursor/push-state
  сбрасываются, пользователь логинится заново (`saveServer`). Сохраняй
  это поведение.

### 6. Безопасность

- Пароли не сохраняются нигде. Access/refresh токены — только в Keychain
  (`KeychainStore`), никогда не в `UserDefaults`, SwiftData или файлах.
- Для удалённого сервера — только HTTPS. HTTP разрешён только для
  `localhost`, `127.0.0.1`, `::1`.
- Не логируй пароли, токены и заголовок `Authorization`.
- Не коммить секреты, production-URL и credentials.

### 7. UI на часах

- Предпочитай `NavigationStack`, `List`, `Form`, короткие списки и
  компактные действия; крупный текст с `minimumScaleFactor`.
- Строки интерфейса — на русском (`developmentRegion = ru`).
- Акцентный цвет — `.indigo`; тема берётся из `@AppStorage("appTheme")`
  через `AppTheme`. Валюта — `@AppStorage("currencyCode")`.
- Ключи `@AppStorage`/`UserDefaults` не переименовывай: это сломает
  настройки у существующих пользователей.

## Сборка и проверка

```bash
xcodebuild -project BalanceWatch.xcodeproj -scheme BalanceWatch \
  -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

CI (`.github/workflows/build.yml`) собирает проект на `macos-15` для
симулятора и для устройства без подписи. Перед PR сборка должна быть
зелёной в обоих вариантах.

Тестового таргета пока нет. Если добавляешь тесты, не завязывай их на
текущую дату и локаль — явно фиксируй `Calendar`, `Date` и formatter'ы.
Добавив тестовый таргет, добавь и шаг `test` в CI.

## Чек-лист перед PR

- [ ] Изменение лежит в правильном слое (`App/`, `Models/`, `Shared/`, `Utilities/`).
- [ ] Persisted-поля SwiftData не сломаны, миграция продумана.
- [ ] Изменённые синхронизируемые сущности обновляют `syncUpdatedAt`.
- [ ] Удаления идут через `deleteForSync`.
- [ ] Финансовые правила и sync-контракт не разошлись с остальными клиентами Balance.
- [ ] Секреты и токены не попали в репозиторий и логи.
- [ ] CI собирает проект для симулятора и для устройства.
- [ ] README/AGENTS.md обновлены, если поменялась структура или сборка.
