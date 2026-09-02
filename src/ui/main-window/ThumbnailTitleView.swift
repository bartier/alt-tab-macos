import Cocoa

class ThumbnailTitleView: NSTextField {
    /// colour of the Group dot currently drawn in front of the title; nil when the window is Unknown
    var groupDotColor: NSColor?

    /// the title as the user reads it, without the Group dot; used for tooltips
    var titleWithoutGroupDot: String {
        return groupDotColor == nil ? stringValue : String(stringValue.dropFirst(ThumbnailView.groupDotPrefix.count))
    }
    convenience init(shadow: NSShadow?, font: NSFont) {
        self.init(labelWithString: "")
        self.font = font
        textColor = Appearance.fontColor
        self.shadow = shadow
        allowsDefaultTighteningForTruncation = false
        translatesAutoresizingMaskIntoConstraints = false
    }

    func fixHeight() {
        heightAnchor.constraint(equalToConstant: cell!.cellSize.height).isActive = true
    }

    override func mouseMoved(with event: NSEvent) {
        // no-op here prevents tooltips from disappearing on mouseMoved
    }

    func updateTruncationModeIfNeeded() {
        let newLineBreakMode = getTruncationMode()
        if lineBreakMode != newLineBreakMode {
            lineBreakMode = newLineBreakMode
        }
    }

    private func getTruncationMode() -> NSLineBreakMode {
        if Preferences.titleTruncation == .end {
            return .byTruncatingTail
        }
        if Preferences.titleTruncation == .middle {
            return .byTruncatingMiddle
        }
        return .byTruncatingHead
    }
}
