// swiftlint:disable all  — dense table-driven cases ported from the plugins' scratch tests
import XCTest


final class TimeLogicTests: XCTestCase {
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
}
