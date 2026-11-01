import XCTest
@testable import PickerCore

final class MeetTimesTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 26) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m, second: s))!
    }

    private func clock(_ d: Date) -> String {
        let p = calendar.dateComponents([.hour, .minute, .second], from: d)
        return String(format: "%02d:%02d:%02d", p.hour!, p.minute!, p.second!)
    }

    func testPlansAWeekOutIncludeTheDate() {
        let en = Locale(identifier: "en_US")
        let now = date(12, 0)  // Mon, Oct 26
        // Mon, Nov 2 is 7 days out: the weekday alone would be ambiguous.
        let nov2 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 19, minute: 0))!
        let label = MeetTimes.label(for: nov2, now: now, calendar: calendar, locale: en)
        XCTAssertTrue(label.contains("Nov") && label.contains("2"), label)
        XCTAssertTrue(label.hasSuffix("7:00\u{202F}PM"), label)
        let phrase = MeetTimes.phrase(for: nov2, now: now, calendar: calendar, locale: en)
        XCTAssertTrue(phrase.hasSuffix(" at 7:00\u{202F}PM") && phrase.contains("Nov"), phrase)
        // Six days out still reads as just the weekday.
        XCTAssertTrue(MeetTimes.label(for: date(19, 0, day: 31), now: now, calendar: calendar, locale: en).hasPrefix("Sat "))
    }

    func testLabelSaysTomorrowOrTheDay() {
        let en = Locale(identifier: "en_US")
        let now = date(23, 10)  // Monday night
        XCTAssertEqual(MeetTimes.label(for: date(23, 45), now: now, calendar: calendar, locale: en), "11:45\u{202F}PM")
        XCTAssertEqual(MeetTimes.label(for: date(19, 0, day: 27), now: now, calendar: calendar, locale: en), "Tomorrow 7:00\u{202F}PM")
        XCTAssertTrue(MeetTimes.label(for: date(19, 0, day: 31), now: now, calendar: calendar, locale: en).hasPrefix("Sat "))
        XCTAssertEqual(MeetTimes.phrase(for: date(19, 0, day: 27), now: now, calendar: calendar, locale: en), "tomorrow at 7:00\u{202F}PM")
        XCTAssertEqual(MeetTimes.phrase(for: date(23, 45), now: now, calendar: calendar, locale: en), "at 11:45\u{202F}PM")
        XCTAssertEqual(MeetTimes.phrase(for: date(19, 0, day: 31), now: now, calendar: calendar, locale: en), "Sat at 7:00\u{202F}PM")
    }

    func testRoundsUpToQuarterHours() {
        XCTAssertEqual(clock(MeetTimes.nextQuarterHour(onOrAfter: date(18, 31), calendar: calendar)), "18:45:00")
        XCTAssertEqual(clock(MeetTimes.nextQuarterHour(onOrAfter: date(18, 45), calendar: calendar)), "18:45:00")
        XCTAssertEqual(clock(MeetTimes.nextQuarterHour(onOrAfter: date(18, 45, 10), calendar: calendar)), "19:00:00")
        XCTAssertEqual(clock(MeetTimes.nextQuarterHour(onOrAfter: date(23, 50), calendar: calendar)), "00:00:00")
    }

    func testSlotsAreCleanAndAtLeastFifteenMinutesOut() {
        let slots = MeetTimes.slots(from: date(18, 16), calendar: calendar)
        XCTAssertEqual(slots.map(clock), ["18:45:00", "19:00:00", "19:15:00", "19:30:00", "19:45:00"])
        let onTheDot = MeetTimes.slots(from: date(18, 0), count: 2, calendar: calendar)
        XCTAssertEqual(onTheDot.map(clock), ["18:15:00", "18:30:00"])
    }

    func testCustomTimeRollsToTomorrowWhenPast() {
        let later = MeetTimes.resolve(hour: 19, minute: 30, after: date(18, 0), calendar: calendar)
        XCTAssertEqual(later, date(19, 30))
        let past = MeetTimes.resolve(hour: 7, minute: 0, after: date(18, 0), calendar: calendar)
        XCTAssertEqual(past, date(7, 0, day: 27))
    }

    func testCuisineMatching() {
        XCTAssertTrue(CuisineFilter.mexican.matches(name: "Tortilla Coast", category: "Mexican"))
        XCTAssertTrue(CuisineFilter.mexican.matches(name: "Agave & Rye Tacos", category: "Restaurant"))
        XCTAssertTrue(CuisineFilter.mexican.matches(name: "Moe’s Southwest Grill", category: "Restaurant"))
        XCTAssertTrue(CuisineFilter.thai.matches(name: "Thai Orchid", category: "Restaurant"))
        XCTAssertFalse(CuisineFilter.thai.matches(name: "Thailand Imports", category: "Market"))
        XCTAssertFalse(CuisineFilter.bbq.matches(name: "Sora Ramen", category: "Japanese"))
        XCTAssertTrue(CuisineFilter.matches([], name: "Anything", category: "Restaurant"))
        XCTAssertTrue(CuisineFilter.matches([.bbq, .japanese], name: "Sora Ramen", category: "Restaurant"))
    }

    func testOldSessionsWithoutNoteStillDecode() throws {
        let json = """
        {"id":"s","title":"Dinner","joinCode":"ABC123","createdBy":"u","createdByName":"Chip",
         "createdAt":0,"mode":"vote","status":"open","options":[]}
        """.data(using: .utf8)!
        let session = try JSONDecoder().decode(GroupSession.self, from: json)
        XCTAssertNil(session.note)
        var withNote = session
        withNote.note = "  Bring a gift!  "
        XCTAssertEqual(withNote.trimmedNote, "Bring a gift!")
        withNote.note = "   "
        XCTAssertNil(withNote.trimmedNote)
    }
}
