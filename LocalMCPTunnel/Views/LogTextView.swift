import AppKit
import SwiftUI

struct LogTextView: NSViewRepresentable {
    let text: String
    @Binding var input: String
    let isInputEnabled: Bool
    let prompt: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        scrollView.documentView = textView

        context.coordinator.update(textView: textView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.update(textView: textView, scrollView: scrollView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LogTextView
        private var editableStart = 0
        private var isProgrammaticUpdate = false
        private var lastLogText = ""

        init(_ parent: LogTextView) {
            self.parent = parent
        }

        func update(textView: NSTextView, scrollView: NSScrollView) {
            let promptText = parent.isInputEnabled ? parent.prompt : ""
            let desiredText = parent.text + promptText + parent.input
            let logChanged = lastLogText != parent.text
            lastLogText = parent.text
            editableStart = (parent.text as NSString).length + (promptText as NSString).length

            guard textView.string != desiredText else { return }

            isProgrammaticUpdate = true
            let wasFirstResponder = textView.window?.firstResponder === textView
            textView.string = desiredText
            textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

            if wasFirstResponder && parent.isInputEnabled {
                textView.setSelectedRange(NSRange(location: (desiredText as NSString).length, length: 0))
            }
            isProgrammaticUpdate = false

            if logChanged {
                textView.scrollToEndOfDocument(nil)
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isProgrammaticUpdate, parent.isInputEnabled else { return false }

            let replacement = replacementString ?? ""
            if replacement == "\n" || replacement == "\r" {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onSubmit()
                }
                return false
            }

            guard affectedCharRange.location >= editableStart else {
                if !replacement.isEmpty {
                    let end = (textView.string as NSString).length
                    textView.setSelectedRange(NSRange(location: end, length: 0))
                    textView.insertText(replacement, replacementRange: NSRange(location: end, length: 0))
                }
                return false
            }

            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  let textView = notification.object as? NSTextView else { return }

            let fullText = textView.string as NSString
            guard editableStart <= fullText.length else { return }
            parent.input = fullText.substring(from: editableStart)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                  parent.isInputEnabled,
                  let textView = notification.object as? NSTextView else { return }

            let selection = textView.selectedRange()
            if selection.length == 0 && selection.location < editableStart {
                // 過去ログは選択可能。入力開始時のみ末尾へ移動するため、ここでは位置を維持する。
            }
        }
    }
}
