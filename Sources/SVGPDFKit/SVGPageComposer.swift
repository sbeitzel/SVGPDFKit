import Foundation

/// Places an SVG document on a page: the geometry both rendering backends
/// share, plus the document rewrite the `rsvg-convert` backend needs in order
/// to honour it.
///
/// `rsvg-convert` sizes the drawing box with `--width`/`--height` but never
/// positions it: `--left` and `--top` default to zero and `--keep-aspect-ratio`
/// fits to the *top-left* of that box, so the whole of the removed margin piles
/// up against the right and bottom edges (issue #4). Passing `--left`/`--top`
/// is not a fix on its own either — one invocation renders every input with one
/// set of arguments, and pages that differ in shape need different offsets, so
/// a mixed-orientation binder cannot be centred from the command line at all.
///
/// The offset therefore goes into the document. `compose` wraps each page in a
/// page-sized root `<svg>` and turns the original document into a nested
/// viewport positioned at exactly the rect `fitRect` returns — the same rect
/// the CoreGraphics path draws into. rsvg-convert is then only asked to render
/// a page-shaped document onto a page, which it does without an opinion about
/// where things go.
enum SVGPageComposer {

    struct Size: Equatable {
        var width: Double
        var height: Double
    }

    struct Rect: Equatable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// The page a document declares for itself, and how it said so.
    struct IntrinsicPageSize: Equatable {

        /// Where the size was read from. A `width`/`height` pair is a statement
        /// of physical size; a bare `viewBox` is not, and the difference is
        /// worth telling a caller about.
        enum Source: Equatable {
            case widthAndHeight
            case viewBox
        }

        var size: PageSize
        var source: Source
    }

    // MARK: - Geometry

    /// The rect a document of `content` size occupies on the page: aspect-fitted
    /// inside the page less `margin` on all four edges, and centred in whatever
    /// slack the fit leaves over.
    ///
    /// Both backends position pages with this, so a page that is centred in a
    /// PDF built on macOS is centred in the same place on Linux.
    static func fitRect(content: Size, pageSize: PageSize, margin: Double) -> Rect {
        let contentRect = Rect(
            x: margin,
            y: margin,
            width: pageSize.width - 2 * margin,
            height: pageSize.height - 2 * margin
        )

        guard content.width > 0, content.height > 0 else { return contentRect }

        let scale = min(contentRect.width / content.width, contentRect.height / content.height)
        let fittedWidth = content.width * scale
        let fittedHeight = content.height * scale

        return Rect(
            x: contentRect.x + (contentRect.width - fittedWidth) / 2,
            y: contentRect.y + (contentRect.height - fittedHeight) / 2,
            width: fittedWidth,
            height: fittedHeight
        )
    }

    /// The factor an aspect-fit applies to a document of `content` size placed on
    /// `pageSize` with `margin` on every edge: 1 when it lands at its engraved
    /// size, less than 1 when the page forced it smaller.
    static func fitScale(content: Size, pageSize: PageSize, margin: Double) -> Double {
        guard content.width > 0 else { return 1 }
        return fitRect(content: content, pageSize: pageSize, margin: margin).width / content.width
    }

    /// Whether `content` and `pageSize` are different shapes — the tell that an
    /// explicit `pageSize` is not the one the document was engraved for.
    ///
    /// The comparison is against the page rather than the page less its margins,
    /// because a uniform margin does not preserve a page's proportions: a letter
    /// document inside 36pt margins fills a 540 × 720 box, which is 3% off letter
    /// and would report a mismatch on the most ordinary conversion there is. The
    /// 2% tolerance covers rounding in a producer's own arithmetic while leaving
    /// the case that matters — a landscape document on a portrait page — nowhere
    /// to hide.
    static func isDifferentShape(content: Size, from pageSize: PageSize) -> Bool {
        guard content.width > 0, content.height > 0, pageSize.height > 0 else { return false }
        let contentRatio = content.width / content.height
        let pageRatio = pageSize.width / pageSize.height
        return abs(contentRatio - pageRatio) / pageRatio > 0.02
    }

    // MARK: - Composition

    /// Rewrites `svgString` as a page-sized document with the original placed at
    /// its aspect-fitted, centred position.
    ///
    /// A document whose root `<svg>` cannot be found is returned unchanged —
    /// there is nothing to position, and rsvg-convert will have its own opinion
    /// about the markup soon enough. A document whose intrinsic size cannot be
    /// read is given the whole content rect, which is what it would have had
    /// before any of this existed.
    static func compose(page svgString: String, pageSize: PageSize, margin: Double) -> String {
        guard let rootTagRange = rootTagRange(in: svgString) else { return svgString }

        let rootTag = String(svgString[rootTagRange])
        let intrinsic = intrinsicSize(ofRootTag: rootTag)
        let frame = fitRect(content: intrinsic ?? Size(width: 0, height: 0),
                            pageSize: pageSize,
                            margin: margin)

        // The nested viewport carries our placement, so any size or position the
        // original declared for itself has to go; everything else about the tag
        // — namespaces, `color`, `version`, a `viewBox` — is the document's and
        // is left alone.
        var nested = removingAttributes(["x", "y", "width", "height"], from: rootTag)

        var placement = " x=\"\(format(frame.x))\" y=\"\(format(frame.y))\""
            + " width=\"\(format(frame.width))\" height=\"\(format(frame.height))\""

        // Without a viewBox a nested `<svg>` does not scale its contents to the
        // viewport we just gave it, so a document sized only by width/height
        // needs one synthesized from that size.
        if attribute("viewBox", in: rootTag) == nil, let intrinsic {
            placement += " viewBox=\"0 0 \(format(intrinsic.width)) \(format(intrinsic.height))\""
        }

        nested = "<svg" + placement + nested.dropFirst("<svg".count)

        // Anything ahead of the root tag is an XML declaration, a DOCTYPE or a
        // comment; none of it can survive being moved inside another element,
        // and none of it is needed to render.
        let body = svgString[rootTagRange.upperBound...]

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" \
        width="\(format(pageSize.width))pt" height="\(format(pageSize.height))pt" \
        viewBox="0 0 \(format(pageSize.width)) \(format(pageSize.height))">
        \(nested)\(body)
        </svg>

        """
    }

    // MARK: - Reading the root tag

    /// The page a document declares for itself, in points, and where that came
    /// from.
    ///
    /// This is what `ConversionOptions.pageSize == nil` renders onto, so unlike
    /// `intrinsicSize` the units are not incidental: a document sized
    /// `816px × 1056px` is a 612 × 792 pt page, because a CSS pixel is 1/96 inch
    /// and a point is 1/72. `rsvg-convert` reaches the same number from the same
    /// document, so both backends agree on the media box.
    static func intrinsicPageSize(ofRootTag rootTag: String) -> IntrinsicPageSize? {
        if let width = attribute("width", in: rootTag).flatMap(userUnits),
           let height = attribute("height", in: rootTag).flatMap(userUnits),
           width > 0, height > 0 {
            return IntrinsicPageSize(
                size: PageSize(width: width * pointsPerUserUnit, height: height * pointsPerUserUnit),
                source: .widthAndHeight
            )
        }

        // A `viewBox` with no `width`/`height` gives the document no intrinsic
        // size at all, only a coordinate system. Reading its extent as user units
        // is what every renderer does with it, `rsvg-convert` included, but it is
        // a guess about a producer's intent and is reported as one.
        if let viewBox = attribute("viewBox", in: rootTag) {
            let numbers = viewBox
                .split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .compactMap { Double($0) }
            if numbers.count == 4, numbers[2] > 0, numbers[3] > 0 {
                return IntrinsicPageSize(
                    size: PageSize(width: numbers[2] * pointsPerUserUnit,
                                   height: numbers[3] * pointsPerUserUnit),
                    source: .viewBox
                )
            }
        }

        return nil
    }

    /// `intrinsicPageSize(ofRootTag:)` for a whole document.
    static func intrinsicPageSize(ofDocument svgString: String) -> IntrinsicPageSize? {
        guard let rootTagRange = rootTagRange(in: svgString) else { return nil }
        return intrinsicPageSize(ofRootTag: String(svgString[rootTagRange]))
    }

    /// The intrinsic size of a document, in user units: its `width`/`height` if
    /// both are readable lengths, otherwise the size its `viewBox` declares.
    ///
    /// Only the ratio of the two ends up mattering to `fitRect`, but `compose`
    /// also synthesizes a `viewBox` from this, and a `viewBox` is written in the
    /// document's own user units — so this one stays unconverted.
    static func intrinsicSize(ofRootTag rootTag: String) -> Size? {
        guard let intrinsic = intrinsicPageSize(ofRootTag: rootTag) else { return nil }
        return Size(width: intrinsic.size.width / pointsPerUserUnit,
                    height: intrinsic.size.height / pointsPerUserUnit)
    }

    /// A CSS pixel is 1/96 inch; a PDF point is 1/72.
    static let pointsPerUserUnit = 72.0 / 96

    /// Converts an SVG length to user units (1 user unit = 1 CSS pixel).
    /// Percentages and other relative lengths have no size of their own and
    /// come back `nil`, which sends `intrinsicSize` on to the `viewBox`.
    private static func userUnits(_ length: String) -> Double? {
        let trimmed = length.trimmingCharacters(in: .whitespacesAndNewlines)
        let units: [(suffix: String, perUnit: Double)] = [
            ("px", 1), ("pt", 96.0 / 72), ("pc", 16), ("mm", 96.0 / 25.4),
            ("cm", 96.0 / 2.54), ("in", 96), ("q", 96.0 / 101.6)
        ]

        for (suffix, perUnit) in units where trimmed.lowercased().hasSuffix(suffix) {
            let value = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let number = Double(value) else { return nil }
            return number * perUnit
        }

        return Double(trimmed)
    }

    // MARK: - Tag surgery

    /// The range of the document's root `<svg …>` tag, open angle bracket to
    /// close. An attribute value containing `>` would fool this, as it would
    /// fool `PageNumberInjector`; no SVG producer we care about writes one.
    static func rootTagRange(in svgString: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: #"<svg\b[^>]*>"#),
              let match = regex.firstMatch(in: svgString, range: NSRange(svgString.startIndex..., in: svgString))
        else { return nil }
        return Range(match.range, in: svgString)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"(?:^|\s)"# + NSRegularExpression.escapedPattern(for: name)
            + #"\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else { return nil }

        for group in 1...2 {
            if let range = Range(match.range(at: group), in: tag) {
                return String(tag[range])
            }
        }
        return nil
    }

    private static func removingAttributes(_ names: [String], from tag: String) -> String {
        names.reduce(tag) { partial, name in
            // The leading whitespace is what keeps `width` from matching the
            // `width` inside `stroke-width`.
            let pattern = #"\s+"# + NSRegularExpression.escapedPattern(for: name)
                + #"\s*=\s*(?:"[^"]*"|'[^']*')"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return partial }
            return regex.stringByReplacingMatches(
                in: partial,
                range: NSRange(partial.startIndex..., in: partial),
                withTemplate: ""
            )
        }
    }

    /// Formats a coordinate for an attribute: enough precision for a page, no
    /// exponents, no locale — `String(format:)` with no locale is POSIX.
    private static func format(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        guard text.contains(".") else { return text }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
