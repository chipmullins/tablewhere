import SwiftUI
import UIKit
import PickerCore

/// Renders the picture shown in the vote bubble.
enum VoteBubbleImage {
    @MainActor
    static func render(session: GroupSession, tally: Tally) -> UIImage? {
        // Always the dark ForkRoad look, whatever mode the phone is in.
        let renderer = ImageRenderer(content: VoteBubbleCard(session: session, tally: tally)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct VoteBubbleCard: View {
    let session: GroupSession
    let tally: Tally

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Messages draws ForkRoad's app icon over the bubble's top-left
            // corner, so no icon of our own here, and room to its right.
            HStack(spacing: 8) {
                Text(session.mode == .plan ? "FORKROAD · THE PLAN"
                     : session.winner != nil ? "FORKROAD · DECIDED"
                     : session.mode == .spin ? "FORKROAD · SPIN" : "FORKROAD · VOTE")
                    .font(Theme.body(11, .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.accentText)
            }
            .padding(.leading, 30)
            .frame(minHeight: 24)

            if let winner = session.winner {
                Text(winner.name)
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(session.meetTime.map { "\(MeetTimes.label(for: $0)) · \(winner.category)" } ?? winner.category)
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.muted)
                if let note = session.trimmedNote {
                    // The plan's note, so one bubble says it all.
                    HStack(alignment: .top, spacing: 8) {
                        Capsule().fill(Theme.saffron).frame(width: 3)
                        Text("“\(note)”")
                            .font(Theme.body(13, .semibold))
                            .italic()
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else if session.mode == .spin {
                Text(session.isSurprise
                     ? "\(session.options.count) places nearby. \(session.createdByName) spins."
                     : "Everyone adds one place, then \(session.createdByName) spins.")
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.text)
                ForEach(session.options.prefix(4)) { option in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Theme.saffron)
                        Text(option.name).lineLimit(1)
                        Spacer()
                        Text(option.addedBy).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.text)
                }
                if session.options.count > 4 {
                    Text("+\(session.options.count - 4) more")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                }
            } else {
                let maxVotes = max(tally.counts.values.max() ?? 0, 1)
                ForEach(session.options.prefix(4)) { option in
                    let count = tally.count(for: option.id)
                    let leading = tally.leader == option.id
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(option.name).lineLimit(1)
                            Spacer()
                            Text("\(count)").foregroundStyle(leading ? Theme.accentText : Theme.muted)
                        }
                        .font(Theme.body(13, .semibold))
                        .foregroundStyle(Theme.text)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.track)
                                Capsule()
                                    .fill(leading ? Theme.saffron : Theme.trackFill)
                                    .frame(width: geo.size.width * CGFloat(count) / CGFloat(maxVotes))
                            }
                        }
                        .frame(height: 6)
                    }
                }
                if session.options.count > 4 {
                    Text("+\(session.options.count - 4) more")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(Theme.accentSoft)
    }
}
