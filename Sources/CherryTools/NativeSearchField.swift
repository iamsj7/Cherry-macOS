import AppKit
import SwiftUI

struct NativeSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var onMove: ((Int) -> Void)?
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        field.delegate = context.coordinator
        // The field is rebuilt when the panel changes, so typing and arrow keys need it focused.
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField

        init(parent: NativeSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)) where parent.onMove != nil:
                parent.onMove?(1)
            case #selector(NSResponder.moveUp(_:)) where parent.onMove != nil:
                parent.onMove?(-1)
            case #selector(NSResponder.insertNewline(_:)) where parent.onSubmit != nil:
                parent.onSubmit?()
            case #selector(NSResponder.cancelOperation(_:)):
                if parent.text.isEmpty { AppController.shared?.closePopover() } else { parent.text = "" }
            default:
                return false
            }
            return true
        }
    }
}
