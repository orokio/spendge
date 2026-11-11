import SwiftUI
import UIKit

/// 备注输入框：整块可点、回车即完成（不插入换行）、长文本自动换行。
/// 用 UITextView 是因为 SwiftUI 的多行 TextField 会把回车当成换行。
struct NoteTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .subheadline)
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.returnKeyType = .done
        view.isScrollEnabled = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            view.text = text
        }
        if isEditing, !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !isEditing, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: NoteTextView

        init(_ parent: NoteTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isEditing = false
        }

        /// 回车当作「完成」，不插入换行。
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if text == "\n" {
                textView.resignFirstResponder()
                return false
            }
            return true
        }
    }
}
