# Spec: iPhone personal-finance app modeled on Debit & Credit for Mac

Handoff document for an implementing agent. It is self-contained: it records what was learned about the reference app (Debit & Credit for Mac v7.9, build 2991, by Ivan Pavlov), the behavior to reproduce, and the proposed iPhone design.

## 0. Ground rules

- This is a clean-room re-implementation of **observed behavior and data shape**. Do not copy the reference app's code, assets, icons, strings, name or branding. Pick an original app name, icon and copy.
- Evidence labels used below:
  - **Observed**: read directly from the installed Mac app (plists, entitlements, linked frameworks, Core Data model, ObjC metadata, disassembly).
  - **Inferred**: reconstructed from method names and call sequences. Treat as a hypothesis and verify with tests.
- Analysis was static only. No decompiler was available, nothing was executed, and the user's local database was deliberately never opened. The iPhone version of the reference app was not analyzed; the Mac framework `DCCoreKit` is shared code, so iPhone behavior is probably similar (inferred).
- Not determined: sign conventions, rounding mode, the `Plan_item.repeat_period` enum values, CloudKit conflict handling, server request/response formats, the App Intents list. Decide these yourself and cover them with tests (section 9).

## 1. Reference app summary (observed)

- Bundle `com.mr-brightside.debitandcreditMac`, universal binary, macOS 12+, Mac App Store, sandboxed.
- Two code layers: a thin AppKit UI (`DCMac*` classes, storyboards, some SwiftUI and Charts) and `DCCoreKit.framework` (all business logic, shared with iOS). Logic is organized as controllers (Account, Budget, Category, Plan, Report, Statistics, Transaction, RecurringTransaction, Currency, Import, Export, Calculator, Metadata, CloudKit, CloudSharing, InApp, Pin, Rating, Location, Log, RestoreData) plus an `NSOperation` pipeline (CloudKit download/modify, running balance, plan-period calc, recurring-due, duplicate removal, expired-object deletion, calendar events, local notifications, badge refresh, attachment OCR and thumbnails, subscription status).
- Storage: Core Data, 39 model versions (current "DebitAndCredit 39"), SQLite in an app-group container shared with extensions.
- Sync: CloudKit (private DB and sharing), iCloud key-value store, push notifications.
- Extensions: share, intents, App Intents, widgets. URL scheme `dcapp://`. Opens CSV, OFX, QIF/QFX files.
- Only declared server: `api.debitandcredit.app`, used for premium status. Paths seen: `dc-check-account-status.php`, `dc-check-server.php`, `dc-get-purchase-token.php`, `dc-receipt-verification.php`, `dc-verify-transactions.php`. StoreKit products: a one-time premium, a renewable subscription, and a trial variant.
- Free tier has limits (`...IsOverLimit` checks for transactions per account/week and scheduled transactions) and sharing is disabled for free accounts.
- Permissions: calendars (scheduled transactions into a separate calendar), location (suggest nearby saved payees), Apple Events (Numbers export).

## 2. Product scope

### v1 (build)
Accounts and folders, multi-currency, transactions (expense, income, transfer) with categories, tags, payees, notes, splits and attachments, scheduled/recurring transactions, budgets, annual plans, basic reports, CSV import/export, Face ID/PIN lock, local persistence, CloudKit sync across the user's devices.

### Later
OFX/QIF import with rules, bank reconciliation, widgets, App Intents/Siri, calendar integration, receipt OCR, location-based payee suggestion, CloudKit sharing, Apple Wallet account import, premium/paywall.

### Out of scope
Anything involving the reference app's server, its StoreKit products, or its branding.

## 3. Architecture

- SwiftUI, iOS 17+. Persistence: SwiftData by default; Core Data if the owner wants to import Mac databases or keep schema parity (open decision, section 11).
- Domain logic lives in a local Swift package, `LedgerCore`, with no UI imports. It holds models-agnostic pure functions (date stepping, balance math, budget periods, plan math) so it is unit-testable and reusable by a future Mac target. UI and persistence depend on it, not the reverse.
- Money uses `Decimal` end to end. Never `Double` or `Float`. (The reference app uses NSDecimalNumber for budget math, with a float-based exchange rate in places; do not copy that.)
- Background work: use async tasks or `BGTaskScheduler`; keep recalculation off the main actor.
- Sync: CloudKit private database. Every synced record carries a stable record ID, change tag, owner, pending-update flag and soft-delete date (tombstones), mirroring the reference.

## 4. Data model

Derived from the reference Core Data model (observed). Fields may be simplified; keep the relationships.

| Entity | Key fields and relationships |
|---|---|
| Account | name, type (AccountType), currency, folder, current balance, current uncleared balance, credit limit, show available credit, hidden, excluded from net wealth, last reconciled balance, icon name, sort id, date created |
| AccountFolder | name, icon name, expanded, show balance, hidden, sort id, accounts |
| AccountType | name, kind (transaction, savings, credit, cash) |
| Transaction | amount, type, date (plus day, effective date, posted date), account, category, payee, description, tag, notes, tax, pending, reconciled, imported, upcoming, external id, originating source, referenced transaction (links the two legs of a transfer), recurring transaction, splits, attachments |
| Split | amount, category, transaction |
| Attachment | file name, content type, file size, transaction |
| RecurringTransaction | repeat flag, repeat type, repeat duration, start date, next date, last date, end date, amount (source amount and destination amount for transfers), account, destination account, category, payee, description, tag, splits, notify, autopay, process pending, include in calendar, cashback account and percentage, tax, completed transactions |
| Budget | name, amount, currency, start date, end date, repeat type, repeat duration, all categories flag, monitored categories, filtered tags, excluded tags, include pending, carry over, carry over negative, current balance, carryover balance, unused refunds, notes, limits history (BudgetLimit), sort id |
| BudgetLimit | budget, date, limit, comment |
| Plan | name, start month/year, end month/year, currency, periods, items, ignore unplanned tags, sort id |
| PlanPeriod | plan, month, year, units |
| PlanItem | plan, type, category (or group name with group categories), tag, repeat period, annual amount, payment date, units |
| PlanUnit | item, period, amount, comment |
| Category | name, type, parent, children, sort id, usage rating |
| Payee | name, usage rating, last used category, locations, document fields for OCR |
| Tag | name, colour, default tag flag, default accounts, usage rating |
| Description | name, type, usage rating, last used date |
| Location | latitude, longitude, locality, sublocality, accuracy fields, payee |
| ImportRule | merchant name mapped to category, payee, tag, description |
| Currency | code, name, symbol, symbol behind flag, crypto flag, exchange rate, rate updated date |
| Tombstone | record type, record name, owner |

## 5. Business logic to implement

### 5.1 Next occurrence for scheduled transactions
Observed in disassembly (`+nextDateForRepeatType:andDuration:fromDate:afterDate:`), restated as a spec.

Inputs: `repeatType` (1…11), `duration` (≥ 1), `fromDate`, optional `afterDate`. Output: a date, or nil for invalid input (type outside 1…11 or duration < 1).

- Types: 1 = day, 2 = week, 3 = month, 4 = year, 5…11 = "nth weekday of the month". For 5…11 the weekday is derived from `type − 5` through a 7-entry table (weekday order not verified; assume Sunday…Saturday in the system calendar and test), and `duration` is the ordinal (2 = second).
- If `afterDate` is nil or `fromDate > afterDate`: return `fromDate + 1 × duration` units (for weekday types return `fromDate` unchanged).
- Otherwise iterate `i = 1, 2, …`: candidate = `fromDate + i × duration` units, always measured from the original `fromDate` (this prevents month-end drift such as Jan 31 → Feb 28 → Mar 28). Stop at the first candidate strictly after `afterDate`.
- Weekday types: take the time of day from the current date, find the next date after it matching weekday and weekday-ordinal strictly, re-apply the time of day, repeat until strictly after `afterDate`.

### 5.2 Processing a scheduled transaction
Inferred from the call sequence of `processRecurringTransactionID:withOptions:processedManually:`.
1. Load the schedule; abort if missing.
2. Recorded date = scheduled date, or "now" when executed manually (option to execute now with a specific amount).
3. Build the transaction from the schedule: amount, category, payee, tag, description, splits.
4. If a destination account exists, create a transfer using source and destination amounts (they differ when currencies differ). Otherwise create a normal transaction.
5. If cashback percentage and cashback account are set, also create a cashback transaction.
6. Set `last_date`, advance `next_date` with 5.1 (using `afterDate` = recorded date). If the new date passes `end_date`, or repeat is off, mark the schedule completed (set end date or remove it).
7. Mark the new transaction pending if `process_pending` is set; update affected account balances; refresh the "upcoming" token.
- Skip: advance `next_date` without creating a transaction. Execute now: run the steps above immediately.
- Upcoming rows: keep a window of future "upcoming" transactions up to a threshold date. Compare existing upcoming rows with the expected count; delete stale ones, create missing ones. Run this after sync and on a timer.
- Notifications with actions (execute, skip), optional calendar events in a dedicated calendar, widget list of upcoming items, count of unpaid due items for the badge.

### 5.3 Balances
- Account balance = signed sum of transaction amounts. Provide `includePending` and `asOfDate` parameters (observed on the running-balance operation). Keep cleared and uncleared totals separately.
- Folder total = sum of its accounts, converting each account's currency to the folder's display currency using `Currency.rate`. Folders holding several currencies need explicit handling.
- Net worth excludes accounts flagged `excluded_from_net_wealth` and hidden accounts when configured.
- Credit accounts: available credit = credit limit + balance (balance is negative when owed).
- Transfers are two linked transactions (`referenced_transaction`); deleting an account needs a transfer-handling step first.
- Recalculate affected accounts incrementally after any change; run a full rebuild as a maintenance action.

### 5.4 Budgets
Inferred from `updateBalanceOfBudget:` (call sequence only; verify against the formulas below with tests).
1. Determine the current period: start at `start_date`, add `repeat_duration` of `repeat_type` (day, week, month, year) until the period containing today.
2. Spent = sum of transaction amounts in the period, grouped by category, where: (category ∈ monitored categories, or all categories) AND (tag ∈ filtered tags when set) AND (tag ∉ excluded tags) AND (pending only when `include_pending` is set).
3. Convert each amount into the budget currency using the transaction currency's rate.
4. Period limit = latest `BudgetLimit` effective for the period, else `amount`. Remaining = limit − spent (+ carry-over).
5. Refunds: income-type transactions in monitored categories reduce spent; amounts that exceed spending are tracked in `unused_refunds`.
6. Carry-over: if enabled, the previous period's unspent balance is added to the next period's allowance; negative balances carry only when `carry_over_negative` is on. Store as `carryover_balance`.
7. Mark `pending_update` for sync; refresh widgets.
Provide an "over budget" count and a "total budgeted" figure, as the reference does.

### 5.5 Plans
Inferred from `DCPlanController` and `DCCalculatePlanPeriodOperation` call sequences.
- A plan spans a start month/year to an end month/year, with one PlanPeriod per month and PlanUnits holding planned amounts per item.
- Monthly amount for an item: annual amount ÷ 12 for yearly items; per-repeat-period division otherwise; one-off items appear only in the month of `payment_date`; weekly items use week-of-year stepping.
- For each period, actual spending is computed from reports (by category and tag) and matched to plan units. Transfers to excluded accounts and currency fluctuation are accounted for separately.
- Outputs per period: planned income, planned expenses, planned change in wealth, and actuals. A starting net worth seeds projected wealth.
- Suggestions: generate a draft plan from budgets, scheduled transactions, and the last three months of reports (excluding tags flagged to ignore).
- Periods can be calculated in parallel, each with its own context.

### 5.6 Import and export
- CSV, OFX, QIF/QFX import with a column/field mapping step, duplicate detection (match on date, amount, payee, external id), and import rules (merchant name → category, payee, tag, description).
- Export to CSV; optionally Numbers on macOS only (not applicable on iPhone).

## 6. iPhone UX design

Tab bar (5): **Accounts**, **Activity**, **Budgets**, **Plans**, **Scheduled**. A floating "+" opens **Add transaction** on every tab. A "More" sheet from Accounts holds Reports, Settings, Import/Export, Reconciliation.

Mac → iPhone mapping: the account sidebar becomes the Accounts tab; the transaction list + detail pane becomes Activity with push navigation; Mac secondary windows become sheets.

Screens:
1. **Accounts**: net worth header; folders with collapsible account rows; balance per account; toggle for cleared-only; credit accounts show available credit; tap an account to see its Activity filtered.
2. **Activity**: grouped by day; search; filters (account, category, tag, pending/reconciled); swipe to delete or toggle reconciled; detail shows splits, attachments, notes, location.
3. **Add transaction**: segmented Expense/Income/Transfer; amount keypad; payee with suggestions; account; category or splits; tag; date; repeat; attachments (camera/scan). Validation: an amount greater than zero is required, shown with an inline error.
4. **Budgets**: row per budget with progress bar, remaining amount, period label; over-budget rows in the danger color; detail shows transactions and limit history.
5. **Plans**: month picker; planned versus actual for income, expenses, and net wealth; item list; "suggest a plan" action.
6. **Scheduled**: list of upcoming items with next date and cadence; swipe to skip or execute now; edit amount before executing.
7. **Reports**: category trends and budget reports with Swift Charts.
8. **Settings**: iCloud sync status, lock (Face ID and PIN), currencies and rates, categories/tags/payees management, backups, import/export.

Visual direction: native iOS look (system colors, SF Symbols, Dynamic Type, dark mode), flat surfaces, one accent color, red only for overspending and negative balances, green for income. Original icon and name. All numbers right-aligned with monospaced digits; negative amounts show a leading minus. A clickable prototype of the tabs and the add sheet exists in the conversation (`iphone_ledger_prototype`); treat it as a layout sketch, not a pixel spec.

Accessibility: Dynamic Type support, VoiceOver labels for amounts ("minus forty-two dollars eighty"), 44 pt minimum tap targets.

## 7. Security and privacy

- All financial data stays on device and in the user's own iCloud. No third-party servers in v1.
- App lock with Face ID/PIN; blur the app switcher snapshot; Keychain for PIN hash.
- Request location and calendar permissions only when the related feature is first used, with plain-language purpose strings.
- Never log amounts or payees.

## 8. Build order

1. `LedgerCore` package: models-agnostic functions for date stepping (5.1), balances (5.3), budget period (5.4), plan monthly amounts (5.5), with tests.
2. App shell, persistence, Accounts, Activity, Add transaction.
3. Scheduled transactions (5.2), Budgets, Plans.
4. Reports, CSV import/export.
5. CloudKit sync and conflict policy.
6. Lock, notifications, widgets, App Intents.
7. OFX/QIF import and rules, reconciliation, calendar, OCR, sharing.

## 9. Test plan (acceptance)

Because logic was inferred, these tests define behavior and should be written first.
- Next date: monthly from Jan 31 yields Feb 28/29, then Mar 31 (no drift); every 2 weeks; yearly from Feb 29; "second Tuesday" across month boundaries; `afterDate` far in the future loops correctly; invalid type or duration returns nil.
- Processing: transfer with different currencies creates two linked legs with the right amounts; cashback adds a third transaction; ended schedules stop.
- Balances: sum with and without pending; as-of date; multi-currency folder total; credit available amount; excluded accounts.
- Budgets: period rollover, category and tag filtering, excluded tags, refunds, carry-over positive and negative, limit history override, currency conversion.
- Plans: annual ÷ 12, one-off month placement, parallel period calculation equals sequential.
- Money: no floating point; rounding mode is banker's or half-up, chosen once and documented.
- Sync: soft delete tombstones, two-device edit conflict resolved deterministically (last writer wins per record unless decided otherwise).

## 10. Risks and unknowns

- Budget and plan formulas are reconstructed from call sequences, not decompiled; expect corrections when compared with real use of the Mac app. If exact parity matters, run the Mac app with known data and compare outputs, or decompile with Ghidra (not installed).
- The reference app's premium/paywall and server are intentionally not replicated.
- Reproducing its exact UI would be a trademark and trade-dress risk; keep the design original.

## 11. Open decisions for the owner

1. Native SwiftUI or cross-platform.
2. SwiftData or Core Data (schema parity and Mac-database import).
3. Whether v1 includes sync, sharing, widgets and premium.
4. App name, icon and monetization.
5. Rounding mode and sign convention (default: expenses stored negative, half-up rounding to the currency's minor unit).
