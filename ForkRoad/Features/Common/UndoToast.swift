import SwiftUI
import UIKit

/// "Blacklisted Taco Hut · Undo" — a short toast after anything you might
/// regret: blacklisting, removing from a list, clearing your wheel.
/// One at a time; a new one replaces the last. It hides itself after a few seconds.
@MainActor @Observable
final class UndoCenter {
    static let shared = UndoCenter()

    struct Item: Identifiable {
        let id = UUID()
        let message: String
        let undo: @MainActor () -> Void
    }

    private(set) var current: Item?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, undo: @escaping @MainActor () -> Void) {
        let item = Item(message: message, undo: undo)
        withAnimation(.snappy) { current = item }
        UIAccessibility.post(notification: .announcement, argument: "\(message). Undo available.")
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 10 : 5))
            guard !Task.isCancelled else { return }
            self?.hide(item.id)
        }
    }

    func performUndo() {
        guard let item = current else { return }
        item.undo()
        hide(item.id)
    }

    func hide(_ id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        withAnimation(.snappy) { current = nil }
    }
}

/// Sits above the floating tab bar. Added once, in RootTabView.
struct UndoToastHost: View {
    @State private var center = UndoCenter.shared

    var body: some View {
        if let item = center.current {
            HStack(spacing: 12) {
                Text(item.message)
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.night)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Undo") { center.performUndo() }
                    .font(Theme.body(14, .heavy))
                    .foregroundStyle(Color(light: 0xFFB23F, dark: 0x9A5B00))  // reads on the inverted toast
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .background(Theme.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 80)  // above the floating tab bar
            .id(item.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                if value.translation.height > 10 { center.hide() }
            })
        }
    }
}
