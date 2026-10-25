import AppIntents
import Foundation

/// Действие для приложения «Команды»: автоматизация «пришло сообщение от банка» передаёт сюда текст СМС.
struct AddBankSMSIntent: AppIntent {
    static var title: LocalizedStringResource = "intent.addSMS.title"
    static var description = IntentDescription("intent.addSMS.desc")
    static var openAppWhenRun = false

    @Parameter(title: "intent.addSMS.text")
    var text: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = SMSImporter.importText(text, ctx: AppStore.container.mainContext, rates: AppStore.rates)
        // Команда может закончиться раньше паузы перед пересчётом, поэтому обновляем вечернюю сводку сразу.
        if case .added = outcome { await EveningNotifier.shared.scheduleNow() }
        let message: String
        switch outcome {
        case .added: message = String(localized: "intent.addSMS.added")
        case .duplicate: message = String(localized: "intent.addSMS.duplicate")
        case .unrecognized: message = String(localized: "intent.addSMS.unrecognized")
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct SrudzhShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddBankSMSIntent(),
                    phrases: ["Add bank SMS to \(.applicationName)"],
                    shortTitle: "intent.addSMS.title", systemImageName: "message")
    }
}
