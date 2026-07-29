import AppKit

enum PenguinMenuBarIcon {
    static func make(frame: Int = 0) -> NSImage {
        let phase = ((frame % 4) + 4) % 4
        let bounce: CGFloat = phase.isMultiple(of: 2) ? 0 : 0.8
        let faceShift: [CGFloat] = [-0.45, 0, 0.45, 0]
        let leftFootX: [CGFloat] = [2.4, 3.3, 4.2, 3.3]
        let rightFootX: [CGFloat] = [10.8, 10, 9.2, 10]
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()

            let body = NSBezierPath(
                roundedRect: NSRect(x: 2.5, y: 1 + bounce, width: 13, height: 16 - bounce),
                xRadius: 6.5,
                yRadius: 7
            )
            body.appendOval(
                in: NSRect(
                    x: 5 + faceShift[phase],
                    y: 4 + bounce,
                    width: 8,
                    height: 10.5 - bounce
                )
            )
            body.windingRule = .evenOdd
            body.fill()

            let faceX = faceShift[phase]
            NSBezierPath(
                ovalIn: NSRect(x: 6.4 + faceX, y: 10.8 + bounce, width: 1.3, height: 1.3)
            ).fill()
            NSBezierPath(
                ovalIn: NSRect(x: 10.3 + faceX, y: 10.8 + bounce, width: 1.3, height: 1.3)
            ).fill()

            let beak = NSBezierPath()
            beak.move(to: NSPoint(x: 7.7 + faceX, y: 9.8 + bounce))
            beak.line(to: NSPoint(x: 10.3 + faceX, y: 9.8 + bounce))
            beak.line(to: NSPoint(x: 9 + faceX, y: 8.6 + bounce))
            beak.close()
            beak.fill()

            NSBezierPath(
                ovalIn: NSRect(x: leftFootX[phase], y: 0.25, width: 4.8, height: 1.9)
            ).fill()
            NSBezierPath(
                ovalIn: NSRect(x: rightFootX[phase], y: 0.25, width: 4.8, height: 1.9)
            ).fill()
            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = ProductBrand.displayName
        return image
    }
}
