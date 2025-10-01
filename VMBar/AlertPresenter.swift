import AppKit

/// A lightweight utility for presenting blocking alerts in a macOS app.
///
/// AlertPresenter wraps `NSAlert` to make it easy to show a modal alert with a
/// message, optional informative text, and a configurable set of button titles.
/// The alert is presented synchronously using `NSAlert.runModal()`, so it will
/// block the current thread until the user dismisses it.
///
/// - Important: Call this API from the main thread, as AppKit UI work must be performed on the main run loop.
enum AlertPresenter {
    /// Presents a modal alert with the given message, informative text, and buttons.
    ///
    /// This method constructs an `NSAlert` configured with `.warning` style, adds the
    /// provided button titles in order, and then calls `runModal()` to block until
    /// the user makes a selection. Once the alert is dismissed, the optional
    /// `completion` closure is invoked synchronously with the resulting
    /// `NSApplication.ModalResponse`.
    ///
    /// - Parameters:
    ///   - messageText: The primary text displayed in bold at the top of the alert.
    ///   - informativeText: Secondary text displayed under the message that provides additional context.
    ///   - buttons: An array of button titles to display, in order from left to right.
    ///              The first title corresponds to `.alertFirstButtonReturn`, the second to
    ///              `.alertSecondButtonReturn`, and the third to `.alertThirdButtonReturn`.
    ///              Defaults to a single “OK” button.
    ///   - completion: An optional closure executed after the alert is dismissed, receiving
    ///                 the modal response returned by `runModal()`. This closure is called
    ///                 synchronously on the same thread that invoked this method.
    ///
    /// - Note: Because this uses `runModal()`, the call blocks until the user responds.
    ///         If you need a non-blocking presentation, consider presenting the alert as a sheet
    ///         with `beginSheetModal(for:completionHandler:)` instead.
    ///
    /// - Example:
    ///   ```
    ///   AlertPresenter.show(
    ///       messageText: "Delete File?",
    ///       informativeText: "This action cannot be undone.",
    ///       buttons: ["Delete", "Cancel"]
    ///   ) { response in
    ///       if response == .alertFirstButtonReturn {
    ///           // Perform deletion
    ///       }
    ///   }
    ///   ```
    static func show(messageText: String, informativeText: String, buttons: [String] = ["OK"], completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        for title in buttons {
            alert.addButton(withTitle: title)
        }
        let response = alert.runModal()
        completion?(response)
    }
}
