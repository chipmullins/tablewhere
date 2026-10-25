import SwiftUI
import UIKit
import PickerCore

/// Renders the picture shown in the vote bubble.
enum VoteBubbleImage {
    @MainActor
    static func render(session: GroupSession, tally: Tally) -> UIImage? {
        let renderer = ImageRenderer(content: VoteBubbleCard(session: session, tally: tally))
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct VoteBubbleCard: View {
    let session: GroupSession
    let tally: Tally

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .font(Theme.body(12, .bold))
                    .foregroundStyle(Theme.onSaffron)
                    .frame(width: 24, height: 24)
                    .background(Theme.saffron, in: RoundedRectangle(cornerRadius: 7))
                Text(session.winner == nil ? "FORKROAD · VOTE" : "FORKROAD · DECIDED")
                    .font(Theme.body(11, .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.saffron)
            }

            if let winner = session.winner {
                Text(winner.name)
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(winner.category)
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Theme.muted)
            } else {
                let maxVotes = max(tally.counts.values.max() ?? 0, 1)
                ForEach(session.options.prefix(4)) { option in
                    let count = tally.count(for: option.id)
                    let leading = tally.leader == option.id
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(option.name).lineLimit(1)
                            Spacer()
                            Text("\(count)").foregroundStyle(leading ? Theme.saffron : Theme.muted)
                        }
                        .font(Theme.body(13, .semibold))
                        .foregroundStyle(Theme.text)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(hex: 0x2A2A34))
                                Capsule()
                                    .fill(leading ? Theme.saffron : Color(hex: 0x5C5A66))
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
        .background(Color(hex: 0x1A1710))
    }
}
