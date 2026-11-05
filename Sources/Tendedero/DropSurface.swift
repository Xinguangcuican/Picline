import AppKit

/// The layer the line is drawn on, which is also the thing a picture can be
/// dropped onto. It sits behind the SwiftUI content and passes everything
/// through by default: the panel decides when it may take the mouse, and the
/// line is only touchable while the pointer is on a photo, or while a drag is
/// under way.
final class DropSurface: NSView {
    /// The pasteboard items of a drop, in the order they were dragged.
    var onDrop: (([NSPasteboardItem]) -> Void)?
    /// A drag came in or left, so the line can show where it will land.
    var onDragChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Whether the drag holds something the line could hang. Only the types are
    /// looked at here: reading the picture itself on every mouse move would be
    /// a lot of work for a yes or no.
    private func carriesPicture(_ info: NSDraggingInfo) -> Bool {
        let types = info.draggingPasteboard.types ?? []
        return types.contains(.fileURL) || types.contains(.tiff) || types.contains(.png)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard carriesPicture(sender) else { return [] }
        onDragChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        carriesPicture(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragChange?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        carriesPicture(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragChange?(false)
        let items = sender.draggingPasteboard.pasteboardItems ?? []
        guard !items.isEmpty else { return false }
        onDrop?(items)
        return true
    }
}
