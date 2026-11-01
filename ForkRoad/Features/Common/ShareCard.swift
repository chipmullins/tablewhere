import SwiftUI
import UIKit
import PickerCore

/// What a shared pick card is announcing.
enum PickShareContext: Equatable {
    /// Your own spin landed on it.
    case spin
    /// The group decided on it (with the meeting time and the plan's note, if set).
    case group(meetTime: Date?, note: String? = nil)

    var eyebrow: String {
        switch self {
        case .spin: return "THE WHEEL PICKED"
        case .group: return "WE’RE GOING TO"
        }
    }
}

/// A branded picture of a pick, for sharing to a group chat or a story:
/// night background, saffron accents, the place in big Outfit type.
/// Always drawn in the dark look, whatever the phone's appearance.
struct ShareCard: View {
    let name: String
    let detail: String
    let context: PickShareContext
    /// The plan's note ("Bring a gift!"), shown as a callout.
    let note: String?

    static let size = CGSize(width: 360, height: 450)  // 4:5, 1080×1350 at 3×

    init(place: Place, context: PickShareContext) {
        self.name = place.name
        self.context = context
        var parts = [place.category]
        if let area = Self.area(from: place.address) { parts.append(area) }
        var detail = parts.joined(separator: " · ")
        var note: String?
        if case .group(let meetTime, let groupNote) = context {
            if let meetTime { detail += "\nMeet \(MeetTimes.phrase(for: meetTime))" }
            note = groupNote?.trimmingCharacters(in: .whitespacesAndNewlines)
            if note?.isEmpty == true { note = nil }
        }
        self.detail = detail
        self.note = note
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x0B0B0F)  // fixed dark colors: ImageRenderer may ignore the color scheme
            // A warm glow in the corner.
            Circle()
                .fill(Theme.saffron.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: 170, y: -150)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image("ForkRoadLogo")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 30 * 0.225, style: .continuous))
                    Text("forkroad")
                        .font(Theme.display(18))
                        .foregroundStyle(Color(hex: 0xF5F3EE))
                }

                Spacer(minLength: 0)

                Text(context.eyebrow)
                    .font(Theme.body(13, .heavy))
                    .tracking(1.6)
                    .foregroundStyle(Theme.saffron)
                    .padding(.bottom, 10)
                Text(name)
                    .font(Theme.display(44))
                    .foregroundStyle(Color(hex: 0xF5F3EE))
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                Text(detail)
                    .font(Theme.body(17, .semibold))
                    .foregroundStyle(Color(hex: 0xA19FAA))
                    .lineLimit(3)
                if let note {
                    // The note, like a sticky on the invite: saffron bar, quoted.
                    HStack(alignment: .top, spacing: 10) {
                        Capsule()
                            .fill(Theme.saffron)
                            .frame(width: 3)
                        Text("“\(note)”")
                            .font(Theme.body(15, .semibold))
                            .italic()
                            .foregroundStyle(Color(hex: 0xF5F3EE))
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 16)
                }

                Spacer(minLength: 0)

                Capsule()
                    .fill(Theme.saffron)
                    .frame(width: 36, height: 4)
                    .padding(.bottom, 12)
                Text("forkroad · where to eat, decided")
                    .font(Theme.body(13, .semibold))
                    .foregroundStyle(Color(hex: 0xA19FAA))
            }
            .padding(28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.large)
    }

    /// The city from a MapKit address ("12 Main St, Lexington, KY 40507, United States").
    static func area(from address: String?) -> String? {
        guard let parts = address?.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }),
              parts.count >= 3, !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    /// The card as a 3× image.
    @MainActor
    func rendered() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// Shares a pick as a `ShareCard` image. The image is drawn when the button
/// appears (ShareLink needs it up front); until then the label shows dimmed.
struct SharePickButton<LabelView: View>: View {
    let place: Place
    let context: PickShareContext
    @ViewBuilder var label: () -> LabelView

    @State private var image: Image?

    var body: some View {
        let card = ShareCard(place: place, context: context)
        Group {
            if let image {
                ShareLink(item: image,
                          subject: Text(card.name),
                          message: Text("\(context == .spin ? "The wheel picked" : "We’re going to") \(card.name)"),
                          preview: SharePreview(card.name, image: image)) {
                    label()
                }
            } else {
                label().opacity(0.5)
            }
        }
        .task(id: "\(card.name)|\(card.detail)|\(card.note ?? "")|\(context.eyebrow)") { @MainActor in
            image = card.rendered().map { Image(uiImage: $0) }
        }
    }
}
