import AppKit

/// A lightweight factory for generating small, colored circular icons that
/// visually represent a power state.
///
/// The factory produces 10×10 point `NSImage` instances by drawing a filled
/// circle using AppKit. State matching is case-insensitive.
///
/// Recognized states and their colors:
/// - "poweredOn": `NSColor.systemGreen`
/// - "poweredOff": `NSColor.systemRed`
/// - "suspended": `NSColor.systemOrange`
/// - "paused": `NSColor.systemYellow`
/// - Any other value: `NSColor.systemGray` (fallback)
///
/// Notes:
/// - Important: This method performs AppKit drawing and should be called on the main thread.
/// - Performance: Images are created on demand; consider caching results if used frequently.
enum PowerStateIconFactory {

    /// Creates a small circular image representing the provided power state.
    ///
    /// The returned image is 10×10 points and filled with a color mapped from the
    /// given state string. Matching is case-insensitive. Unrecognized states
    /// fall back to a gray circle.
    ///
    /// - Parameter state: A string describing the power state (e.g., "poweredOn",
    ///   "poweredOff", "suspended", "paused"). Matching is case-insensitive.
    /// - Returns: An `NSImage` containing a 10×10 filled circle that represents
    ///   the given state.
    ///
    /// Example:
    /// ```
    /// let image = PowerStateIconFactory.image(for: "poweredOn")
    /// ```
    static func image(for state: String) -> NSImage? {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)

        image.lockFocus()

        let color: NSColor
        switch state.lowercased() {
        case "poweredon":
            color = .systemGreen
        case "poweredoff":
            color = .systemRed
        case "suspended":
            color = .systemOrange
        case "paused":
            color = .systemYellow
        default:
            color = .systemGray
        }

        let circle = NSBezierPath(ovalIn: NSRect(origin: .zero, size: size))
        color.setFill()
        circle.fill()

        image.unlockFocus()
        return image
    }
}
