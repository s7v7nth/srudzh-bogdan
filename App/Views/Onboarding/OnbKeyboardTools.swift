import SwiftUI
import UIKit

/// Панель над клавиатурой «вверх / вниз / Готово» и выделение всей суммы при входе в числовое поле.
/// Работает на уровне UIKit, поэтому подхватывает все поля экрана без привязки каждого к фокусу.
private final class OnbKeyboardAccessory: NSObject {
    static let shared = OnbKeyboardAccessory()
    private weak var current: UITextField?
    private var begin: NSObjectProtocol?
    private var refs = 0

    func attach() {
        refs += 1
        guard begin == nil else { return }
        begin = NotificationCenter.default.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] n in
            guard let tf = n.object as? UITextField else { return }
            self?.current = tf
            if tf.inputAccessoryView == nil {
                tf.inputAccessoryView = self?.makeBar()
                tf.reloadInputViews()
            }
            if tf.keyboardType == .decimalPad || tf.keyboardType == .numberPad {
                DispatchQueue.main.async { tf.selectAll(nil) }
            }
        }
    }

    func detach() {
        refs -= 1
        guard refs <= 0, let b = begin else { return }
        NotificationCenter.default.removeObserver(b); begin = nil; refs = 0
    }

    private func makeBar() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        bar.items = [
            UIBarButtonItem(image: UIImage(systemName: "chevron.up"), style: .plain, target: self, action: #selector(prev)),
            UIBarButtonItem(image: UIImage(systemName: "chevron.down"), style: .plain, target: self, action: #selector(next)),
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: String(localized: "common.done"), style: .done, target: self, action: #selector(done)),
        ]
        return bar
    }

    @objc private func prev() { move(-1) }
    @objc private func next() { move(1) }
    @objc private func done() { current?.resignFirstResponder() }

    private func move(_ delta: Int) {
        guard let cur = current, let window = cur.window else { return }
        let fields = textFields(in: window).sorted {
            let a = $0.convert($0.bounds, to: window), b = $1.convert($1.bounds, to: window)
            return abs(a.minY - b.minY) > 1 ? a.minY < b.minY : a.minX < b.minX
        }
        guard let i = fields.firstIndex(of: cur), fields.indices.contains(i + delta) else { return }
        let target = fields[i + delta]
        target.becomeFirstResponder()
        // Если поле за краем экрана, прокручиваем к нему.
        var v: UIView? = target.superview
        while let s = v, !(s is UIScrollView) { v = s.superview }
        (v as? UIScrollView)?.scrollRectToVisible(target.convert(target.bounds, to: v).insetBy(dx: 0, dy: -60), animated: true)
    }

    private func textFields(in view: UIView) -> [UITextField] {
        var out: [UITextField] = []
        for s in view.subviews where !s.isHidden && s.alpha > 0.01 {
            if let tf = s as? UITextField, tf.isEnabled { out.append(tf) } else { out += textFields(in: s) }
        }
        return out
    }
}

extension View {
    func onbKeyboardTools() -> some View {
        onAppear { OnbKeyboardAccessory.shared.attach() }
            .onDisappear { OnbKeyboardAccessory.shared.detach() }
    }
}
