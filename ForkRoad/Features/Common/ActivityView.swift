import SwiftUI
import UIKit

/// The iPhone share sheet, for when it has to open on its own (SwiftUI's
/// ShareLink only opens from a tap on it). Present it in a `.sheet`.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    /// Called when the sheet closes; true if something was sent or copied.
    var onFinish: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
