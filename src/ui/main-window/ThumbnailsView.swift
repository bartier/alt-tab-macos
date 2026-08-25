import Cocoa

class ThumbnailsView: NSVisualEffectView {
    let scrollView = ScrollView()
    let spaceLegendView = SpaceLegendView()
    let searchFieldView = SearchFieldView()
    static var recycledViews = [ThumbnailView]()
    var rows = [[ThumbnailView]]()
    static var thumbnailsWidth = CGFloat(0.0)
    static var thumbnailsHeight = CGFloat(0.0)

    convenience init() {
        self.init(frame: .zero)
        material = Appearance.material
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        updateRoundedCorners(Appearance.windowCornerRadius)
        addSubview(searchFieldView)
        addSubview(spaceLegendView)
        addSubview(scrollView)
        // TODO: think about this optimization more
        (1...20).forEach { _ in ThumbnailsView.recycledViews.append(ThumbnailView()) }
    }

    func reset() {
        // it would be nicer to remove this whole "reset" logic, and instead update each component to check Appearance properties before showing
        // Maybe in some Appkit willDraw() function that triggers before drawing it
        NSScreen.updatePreferred()
        Appearance.update()
        material = Appearance.material
        for i in 0..<ThumbnailsView.recycledViews.count {
            ThumbnailsView.recycledViews[i] = ThumbnailView()
        }
        updateRoundedCorners(Appearance.windowCornerRadius)
    }

    static func highlight(_ indexInRecycledViews: Int) {
        let view = recycledViews[indexInRecycledViews]
        view.indexInRecycledViews = indexInRecycledViews
        if view.frame != NSRect.zero {
            view.drawHighlight()
        }
    }

    /// using layer!.cornerRadius works but the corners are aliased; this custom approach gives smooth rounded corners
    /// see https://stackoverflow.com/a/29386935/2249756
    func updateRoundedCorners(_ cornerRadius: CGFloat) {
        if cornerRadius == 0 {
            maskImage = nil
        } else {
            let edgeLength = 2.0 * cornerRadius + 1.0
            let mask = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
                let bezierPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor.black.set()
                bezierPath.fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
            mask.resizingMode = .stretch
            maskImage = mask
        }
    }

    func nextRow(_ direction: Direction, allowWrap: Bool = true) -> [ThumbnailView]? {
        let step = direction == .down ? 1 : -1
        if let currentRow = Windows.focusedWindow()?.rowIndex {
            var nextRow = currentRow + step
            if nextRow >= rows.count {
                if allowWrap {
                    nextRow = nextRow % rows.count
                } else {
                    return nil
                }
            } else if nextRow < 0 {
                if allowWrap {
                    nextRow = rows.count + nextRow
                } else {
                    return nil
                }
            }
            if ((step > 0 && nextRow < currentRow) || (step < 0 && nextRow > currentRow)) &&
                   (ATShortcut.lastEventIsARepeat || KeyRepeatTimer.timer?.isValid ?? false) {
                return nil
            }
            return rows[nextRow]
        }
        return nil
    }

    func navigateUpOrDown(_ direction: Direction, allowWrap: Bool = true) {
        let focusedViewFrame = ThumbnailsView.recycledViews[Windows.focusedWindowIndex].frame
        let originCenter = NSMidX(focusedViewFrame)
        if let targetRow = nextRow(direction, allowWrap: allowWrap) {
            let leftSide = originCenter < NSMidX(frame)
            let leadingSide = App.shared.userInterfaceLayoutDirection == .leftToRight ? leftSide : !leftSide
            let iterable = leadingSide ? targetRow : targetRow.reversed()
            let targetView = iterable.first {
                if App.shared.userInterfaceLayoutDirection == .leftToRight {
                    return leadingSide ? NSMaxX($0.frame) > originCenter : NSMinX($0.frame) < originCenter
                }
                return leadingSide ? NSMinX($0.frame) < originCenter : NSMaxX($0.frame) > originCenter
            } ?? iterable.last!
            let targetIndex = ThumbnailsView.recycledViews.firstIndex(of: targetView)!
            Windows.updateFocusedAndHoveredWindowIndex(targetIndex)
        }
    }

    func updateItemsAndLayout() {
        let widthMax = ThumbnailsPanel.maxThumbnailsWidth().rounded()
        searchFieldView.refresh()
        spaceLegendView.refresh()
        if let (maxX, maxY, labelHeight) = layoutThumbnailViews(widthMax) {
            layoutParentViews(maxX, widthMax, maxY, labelHeight)
            if Preferences.alignThumbnails == .center {
                centerRows(maxX)
            }
            for row in rows {
                for (j, view) in row.enumerated() {
                    view.numberOfViewsInRow = row.count
                    view.isFirstInRow = j == 0
                    view.isLastInRow = j == row.count - 1
                    view.indexInRow = j
                }
            }
            highlightStartView()
        }
    }

    private func layoutThumbnailViews(_ widthMax: CGFloat) -> (CGFloat, CGFloat, CGFloat)? {
        let labelHeight = ThumbnailsView.recycledViews.first!.label.cell!.cellSize.height
        let height = ThumbnailView.height(labelHeight)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? Appearance.interCellPadding : widthMax - Appearance.interCellPadding
        var currentX = startingX
        var currentY = Appearance.interCellPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + Appearance.interCellPadding
        var newViews = [ThumbnailView]()
        rows.removeAll(keepingCapacity: true)
        rows.append([ThumbnailView]())
        for (index, window) in Windows.list.enumerated() {
            guard App.app.appIsBeingUsed else { return nil }
            guard window.shouldShowTheUser else { continue }
            let view = ThumbnailsView.recycledViews[index]
            view.updateRecycledCellWithNewContent(window, index, height)
            let width = view.frame.size.width
            let projectedX = projectedWidth(currentX, width).rounded(.down)
            if needNewLine(projectedX, widthMax) {
                currentX = startingX
                currentY = (currentY + height + Appearance.interCellPadding).rounded(.down)
                view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                currentX = projectedWidth(currentX, width).rounded(.down)
                maxY = max(currentY + height + Appearance.interCellPadding, maxY)
                rows.append([ThumbnailView]())
            } else {
                view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                currentX = projectedX
                maxX = max(isLeftToRight ? currentX : widthMax - currentX, maxX)
            }
            rows[rows.count - 1].append(view)
            newViews.append(view)
            window.rowIndex = rows.count - 1
        }
        scrollView.documentView!.subviews = newViews
        return (maxX, maxY, labelHeight)
    }

    private func needNewLine(_ projectedX: CGFloat, _ widthMax: CGFloat) -> Bool {
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return projectedX > widthMax
        }
        return projectedX < 0
    }

    private func projectedWidth(_ currentX: CGFloat, _ width: CGFloat) -> CGFloat {
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return currentX + width + Appearance.interCellPadding
        }
        return currentX - width - Appearance.interCellPadding
    }

    private func localizedCurrentX(_ currentX: CGFloat, _ width: CGFloat) -> CGFloat {
        App.shared.userInterfaceLayoutDirection == .leftToRight ? currentX : currentX - width
    }

    private func layoutParentViews(_ maxX: CGFloat, _ widthMax: CGFloat, _ maxY: CGFloat, _ labelHeight: CGFloat) {
        let heightMax = ThumbnailsPanel.maxThumbnailsHeight()
        ThumbnailsView.thumbnailsWidth = min(maxX, widthMax)
        ThumbnailsView.thumbnailsHeight = min(maxY, heightMax)
        let legendHeight = spaceLegendView.isHidden ? 0 : spaceLegendView.preferredHeight
        let legendGap = spaceLegendView.isHidden ? 0 : Appearance.intraCellPadding
        let searchHeight = searchFieldView.isHidden ? 0 : searchFieldView.preferredHeight
        let searchGap = searchFieldView.isHidden ? 0 : Appearance.intraCellPadding
        // the legend can be wider than the thumbnails (e.g. few narrow windows across many Spaces);
        // the panel must fit whichever is wider, or the legend chips overflow past the panel edges
        let legendWidth = spaceLegendView.isHidden ? 0 : min(spaceLegendView.fittingWidth.rounded(.up), widthMax)
        let searchWidth = searchFieldView.isHidden ? 0 : min(searchFieldView.fittingWidth.rounded(.up), widthMax)
        let contentWidth = max(ThumbnailsView.thumbnailsWidth, legendWidth, searchWidth)
        let frameWidth = contentWidth + Appearance.windowPadding * 2
        var frameHeight = ThumbnailsView.thumbnailsHeight + Appearance.windowPadding * 2 + legendHeight + legendGap + searchHeight + searchGap
        let originX = Appearance.windowPadding + ((contentWidth - ThumbnailsView.thumbnailsWidth) / 2).rounded()
        var originY = Appearance.windowPadding
        if Preferences.appearanceStyle == .appIcons {
            // If there is title under the icon on the last line, the height of the title needs to be subtracted.
            frameHeight = frameHeight - Appearance.intraCellPadding - labelHeight
            originY = originY - Appearance.intraCellPadding - labelHeight
        }
        frame.size = NSSize(width: frameWidth, height: frameHeight)
        // ThumbnailsView is not flipped: y=0 is bottom, so the search field and the legend go
        // near the top of the frame, the search field being the topmost row.
        searchFieldView.frame = NSRect(x: Appearance.windowPadding,
            y: frameHeight - Appearance.windowPadding - searchHeight,
            width: contentWidth, height: searchHeight)
        spaceLegendView.frame = NSRect(x: Appearance.windowPadding,
            y: frameHeight - Appearance.windowPadding - searchHeight - searchGap - legendHeight,
            width: contentWidth, height: legendHeight)
        scrollView.frame.size = NSSize(width: min(maxX, widthMax), height: min(maxY, heightMax))
        scrollView.frame.origin = CGPoint(x: originX, y: originY)
        scrollView.contentView.frame.size = scrollView.frame.size
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            let croppedWidth = widthMax - maxX
            scrollView.documentView!.subviews.forEach { $0.frame.origin.x -= croppedWidth }
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        if let existingTrackingArea = scrollView.trackingAreas.first {
            scrollView.removeTrackingArea(existingTrackingArea)
        }
        scrollView.addTrackingArea(NSTrackingArea(rect: scrollView.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: scrollView, userInfo: nil))
    }

    func centerRows(_ maxX: CGFloat) {
        var rowStartIndex = 0
        var rowWidth = Appearance.interCellPadding
        var rowY = Appearance.interCellPadding
        for (index, window) in Windows.list.enumerated() {
            guard App.app.appIsBeingUsed else { return }
            guard window.shouldShowTheUser else { continue }
            let view = ThumbnailsView.recycledViews[index]
            if view.frame.origin.y == rowY {
                rowWidth += view.frame.size.width + Appearance.interCellPadding
            } else {
                shiftRow(maxX, rowWidth, rowStartIndex, index)
                rowStartIndex = index
                rowWidth = Appearance.interCellPadding + view.frame.size.width + Appearance.interCellPadding
                rowY = view.frame.origin.y
            }
        }
        shiftRow(maxX, rowWidth, rowStartIndex, Windows.list.count)
    }

    private func highlightStartView() {
        // redraw every laid-out cell so stale focused/hovered styling on
        // previously-highlighted views is cleared, not just the two current ones
        for row in rows {
            for view in row {
                view.drawHighlight()
            }
        }
    }

    private func shiftRow(_ maxX: CGFloat, _ rowWidth: CGFloat, _ rowStartIndex: Int, _ index: Int) {
        let offset = ((maxX - rowWidth) / 2).rounded()
        if offset > 0 {
            for i in rowStartIndex..<index {
                ThumbnailsView.recycledViews[i].frame.origin.x += App.shared.userInterfaceLayoutDirection == .leftToRight ? offset : -offset
            }
        }
    }
}

class ScrollView: NSScrollView {
    // overriding scrollWheel() turns this false; we force it to be true to enable responsive scrolling
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    var isCurrentlyScrolling = false
    var previousTarget: ThumbnailView?

    convenience init() {
        self.init(frame: .zero)
        documentView = FlippedView(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        verticalScrollElasticity = .none
        scrollerStyle = .overlay
        scrollerKnobStyle = .light
        horizontalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        observeScrollingEvents()
    }

    private func observeScrollingEvents() {
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingStarted), name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingEnded), name: NSScrollView.didEndLiveScrollNotification, object: nil)
    }

    @objc private func scrollingStarted() {
        isCurrentlyScrolling = true
    }

    @objc private func scrollingEnded() {
        isCurrentlyScrolling = false
    }

    private func resetHoveredWindow() {
        if let oldIndex = Windows.hoveredWindowIndex {
            Windows.hoveredWindowIndex = nil
            ThumbnailsView.highlight(oldIndex)
            ThumbnailsView.recycledViews[oldIndex].showOrHideWindowControls(false)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // disable mouse hover during scrolling as it creates jank during elastic bounces at the start/end of the scrollview
        if isCurrentlyScrolling { return }
        if let hit = hitTest(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream) {
            var target: NSView? = hit
            while !(target is ThumbnailView) && target != nil {
                target = target!.superview
            }
            if let target = target as? ThumbnailView {
                if previousTarget != target {
                    previousTarget?.showOrHideWindowControls(false)
                    previousTarget = target
                }
                target.mouseMoved()
            } else {
                if !checkIfWithinInterPadding() {
                    resetHoveredWindow()
                }
            }
        } else {
            resetHoveredWindow()
        }
    }

    override func mouseExited(with event: NSEvent) {
        resetHoveredWindow()
    }

    /// Checks whether the mouse pointer is within the padding area around a thumbnail.
    ///
    /// This is used to avoid gaps between thumbnail views where the mouse pointer might not be detected.
    ///
    /// @return `true` if the mouse pointer is within the padding area around a thumbnail; `false` otherwise.
    private func checkIfWithinInterPadding() -> Bool {
        if Preferences.appearanceStyle == .appIcons {
            let mouseLocation = App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream
            let mouseRect = NSRect(x: mouseLocation.x - Appearance.interCellPadding,
                y: mouseLocation.y - Appearance.interCellPadding,
                width: 2 * Appearance.interCellPadding,
                height: 2 * Appearance.interCellPadding)
            if let hoveredWindowIndex = Windows.hoveredWindowIndex {
                let thumbnail = ThumbnailsView.recycledViews[hoveredWindowIndex]
                let mouseRectInView = thumbnail.convert(mouseRect, from: nil)
                if thumbnail.bounds.intersects(mouseRectInView) {
                    return true
                }
            }
        }
        return false
    }

    /// holding shift and using the scrolling wheel will generate a horizontal movement
    /// shift can be part of shortcuts so we force shift scrolls to be vertical
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) && event.scrollingDeltaY == 0 {
            let cgEvent = event.cgEvent!
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis2))
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: 0)
            super.scrollWheel(with: NSEvent(cgEvent: cgEvent)!)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

class SpaceLegendView: NSView {
    private let stackView = NSStackView()

    var preferredHeight: CGFloat {
        return Appearance.spaceLegendDotSize + 8
    }

    /// width the chips need; the panel is sized to fit this when it exceeds the thumbnails width
    var fittingWidth: CGFloat {
        return stackView.fittingSize.width
    }

    convenience init() {
        self.init(frame: .zero)
        wantsLayer = true
        // the legend receives its frame through manual layout; during transient states (first pass,
        // reset) the stack can be wider than that frame. Clip so chips never draw outside the panel.
        layer?.masksToBounds = true
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        let centerXConstraint = stackView.centerXAnchor.constraint(equalTo: centerXAnchor)
        let trailingConstraint = stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        // centerX and trailing are optional so a transiently zero-width frame is not a constraint
        // conflict (which shows AppKit's purple debugging window). Leading stays required: if the
        // stack ever exceeds the frame, it pins to the leading edge and clips at the trailing edge,
        // instead of the centered stack pushing the first chips out past the panel's left side.
        centerXConstraint.priority = .defaultHigh
        trailingConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerXConstraint,
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            trailingConstraint,
        ])
    }

    func refresh() {
        let hideForSingleSpace = Spaces.isSingleSpace()
        let hideForPreference = Preferences.hideSpaceNumberLabels
        let hideForStyle = Preferences.appearanceStyle == .appIcons
        if hideForSingleSpace || hideForPreference || hideForStyle {
            isHidden = true
            return
        }
        let uniqueSpaceIndexes = Set(
            Windows.list
                .filter { $0.shouldShowTheUser && !$0.isOnAllSpaces }
                .compactMap { $0.spaceIndexes.first }
                .filter { $0 <= 30 }
        ).sorted()
        if uniqueSpaceIndexes.isEmpty {
            isHidden = true
            return
        }
        isHidden = false
        stackView.setViews(uniqueSpaceIndexes.map { makeChip(for: $0) }, in: .leading)
    }

    private func makeChip(for spaceIndex: Int) -> NSView {
        let chip = NSStackView()
        chip.orientation = .horizontal
        chip.alignment = .centerY
        chip.spacing = 5
        let dot = SpaceLegendDotView(color: SpaceColors.color(forSpaceIndex: spaceIndex),
            diameter: Appearance.spaceLegendDotSize)
        let label = NSTextField(labelWithString: String(format: NSLocalizedString("Space %d", comment: ""), spaceIndex))
        label.font = NSFont.systemFont(ofSize: Appearance.spaceLegendChipFontSize, weight: .medium)
        label.textColor = Appearance.fontColor
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        chip.addArrangedSubview(dot)
        chip.addArrangedSubview(label)
        return chip
    }
}

/// shows the type-to-search query at the top of the panel. It is not a real NSTextField:
/// the switcher is a non-activating panel, so keystrokes are captured by the event tap and
/// this view only renders the resulting query
class SearchFieldView: NSView {
    private let label = NSTextField(labelWithString: "")

    var preferredHeight: CGFloat {
        return (Appearance.fontHeight * 1.6).rounded()
    }

    var fittingWidth: CGFloat {
        return label.fittingSize.width + Appearance.windowPadding * 2
    }

    convenience init() {
        self.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        label.font = NSFont.systemFont(ofSize: Appearance.fontHeight)
        label.lineBreakMode = .byTruncatingHead
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let leadingConstraint = label.leadingAnchor.constraint(equalTo: leadingAnchor)
        let trailingConstraint = label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        // optional, so a transiently zero-width frame is not a constraint conflict
        trailingConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingConstraint,
            trailingConstraint,
        ])
    }

    func refresh() {
        guard WindowSearch.isActive else {
            isHidden = true
            return
        }
        isHidden = false
        label.font = NSFont.systemFont(ofSize: Appearance.fontHeight)
        let query = WindowSearch.query
        if WindowSearch.hasNoMatches {
            label.stringValue = String(format: NSLocalizedString("%@ — no matching window", comment: ""), query)
            label.textColor = Appearance.fontColor.withAlphaComponent(0.6)
        } else {
            label.stringValue = query
            label.textColor = Appearance.fontColor
        }
    }
}

class SpaceLegendDotView: NSView {
    private let color: NSColor

    init(color: NSColor, diameter: CGFloat) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

enum Direction {
    case right
    case left
    case leading
    case trailing
    case up
    case down

    func step() -> Int {
        if self == .left {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? -1 : 1
        } else if self == .right {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? 1 : -1
        }
        return self == .leading ? 1 : -1
    }
}
