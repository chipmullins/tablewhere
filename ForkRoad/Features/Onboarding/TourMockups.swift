import SwiftUI
import PickerCore

// Small illustrated mockups for the tour pages, built from the app's real
// components (not screenshots), so they follow the theme, light and dark,
// and Dynamic Type. They're pictures: VoiceOver hears one label each.

/// A card that holds a mockup, a bit smaller than the real screens.
private struct TourCard<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: 340, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline))
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.45, bounce: 0.25).delay(0.05)) { shown = true }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

private func chip(_ text: String, systemImage: String? = nil, isOn: Bool = false) -> some View {
    HStack(spacing: 4) {
        if let systemImage { Image(systemName: systemImage) }
        Text(text)
    }
    .font(Theme.body(12, .semibold))
    .foregroundStyle(isOn ? Theme.onSaffron : Theme.text)
    .padding(.horizontal, 10)
    .frame(height: 28)
    .background(isOn ? Theme.saffron : Theme.surfaceHigh, in: Capsule())
}

private func placeRow(_ name: String, _ category: String, _ detail: String) -> some View {
    HStack(spacing: 10) {
        MonogramTile(name: name, category: category, size: 34)
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(Theme.body(14, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Text(detail).font(Theme.body(11)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        Spacer(minLength: 0)
    }
}

/// Spin: Eat out | Eat in, a landed pick, the Spin button, filter chips.
struct TourSpinMock: View {
    var body: some View {
        TourCard(label: "The Spin screen: Tonight?, Eat out or Eat in, and one big Spin button") {
            HStack(alignment: .firstTextBaseline) {
                Text("Tonight?").font(Theme.display(20)).foregroundStyle(Theme.text)
                Spacer()
                Text("21 places nearby").font(Theme.body(11, .medium)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 0) {
                Text("Eat out").frame(maxWidth: .infinity, minHeight: 28)
                    .background(Theme.segmentThumb, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(Theme.text)
                Text("Eat in").frame(maxWidth: .infinity, minHeight: 28).foregroundStyle(Theme.muted)
            }
            .font(Theme.body(12, .bold))
            .padding(3)
            .background(Theme.segmentTrack, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(spacing: 2) {
                Image(systemName: "sparkles").font(.system(size: 18, weight: .bold))
                Text("Spin").font(Theme.display(20))
            }
            .foregroundStyle(Theme.onSaffron)
            .frame(width: 92, height: 92)
            .background(Theme.saffron, in: Circle())
            .background(Circle().fill(Theme.accentSoft).padding(-8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            Text("No fast food · skips places you’ve had lately")
                .font(Theme.body(11, .medium))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Lists: Favorites, To try, Home, Blacklist.
struct TourListsMock: View {
    var body: some View {
        TourCard(label: "Your lists: Favorites, To try, Home, and Blacklist") {
            HStack(spacing: 6) {
                chip("Favorites", systemImage: "heart.fill", isOn: true)
                chip("To try", systemImage: "bookmark.fill")
                chip("Home", systemImage: "house.fill")
            }
            placeRow("Goodfellas Pizzeria", "Pizza", "Favorite · 1.2 mi")
            placeRow("Tatsu Sushi", "Japanese", "To try · 0.8 mi")
            placeRow("Taco night", "Mexican", "Home meal")
            HStack(spacing: 6) {
                Image(systemName: "nosign")
                Text("Blacklisted places never come up")
            }
            .font(Theme.body(12, .semibold))
            .foregroundStyle(Theme.muted)
        }
    }
}

/// Groups: the four ways, using the setup screen's own rows.
struct TourGroupWaysMock: View {
    var body: some View {
        TourCard(label: "The four ways to decide: Vote, Spin our picks, Surprise us, and I’ll pick") {
            ForEach(SetupMode.allCases) { mode in
                SetupModeRow(option: mode, isOn: mode == .vote)
            }
        }
    }
}

/// Groups: a link in the chat, picks coming in, "everyone's in".
struct TourJoinMock: View {
    var body: some View {
        TourCard(label: "Friends add picks from a link; 3 of 6 picks are in") {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(Theme.body(13, .bold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Friday dinner").font(Theme.body(13, .semibold)).foregroundStyle(Theme.text)
                    Text("Add your pick · no app needed").font(Theme.body(11)).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: -8) {
                ForEach(["Sam", "Alex", "Jo", "Maya"], id: \.self) { name in
                    let colors = Theme.tileColors(for: name)
                    Text(String(name.prefix(1)))
                        .font(Theme.body(12, .bold))
                        .foregroundStyle(colors.ink)
                        .frame(width: 30, height: 30)
                        .background(colors.background, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                }
                Text("3 of 6 picks in")
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.leading, 16)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.saffron).frame(width: geo.size.width * 0.5)
                }
            }
            .frame(height: 8)
            placeRow("Sora Ramen", "Ramen", "Sam’s pick")
            placeRow("Goodfellas Pizzeria", "Pizza", "Alex’s pick")
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill").foregroundStyle(Theme.accentText)
                Text("Everyone’s in! Time to spin.").font(Theme.body(12, .semibold)).foregroundStyle(Theme.text)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Plans: time, who's coming, leave by, On my way, the Lock Screen countdown.
struct TourPlanMock: View {
    var body: some View {
        TourCard(label: "A plan: Sora Ramen Saturday at 7, 4 coming, leave by 6:42, Sam is on the way, and a Lock Screen countdown") {
            HStack(spacing: 10) {
                MonogramTile(name: "Sora Ramen", category: "Ramen", size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sora Ramen").font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                    Text("Sat at 7:00 PM · 4 coming").font(Theme.body(12)).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "car.fill").foregroundStyle(Theme.accentText)
                Text("Leave by 6:42").font(Theme.body(13, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                chip("I’m on my way", isOn: true)
            }
            Text("Sam ~7:05 · Alex ~7:12 · Jo hasn’t left")
                .font(Theme.body(12, .semibold))
                .foregroundStyle(Theme.muted)
            // The Lock Screen countdown.
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(Theme.body(13, .bold))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(width: 28, height: 28)
                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Leave in 12 min").font(Theme.body(14, .bold)).foregroundStyle(.white)
                    Text("Sora Ramen · 7:00 PM").font(Theme.body(11)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text("12:30").font(Theme.display(18)).foregroundStyle(Theme.saffron).monospacedDigit()
            }
            .padding(10)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
