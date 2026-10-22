# Debit & Credit (Mac) – static reverse-engineering notes

Target: /Applications/Debit & Credit.app, v7.9 (build 2991), bundle `com.mr-brightside.debitandcreditMac`, by Ivan Pavlov. Universal binary (x86_64 + arm64), min macOS 12, Mac App Store build (sandboxed).
Method: otool / codesign / strings / plist + Core Data model parsing. Static only; nothing executed. Observations unless marked (inferred).

## Architecture
- `Debit & Credit` (10 MB): thin AppKit UI layer, `DCMac*` classes (storyboards + some SwiftUI/Charts for reports/plans/widgets).
- `DCCoreKit.framework` (5 MB): all business logic, shared with iOS (inferred: bundle IDs for iOS/watch/widget present). Controllers: Account, Budget, Category, Plan, Report, Statistics, Transaction, RecurringTransaction, Currency, Import, Export, Calculator, Metadata, CloudKit, CloudSharing, InApp, Pin, Rating, Location, Log, RestoreData.
- Work is done by an operation pipeline (`DC*Operation`): CloudKit download/modify/process, running-balance calc, plan-period calc, recurring-due, duplicate removal, expired-object deletion, calendar events, local notifications, app badge, attachment analysis (Vision OCR, thumbnails), subscription status download.
- Extensions: Share, Intents, App Intents, Widget. URL scheme `dcapp://`. Document types: CSV (viewer), OFX, QIF/QFX.

## Data model (Core Data, current version "DebitAndCredit 39", 39 migrations)
Every synced entity carries CloudKit fields: `recordName`, `recordChangeTag`, `ownerName`, `pending_update`, `deleteAfterDate` (soft delete).
- **Account**: name, type (Account_type), currency, folder (Account_folder), current/uncleared balance, credit_limit, show_available_credit, hidden, excluded_from_net_wealth, last_reconciled_balance, iconName, sort_id, wallet_account (Apple Wallet link w/ historyToken).
- **Account_folder**: name, iconName, expanded, show_balance, accounts.
- **Transaction**: amount, type, date/day/effectiveDate/postedDate, account, category, payee, description, tag, splits, attachments, notes, tax, pending, reconciled, imported, upcoming, externalID, referenced_transaction (transfers), recurring_transaction, originatingSource.
- **Split**: amount, category. **Attachment**: file name/size/contentType.
- **Recurring_transaction**: repeat/repeat_type/repeat_duration, start/next/last/end date, source/destination amount (transfers), cashback_account + percentage, autopay, notify, include_into_calendar, process_pending.
- **Budget** (+ **Budget_limit** history): categories_monitored, tags_filtered, exclude_tags, carry_over (+negative), repeat, include_pending, currency.
- **Plan** → Plan_period → Plan_unit; **Plan_item** (annual_amount, repeat_period, category, group_categories, tag, payment_date).
- **Transaction_category** (tree: parent/children, type), **Transaction_payee** (locations, last_used_category, usageRating), **Transaction_tag** (colour, defaultTag), **Transaction_description**, **Location** (lat/long, locality), **Import_rule** (merchantName → category/payee/tag/description).
- **Currency** (code, symbol, rate, crypto), **Account_type**, **Deleted** (tombstones), **System_object**.

## Features (from controllers, storyboards, plists)
Accounts + folders, multi-currency, transactions with splits/attachments/receipt analysis/location-suggested payees, recurring and scheduled transactions (calendar + notifications), budgets with carry-over, annual Plans, reports (categories trends, budgets, touch bar), bank reconciliation incl. PDF statements, import (CSV/OFX/QIF) with rules, export (incl. Numbers via Apple Events), PIN/biometric lock, backups/restore, CloudKit sync and CloudKit sharing, widgets, Siri/App Intents, menu bar controller, Apple Wallet account import.

## Entitlements / network
- iCloud container `iCloud.com.mr-brightside.debitandcreditCloudData` (CloudKit), KVS, app group `38AJRG7QR9.group.com.mr-brightside.debitandcredit` (shared SQLite `DebitAndCreditDatabase.sqlite` with extensions), push (production), maps, time-sensitive notifications, Apple Events, user-selected files r/w, network client.
- Only declared server: `api.debitandcredit.app` (premium status). Endpoints in DCCoreKit: `dc-check-account-status.php`, `dc-check-server.php`, `dc-get-purchase-token.php`, `dc-receipt-verification.php`, `dc-verify-transactions.php`.
- Premium via StoreKit: `com.mrbrightside.debitandcreditMac.premium`, `.premiumRenewable`, `.premiumRenewableWithTrial`. Free accounts have sharing disabled (`DCDisableShareOnFreeAccountOperation`).
- Privacy: calendars, location (payee suggestion), Apple Events usage strings.

## UI structure (to adapt for iPhone later)
Main window = split view: account outline list (folders/accounts) | transaction list | detail pane. Separate windows/sheets: Add transaction (`DCMacAddWindow`), Reconciliation, Reports (split: report list + report view), Plans (regular/section views + form), Budgets (+limits), Settings tabs (General, Cloud, Backups, Locations, Metadata, Sharing, Subscription), Import/Export, Help.
iPhone mapping suggestion: tab bar (Accounts, Transactions, Budgets/Plans, Reports, Settings), sheet for Add.

## Unknowns
Not examined: decompiled logic (balance/budget/plan math), server request/response formats, exact App Intents list, the iPhone binary. The user's local database was deliberately not opened.

---
# Part 2 – DCCoreKit logic (arm64 disassembly + selector traces)
No decompiler (Ghidra/Hopper/IDA) is installed, so these are read from `otool -tV` and per-function call sequences. Pseudocode is *inferred*; method/address names are observed. Addresses are DCCoreKit arm64 VM addresses.

## Recurring / scheduled transactions
- `+nextDateForRepeatType:andDuration:fromDate:afterDate:` (0x23090) – fully read:
  - Valid `repeat_type` 1…11, `duration` ≥ 1, otherwise returns nil.
  - 1 = day, 2 = week (weekOfMonth component), 3 = month, 4 = year; **5…11 = "nth weekday of month"** (`systemWeekdayForRepeatPeriod:` maps type−5 → weekday via a 7-entry table; duration is the ordinal, e.g. 2nd Tuesday).
  - If `afterDate` is nil or `fromDate > afterDate`: returns `fromDate + 1×duration` units (ordinal types: returns fromDate unchanged).
  - Otherwise loops i = 1,2,… with candidate = `fromDate + i×duration` units (always from the original fromDate, so month-end days don't drift) until candidate > afterDate.
  - Ordinal types: take time-of-day from current date, find `nextDateAfterDate:matchingComponents:{weekday, weekdayOrdinal}` (strict), re-add time-of-day, repeat until > afterDate.
- `-processRecurringTransactionID:withOptions:processedManually:` (0x282d0): loads object by ID; computes recorded date via `scheduledTransactionRecordedDate:ifExecutedNow:`; sets `last_date`, advances `next_date` via the function above, and if `end_date` passed / repeat is one-off, sets `end_date` or deletes. Builds a settings dict (amount, category, payee, tag, description, splits, `process_pending`, `autopay`); if `destination_account` is set → `createTransferWithSettings:` (uses `source_amount`/`destination_amount`), else `createTransactionWithSettings:`; if `cashback_percentage` and `cashback_account` are set a second cashback transaction is created. Then `updateBalanceUsingKVOForAccountID:`, `refreshUpcomingToken`.
- `DCInternalRecurringDueOperation` (0x12150c): keeps "upcoming" transactions in the ledger up to a `thresholdDateForUpcomingTransactions`; compares existing upcoming rows (by `upcomingChangeToken`) with the expected count, deletes stale ones, creates missing ones through `processRecurringTransactionID…` (not manual). Follows with balance update, notification refresh, CloudKit sync operations.
- Also: skip (`skipRecurringTransaction:`), execute now (with specific amount), notifications w/ actions, calendar items, widget data.

## Balances
- `DCCalculateRunningBalanceOperation` (0x70438): background-context fetch with Core Data expression (`sum` of `amount`) filtered by account, date (≤ date) and `includePending`; result via completion block. Balance = SUM(amount) over transactions, signed amounts (inferred).
- `DCInternalUpdateBalancesOperation` (0x8b400): recomputes `Account.current_balance`, `current_uncleared_balance`, folder totals (special handling for folders with multiple currencies, uses `Currency.rate`), optionally budgets (`incudeBudgets`), widgets, then chains CloudKit sync.
- `DCAccountController`: uncleared/pending/upcoming queries per account, `totalWealthStringValueClearedOnly:`, `balancingTransactionCreatedRecentlyOnAccount:` (reconciliation adjustments), transfers handled before account delete, free-tier limits (`…IsOverLimit`).

## Budgets – `-updateBalanceOfBudget:` (0x822b4)
1. Period start: from `start_date`, step by `repeat_type`/`repeat_duration` (day/week/month/year) using calendar components until the current period; uses `nextDateForRepeatType…`-style stepping.
2. Fetch `SUM(amount)` grouped by category with predicate: date in period AND (`all_categories` OR category ∈ `categories_monitored`) AND tags ∈ `tags_filtered` AND tag ∉ `exclude_tags` AND (`include_pending_transactions` or not pending).
3. Convert each transaction currency to budget currency with `rate` using NSDecimalNumber multiply/divide, rounded by a rounding behavior.
4. `current_balance` = limit for period (`limitForThePeriodStarting:` from `Budget_limit` history, else `amount`) minus spent; refunds exceeding spend tracked in `unused_refunds`.
5. `carry_over` / `carry_over_negative`: previous period's remainder is added into `carryover_balance` (only positive unless negative carry allowed).
6. Sets `pending_update` when shared budgets exist so CloudKit pushes; triggers widget refresh block.

## Plans
- `calculateFinancialPlan:` (0x120c0) runs one `DCCalculatePlanPeriodOperation` per `Plan_period` in parallel (own context/persistent store coordinator), producing planned income / expenses / wealth change vs actuals.
- Each period op: matches `Plan_unit`s to actual spending reports (by category/tag, `matchPlanUnits:transactionType:withActualReport:`), accounts for transfers to excluded accounts and **currency fluctuation** effects.
- `calculatedMonthlyAmountForStructureItem:periodMonth:periodYear:` (0xd310): `Plan_item` amount text parsed with system locale → NSDecimalNumber; dividing the annual amount by the repeat period (monthly = /12 etc.); one-off items placed only in the month of `payment_date`; weekly uses weekOfYear components.
- Suggestions: `generateSuggestedPlanWithCurrencyCode:` merges suggestions from budgets, scheduled transactions, and the last three months of reports (excluding tags flagged for exclusion).
- `startingNetWealthWithPlan:` seeds projected net wealth; analysis formatted for net wealth / income / expenses.

## Not yet done
Exact sign conventions, rounding mode, the Plan_item repeat_period enum values, and CloudKit conflict handling would need a real decompiler (Ghidra) or runtime tracing.
