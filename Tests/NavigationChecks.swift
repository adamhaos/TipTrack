import Foundation

@main
struct NavigationChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        for (year, expectedDay) in [(2024, 29), (2026, 28)] {
            let selection = CalendarNavigation.selectedDay(in: date(year, 2, 1),
                matching: date(year, 1, 31), calendar: calendar)
            precondition(selection == date(year, 2, expectedDay))
        }
        precondition(CalendarNavigation.selectedDay(in: date(2027, 1, 1),
            matching: date(2026, 12, 31), calendar: calendar) == date(2027, 1, 31))
        // Midnight must stay correct across the spring DST change.
        precondition(CalendarNavigation.selectedDay(in: date(2026, 3, 1),
            matching: date(2026, 2, 9), calendar: calendar) == date(2026, 3, 9))

        for size in [1, 2, 3, 4] {
            var covered: [Int] = []
            for page in 0..<((37 + size - 1) / size) {
                covered.append(contentsOf: CalendarNavigation.pageRange(itemCount: 37, page: page, pageSize: size))
            }
            precondition(covered == Array(0..<37))
        }
        precondition(CalendarNavigation.pageRange(itemCount: 0, page: 10, pageSize: 3).isEmpty)
        precondition(CalendarNavigation.pageRange(itemCount: 1, page: 12, pageSize: 3) == 0..<1)
        precondition(CalendarNavigation.pageRange(itemCount: 37, page: Int.max, pageSize: 3) == 36..<37)
        precondition(CalendarNavigation.pageRange(itemCount: 37, page: -1, pageSize: 3) == 0..<3)

        let order = DashboardCardID.ordered(from: "weekly,weekly,bogus,monthly,weekly")
        precondition(Array(order.prefix(2)) == [.weekly, .monthly])
        precondition(order.count == DashboardCardID.allCases.count)
        precondition(Set(order).count == order.count)
        precondition(DashboardCardID.ordered(from: "").first == .calendar)
        print("Navigation checks passed: month-end selection, leap years, DST, busy-day paging, and duplicate dashboard preferences.")
    }
}
