import AppKit

final class RegionPickerController: NSObject {
    var onRegionSelected: ((CGRect) -> Void)?
    var onCancelled: (() -> Void)?

    private var pickerWindow: NSWindow?

    func show(on screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens[0]

        let window = PickerWindow(
            contentRect: targetScreen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.animationBehavior = .utilityWindow

        let overlay = RegionOverlayView(frame: targetScreen.frame)
        overlay.onRegionSelected = { [weak self] rect in
            self?.dismiss()
            self?.onRegionSelected?(rect)
        }
        overlay.onCancelled = { [weak self] in
            self?.dismiss()
            self?.onCancelled?()
        }

        window.contentView = overlay
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlay)

        self.pickerWindow = window
        NSCursor.crosshair.push()
    }

    func dismiss() {
        NSCursor.pop()
        pickerWindow?.close()
        pickerWindow = nil
    }
}

// MARK: - Window Subclass

private class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Overlay View

private final class RegionOverlayView: NSView {
    var onRegionSelected: ((CGRect) -> Void)?
    var onCancelled: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var dragStart: NSPoint?
    private var selectionRect: NSRect?
    private var isDragging = false
    private var isMoving = false
    private var moveAnchor: NSPoint?
    private var moveOriginalRect: NSRect?
    private var confirmButtonRect: NSRect?

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Dimmed overlay
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(bounds)

        guard let sel = selectionRect, sel.width > 20, sel.height > 20 else {
            drawInstructions(ctx)
            return
        }

        // Clear the selected area to reveal the desktop
        ctx.setBlendMode(.clear)
        ctx.fill(sel)
        ctx.setBlendMode(.normal)

        drawSelectionBorder(ctx, rect: sel)
        drawCornerHandles(ctx, rect: sel)
        drawDimensionsLabel(ctx, rect: sel)
        drawButtons(ctx, rect: sel)
    }

    private func drawInstructions(_ ctx: CGContext) {
        let title = "Drag to select recording area" as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(
            at: NSPoint(x: (bounds.width - titleSize.width) / 2,
                        y: (bounds.height - titleSize.height) / 2 - 15),
            withAttributes: titleAttrs
        )

        let sub = "Press Escape to cancel" as NSString
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
        ]
        let subSize = sub.size(withAttributes: subAttrs)
        sub.draw(
            at: NSPoint(x: (bounds.width - subSize.width) / 2,
                        y: (bounds.height - titleSize.height) / 2 + titleSize.height + 4),
            withAttributes: subAttrs
        )
    }

    private func drawSelectionBorder(_ ctx: CGContext, rect: NSRect) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(rect.insetBy(dx: -1, dy: -1))
    }

    private func drawCornerHandles(_ ctx: CGContext, rect: NSRect) {
        let handleSize: CGFloat = 8
        let positions = [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.midX, y: rect.minY),
            NSPoint(x: rect.midX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.midY),
            NSPoint(x: rect.maxX, y: rect.midY),
        ]

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        for p in positions {
            let r = CGRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2,
                           width: handleSize, height: handleSize)
            ctx.fillEllipse(in: r)
        }
        ctx.setShadow(offset: .zero, blur: 0)
    }

    private func drawDimensionsLabel(_ ctx: CGContext, rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attrs)
        let pillW = textSize.width + 20
        let pillH = textSize.height + 10
        let pillX = rect.midX - pillW / 2
        let pillY = rect.minY - pillH - 10

        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.addPath(pillPath)
        ctx.fillPath()

        text.draw(at: NSPoint(x: pillX + 10, y: pillY + 5), withAttributes: attrs)
    }

    private func drawButtons(_ ctx: CGContext, rect: NSRect) {
        let recordText = "Record This Area" as NSString
        let btnAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = recordText.size(withAttributes: btnAttrs)
        let btnW = textSize.width + 44
        let btnH: CGFloat = 38
        let btnX = rect.midX - btnW / 2
        let btnY = rect.maxY + 14

        let btnRect = CGRect(x: btnX, y: btnY, width: btnW, height: btnH)
        let btnPath = CGPath(roundedRect: btnRect, cornerWidth: 10, cornerHeight: 10, transform: nil)

        ctx.setFillColor(NSColor(red: 0.424, green: 0.361, blue: 0.906, alpha: 1.0).cgColor)
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(btnPath)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0)

        let dotRect = CGRect(x: btnX + 14, y: btnY + (btnH - 10) / 2, width: 10, height: 10)
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fillEllipse(in: dotRect)

        recordText.draw(at: NSPoint(x: btnX + 30, y: btnY + (btnH - textSize.height) / 2),
                        withAttributes: btnAttrs)
        confirmButtonRect = btnRect

        // Cancel text
        let cancelText = "or press Escape" as NSString
        let cancelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.4),
        ]
        let cancelSize = cancelText.size(withAttributes: cancelAttrs)
        cancelText.draw(at: NSPoint(x: rect.midX - cancelSize.width / 2,
                                    y: btnY + btnH + 8),
                        withAttributes: cancelAttrs)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let btn = confirmButtonRect, btn.contains(point), selectionRect != nil {
            confirmSelection()
            return
        }

        if let sel = selectionRect, sel.contains(point) {
            isMoving = true
            moveAnchor = point
            moveOriginalRect = sel
            return
        }

        dragStart = point
        isDragging = true
        selectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isMoving, let anchor = moveAnchor, let orig = moveOriginalRect {
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            selectionRect = orig.offsetBy(dx: dx, dy: dy)
            needsDisplay = true
            return
        }

        guard isDragging, let start = dragStart else { return }

        selectionRect = NSRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        isMoving = false
        moveAnchor = nil
        moveOriginalRect = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancelled?()
        case 36: confirmSelection()
        default: break
        }
    }

    private func confirmSelection() {
        guard let sel = selectionRect, sel.width > 50, sel.height > 50 else { return }
        onRegionSelected?(sel)
    }
}
