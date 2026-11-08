import Foundation

enum CalendarNavigation {
    static func pageRange(itemCount: Int, page: Int, pageSize: Int) -> Range<Int> {
        let count = max(0, itemCount)
        let size = max(1, pageSize)
        let lastPage = count == 0 ? 0 : (count - 1) / size
        let start = min(lastPage, max(0, page)) * size
        return start..<min(count, start + min(size, count - start))
    }

    static func selectedDay(in month: Date, matching selected: Date, calendar: Calendar) -> Date {
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 1
        let day = min(count, max(1, calendar.component(.day, from: selected)))
        return calendar.date(byAdding: .day, value: day - 1, to: start)
            .map { calendar.startOfDay(for: $0) } ?? start
    }

    enum Swipe: Equatable { case previous, next }

    /// Reads a finished drag as a page swipe: mostly sideways and either long or quick.
    /// Swiping left moves forward in time, like turning a page.
    static func swipe(width: Double, height: Double, predictedWidth: Double) -> Swipe? {
        guard abs(width) > abs(height) * 1.5,
              abs(width) > 50 || abs(predictedWidth) > 140 else { return nil }
        return width < 0 ? .next : .previous
    }
}
