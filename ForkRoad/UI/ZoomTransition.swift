import SwiftUI

/// Zoom transitions into place details: the tapped row or card grows into the
/// detail screen. iOS 18+ only; on iOS 17 these do nothing and the push is
/// the standard slide. Pair a `zoomSource` and a `zoomDestination` with the
/// same ID (the place's ID) and the same `@Namespace`.
extension View {
    /// Marks where the zoom starts. A nil namespace does nothing.
    @ViewBuilder
    func zoomSource(id: some Hashable, ns: Namespace.ID?) -> some View {
        if let ns {
            if #available(iOS 18, *) {
                matchedTransitionSource(id: id, in: ns)
            } else {
                self
            }
        } else {
            self
        }
    }

    /// Put on the pushed screen (inside `navigationDestination`). A nil
    /// namespace does nothing.
    @ViewBuilder
    func zoomDestination(id: some Hashable, ns: Namespace.ID?) -> some View {
        if let ns {
            if #available(iOS 18, *) {
                navigationTransition(.zoom(sourceID: id, in: ns))
            } else {
                self
            }
        } else {
            self
        }
    }
}
