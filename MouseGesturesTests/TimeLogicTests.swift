// swiftlint:disable all  — dense table-driven cases ported from the plugins' scratch tests
import XCTest


final class TimeLogicTests: XCTestCase {
    // The rules parse dates in the system zone (as the app does) while these tests compare in New York time, so pin the
    // system zone; otherwise they only pass on a machine that happens to be in that zone (CI runs in UTC).
    private var savedZone: TimeZone!
    override func setUp() {
        super.setUp()
        savedZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/New_York")!
    }
    override func tearDown() {
        NSTimeZone.default = savedZone
        super.tearDown()
    }

    private func eq<T: Equatable>(_ a: T, _ b: T, _ n: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, n, file: file, line: line)
    }

    func testClockDaysDurationsRulesAndSun() {
        for (s,e) in [("7",(7,0)),("7pm",(19,0)),("7:30 pm",(19,30)),("12am",(0,0)),("12pm",(12,0)),("19:30",(19,30)),("noon",(12,0)),("midnight",(0,0)),("7:05am",(7,5))] { let r=TimeLogic.parseClock(s); eq(r?.hour,e.0,"clock h \(s)"); eq(r?.minute,e.1,"clock m \(s)") }
        for s in ["25:00","7:60","13pm","abc","","0pm"] { eq(TimeLogic.parseClock(s)==nil,true,"clock bad \(s)") }
        eq(TimeLogic.parseDays("weekdays"),[2,3,4,5,6],"wd"); eq(TimeLogic.parseDays("mon,wed,fri"),[2,4,6],"mwf"); eq(TimeLogic.parseDays("fri-mon"),[6,7,1,2],"wrap"); eq(TimeLogic.parseDays("xyz")==nil,true,"bad day")
        for (s,e) in [("90s",90.0),("5m",300.0),("5 min",300.0),("2h",7200.0),("1.5 hours",5400.0),("1h30m",5400.0),("1h 30m",5400.0)] { eq(TimeLogic.parseDuration(s),e,"dur \(s)") }
        eq(TimeLogic.parseDuration("banana")==nil,true,"dur bad"); eq(TimeLogic.parseDuration("5 bananas 3m")==nil,true,"dur junk")
        eq(TimeLogic.formatDuration(90),"1 min 30 s","fmt"); eq(TimeLogic.formatDuration(5400),"1 h 30 min","fmt h")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        func d(_ s: String) -> Date { let f=DateFormatter(); f.calendar=cal; f.timeZone=cal.timeZone; f.dateFormat="yyyy-MM-dd HH:mm"; return f.date(from:s)! }
        func fmt(_ x: Date?) -> String { guard let x=x else {return "nil"}; let f=DateFormatter(); f.calendar=cal; f.timeZone=cal.timeZone; f.dateFormat="yyyy-MM-dd HH:mm"; return f.string(from:x) }
        // 2026-10-09 is a Friday
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("8:30")!,after:d("2026-10-09 07:00"),lat:nil,lon:nil,calendar:cal)),"2026-10-09 08:30","clock today")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("8:30")!,after:d("2026-10-09 09:00"),lat:nil,lon:nil,calendar:cal)),"2026-10-10 08:30","clock tomorrow")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("weekdays 8:30")!,after:d("2026-10-09 09:00"),lat:nil,lon:nil,calendar:cal)),"2026-10-12 08:30","weekdays skip weekend")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("sat,sun 10pm")!,after:d("2026-10-09 09:00"),lat:nil,lon:nil,calendar:cal)),"2026-10-10 22:00","weekend")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("mon 7am")!,after:d("2026-10-09 09:00"),lat:nil,lon:nil,calendar:cal)),"2026-10-12 07:00","mon")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("every 30 min")!,after:d("2026-10-09 09:10"),lat:nil,lon:nil,calendar:cal)),"2026-10-09 09:30","every30")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("every 30 min")!,after:d("2026-10-09 09:30"),lat:nil,lon:nil,calendar:cal)),"2026-10-09 10:00","every30 strict")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("every 1h")!,after:d("2026-10-09 23:10"),lat:nil,lon:nil,calendar:cal)),"2026-10-10 00:00","every h across midnight")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("every 30 min 9:00-17:00")!,after:d("2026-10-09 17:00"),lat:nil,lon:nil,calendar:cal)),"2026-10-10 09:00","window next day")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("weekdays every 2h")!,after:d("2026-10-09 23:00"),lat:nil,lon:nil,calendar:cal)),"2026-10-12 00:00","weekday every")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("monthly 15 9:00")!,after:d("2026-10-09 09:00"),lat:nil,lon:nil,calendar:cal)),"2026-10-15 09:00","monthly")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("monthly 31 9:00")!,after:d("2026-11-01 09:00"),lat:nil,lon:nil,calendar:cal)),"2026-12-31 09:00","monthly skip short month")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("2026-12-25 08:00")!,after:d("2026-10-09 09:00"),lat:nil,lon:nil,calendar:cal)),"2026-12-25 08:00","once")
        eq(TimeLogic.next(TimeLogic.parseRule("2020-01-01 08:00")!,after:d("2026-10-09 09:00"),lat:nil,lon:nil,calendar:cal)==nil,true,"once past")
        for s in ["", "banana", "every", "every 10s", "25:00", "sunrise*3", "monthly 40 9:00"] { eq(TimeLogic.parseRule(s)==nil,true,"rule bad '\(s)'") }
        eq(TimeLogic.parseRule("every hour") != nil,true,"every hour")
        // solar: NYC 40.7128,-74.0060 on 2026-10-09: sunrise ~07:03, sunset ~18:26 EDT (NOAA)
        let rise=TimeLogic.solarEvent(rise:true,on:d("2026-10-09 12:00"),lat:40.7128,lon:-74.0060,calendar:cal), set=TimeLogic.solarEvent(rise:false,on:d("2026-10-09 12:00"),lat:40.7128,lon:-74.0060,calendar:cal)
        print("NYC sunrise",fmt(rise),"sunset",fmt(set))
        func mins(_ x: Date?) -> Int { guard let x=x else {return -1}; let c=cal.dateComponents([.hour,.minute],from:x); return c.hour!*60+c.minute! }
        eq(abs(mins(rise)-(7*60+3))<=4,true,"sunrise ±4"); eq(abs(mins(set)-(18*60+26))<=4,true,"sunset ±4")
        eq(TimeLogic.solarEvent(rise:true,on:d("2026-06-21 12:00"),lat:80,lon:0,calendar:cal)==nil,true,"polar day nil")
        eq(fmt(TimeLogic.next(TimeLogic.parseRule("sunset -30m")!,after:d("2026-10-09 00:00"),lat:40.7128,lon:-74.0060,calendar:cal)).hasPrefix("2026-10-09 17:5"),true,"sunset-30m")
        eq(TimeLogic.next(TimeLogic.parseRule("sunrise")!,after:Date(),lat:nil,lon:nil)==nil,true,"solar no loc")

    }

    func testCalendarRules() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"
        func d(_ s: String) -> Date { f.date(from: s)! }
        func next(_ rule: String, _ after: String) -> String {
            guard let r = TimeLogic.parseRule(rule), let n = TimeLogic.next(r, after: d(after), lat: nil, lon: nil, calendar: cal) else { return "nil" }
            return f.string(from: n)
        }
        // 2026-10-09 is a Friday
        XCTAssertEqual(next("monthly last 17:00", "2026-10-09 09:00"), "2026-10-31 17:00")
        XCTAssertEqual(next("monthly last 17:00", "2026-10-31 18:00"), "2026-11-30 17:00")
        XCTAssertEqual(next("monthly last 9:00", "2027-02-01 00:00"), "2027-02-28 09:00")
        XCTAssertEqual(next("monthly 2nd tue 9:00", "2026-10-09 09:00"), "2026-10-13 09:00")
        XCTAssertEqual(next("monthly 2nd tue 9:00", "2026-10-13 09:00"), "2026-11-10 09:00")
        XCTAssertEqual(next("monthly last fri 17:00", "2026-10-09 09:00"), "2026-10-30 17:00")
        XCTAssertEqual(next("monthly 1st mon 8am", "2026-10-09 09:00"), "2026-11-02 08:00")
        XCTAssertEqual(next("yearly 12-25 9:00", "2026-10-09 09:00"), "2026-12-25 09:00")
        XCTAssertEqual(next("yearly 12-25 9:00", "2026-12-25 09:00"), "2027-12-25 09:00")
        XCTAssertEqual(next("yearly 2-29 9:00", "2026-10-09 09:00"), "2028-02-29 09:00")
        XCTAssertEqual(next("dates 2026-12-25 08:00; 2026-11-01 9:30", "2026-10-09 09:00"), "2026-11-01 09:30")
        XCTAssertEqual(next("dates 2026-12-25 08:00; 2026-11-01 9:30", "2026-11-01 09:30"), "2026-12-25 08:00")
        XCTAssertEqual(next("dates 2026-12-25 08:00", "2027-01-01 00:00"), "nil")
        // every 2 weeks counted from Monday 2026-10-12
        XCTAssertEqual(next("every 2 weeks from 2026-10-12 9:00", "2026-10-09 09:00"), "2026-10-12 09:00")
        XCTAssertEqual(next("every 2 weeks from 2026-10-12 9:00", "2026-10-12 09:00"), "2026-10-26 09:00")
        XCTAssertEqual(next("every 2 weeks from 2026-10-12 9:00", "2026-11-20 09:00"), "2026-11-23 09:00")
        XCTAssertEqual(next("every 3 days from 2026-10-09 7am", "2026-10-09 07:00"), "2026-10-12 07:00")
        // existing grammar still wins for intervals
        XCTAssertEqual(next("every 30 min", "2026-10-09 09:10"), "2026-10-09 09:30")
        for bad in ["monthly 5th tue 9:00", "yearly 13-1 9:00", "yearly 2-30 9:00x", "dates", "dates nonsense", "every 0 days 9:00", "every 2 weeks from 2026-13-45 9:00"] {
            XCTAssertNil(TimeLogic.parseRule(bad), "should reject \(bad)")
        }
    }
}
