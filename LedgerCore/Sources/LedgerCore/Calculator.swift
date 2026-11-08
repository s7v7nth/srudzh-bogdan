import Foundation

/// Мини-калькулятор для поля суммы: «12,5+3*2» → 18,5. Поддерживает + − × ÷ с обычным приоритетом.
public enum Calculator {
    /// Есть ли в строке знак действия (минус в самом начале считается знаком числа, а не действием).
    public static func hasOperator(_ s: String) -> Bool {
        let t = normalize(s)
        return t.dropFirst().contains { "+-*/".contains($0) }
    }

    /// Считает выражение. Нет числа или деление на ноль → nil.
    public static func evaluate(_ s: String) -> Decimal? {
        let t = normalize(s)
        guard !t.isEmpty else { return nil }
        // Разбор на числа и действия.
        var numbers: [Decimal] = []
        var ops: [Character] = []
        var current = ""
        for (i, ch) in t.enumerated() {
            if "+-*/".contains(ch), i > 0 {
                guard let n = Decimal(string: current) else { return nil }
                numbers.append(n); ops.append(ch); current = ""
            } else {
                current.append(ch)
            }
        }
        guard let last = Decimal(string: current) else { return nil }
        numbers.append(last)
        // Сначала × и ÷.
        var outNums: [Decimal] = [numbers[0]]
        var outOps: [Character] = []
        for (i, op) in ops.enumerated() {
            let n = numbers[i + 1]
            switch op {
            case "*": outNums[outNums.count - 1] *= n
            case "/":
                guard n != 0 else { return nil }
                outNums[outNums.count - 1] /= n
            default: outOps.append(op); outNums.append(n)
            }
        }
        var result = outNums[0]
        for (i, op) in outOps.enumerated() {
            result = op == "+" ? result + outNums[i + 1] : result - outNums[i + 1]
        }
        return result
    }

    /// Результат для подстановки в поле: округлён до знаков валюты, без хвоста нулей.
    public static func resultText(_ s: String, currency: String) -> String? {
        guard let value = evaluate(s) else { return nil }
        var v = value, r = Decimal()
        NSDecimalRound(&r, &v, Money.fractionDigits(currency), .plain)
        return "\(r)"
    }

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-")
            .filter { !$0.isWhitespace }
    }
}
