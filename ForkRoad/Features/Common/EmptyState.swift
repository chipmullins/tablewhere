import SwiftUI

/// A friendly empty screen: a small drawing, a headline with a bit of
/// personality, one plain sentence, one main button and an optional link.
/// Only shows when a screen has nothing in it; filled screens are unchanged.
struct EmptyState: View {
    enum Art { case plate, crossroads, chat, wheel }

    let art: Art
    let title: String
    let message: String
    var primary: (title: String, action: () -> Void)?
    var secondary: (title: String, action: () -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            EmptyArt(art: art)
                .padding(.bottom, 4)
            Text(title)
                .font(Theme.display(24))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Theme.body(15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let primary {
                Button(action: primary.action) {
                    Text(primary.title)
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.onSaffron)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 50)
                        .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                .padding(.top, 6)
            }
            if let secondary {
                Button(secondary.title, action: secondary.action)
                    .font(Theme.body(14, .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

/// The little saffron line drawings.
private struct EmptyArt: View {
    let art: EmptyState.Art

    var body: some View {
        Group {
            switch art {
            case .plate:
                ZStack {
                    Ellipse()
                        .stroke(Theme.accentText, lineWidth: 3)
                        .frame(width: 92, height: 26)
                        .offset(y: 22)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Theme.saffron)
                        .offset(y: -6)
                }
                .frame(width: 148, height: 148)
                .background(Theme.accentSoft, in: Circle())
            case .crossroads:
                Image(systemName: "signpost.right.and.left")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 148, height: 148)
                    .background(Theme.accentSoft, in: Circle())
            case .chat:
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Theme.trackFill.opacity(0.6)).frame(width: 10, height: 10)
                        }
                    }
                    .frame(width: 92, height: 64)
                    .background(Theme.surface, in: UnevenRoundedRectangle(
                        topLeadingRadius: 20, bottomLeadingRadius: 6,
                        bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous))
                    .overlay(UnevenRoundedRectangle(
                        topLeadingRadius: 20, bottomLeadingRadius: 6,
                        bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous)
                        .stroke(Theme.track, lineWidth: 2))
                    .offset(y: 18)
                    // The ForkRoad mark in the reply bubble.
                    ForkMark()
                        .frame(width: 40, height: 40)
                        .frame(width: 100, height: 70)
                        .background(Theme.saffron, in: UnevenRoundedRectangle(
                            topLeadingRadius: 20, bottomLeadingRadius: 20,
                            bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous))
                        .offset(x: 60, y: 62)
                }
                .frame(width: 160, height: 140, alignment: .topLeading)
            case .wheel:
                ZStack {
                    Circle()
                        .stroke(Theme.trackFill.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [8, 9]))
                        .frame(width: 88, height: 88)
                    dot(filled: true).offset(y: -44)
                    dot(filled: false).offset(x: 38, y: 22)
                    dot(filled: false).offset(x: -38, y: 22)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.accentText)
                }
                .frame(width: 120, height: 120)
            }
        }
        .accessibilityHidden(true)
    }

    private func dot(filled: Bool) -> some View {
        Circle()
            .fill(filled ? Theme.saffron : Theme.accentSoft)
            .overlay(Circle().strokeBorder(Theme.accentText, lineWidth: 2.5))
            .frame(width: 18, height: 18)
    }
}
