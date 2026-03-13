import CoreGraphics
import Foundation

/// The physical dimensions of a PDF page, in points (1 point = 1/72 inch).
public struct PageSize: Sendable {
    public let width: CGFloat
    public let height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    public var cgRect: CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }
}

// MARK: - Standard Presets

extension PageSize {
    /// US Letter: 8.5 × 11 inches
    public static let letter = PageSize(width: 612, height: 792)

    /// US Letter landscape: 11 × 8.5 inches
    public static let letterLandscape = PageSize(width: 792, height: 612)

    /// A4: 210 × 297 mm
    public static let a4 = PageSize(width: 595.28, height: 841.89)

    /// A4 landscape: 297 × 210 mm
    public static let a4Landscape = PageSize(width: 841.89, height: 595.28)

    /// A3: 297 × 420 mm
    public static let a3 = PageSize(width: 841.89, height: 1190.55)
}
