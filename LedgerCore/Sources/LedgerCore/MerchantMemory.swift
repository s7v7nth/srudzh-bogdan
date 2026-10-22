import Foundation

public enum CategorySuggestion<ID: Hashable>: Equatable {
    /// Магазин видим впервые: показываем квиз со всеми категориями.
    case unknown
    /// Категория понятна: траты идут в дайджест уже с ней.
    case confident(ID)
    /// Были разные категории: квиз с вариантами, самые частые первыми.
    case ask([ID])
}

/// Память о магазинах: по прошлым ответам решает, спрашивать пользователя или подставить категорию.
public enum MerchantMemory {
    /// Сколько вариантов показывать в квизе (остальное через «другая категория»).
    public static let maxOptions = 3

    /// Ключ магазина: регистр, пунктуация, код страны и номер точки не мешают узнать тот же магазин.
    public static func key(_ merchant: String) -> String {
        var tokens = merchant.uppercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .map(String.init).joined()
            .split(separator: " ").map(String.init)
        if tokens.count > 1, tokens[0].count == 3, tokens[0].allSatisfy({ $0.isASCII && $0.isLetter }) { tokens.removeFirst() }
        while tokens.count > 1, tokens.last!.allSatisfy(\.isNumber) { tokens.removeLast() }
        return tokens.joined(separator: " ")
    }

    /// `counts`: сколько раз в этом магазине выбирали каждую категорию (порядок важен при равенстве).
    /// Одна категория за всё время → уверенно. Несколько → спрашиваем, но если одна категория
    /// явно доминирует (не меньше 80% при минимум 5 покупках), тоже берём её.
    public static func suggest<ID: Hashable>(counts: [(ID, Int)]) -> CategorySuggestion<ID> {
        let used = counts.filter { $0.1 > 0 }
        guard !used.isEmpty else { return .unknown }
        if used.count == 1 { return .confident(used[0].0) }
        let sorted = used.enumerated().sorted { ($0.element.1, $1.offset) > ($1.element.1, $0.offset) }.map(\.element)
        let total = sorted.reduce(0) { $0 + $1.1 }
        if total >= 5, sorted[0].1 * 5 >= total * 4 { return .confident(sorted[0].0) }
        return .ask(Array(sorted.prefix(maxOptions)).map(\.0))
    }
}
