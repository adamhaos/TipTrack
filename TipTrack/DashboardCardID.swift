import Foundation

enum DashboardCardID: String, Identifiable, CaseIterable {
    case greeting, calendar, monthly, weekly, liveActivity, logShift
    case spacer1, spacer2, spacer3, spacer4

    var id: String { rawValue }

    static func ordered(from storedOrder: String) -> [DashboardCardID] {
        let keys = storedOrder.split(separator: ",").map(String.init)
        var list: [DashboardCardID] = []
        for key in keys {
            if let card = DashboardCardID(rawValue: key), !list.contains(card) {
                list.append(card)
            }
        }
        for card in DashboardCardID.allCases {
            if !list.contains(card) { list.append(card) }
        }
        if storedOrder.isEmpty {
            list = [.calendar, .liveActivity, .greeting, .monthly, .spacer3, .weekly, .spacer1, .logShift, .spacer2, .spacer4]
        }
        return list
    }
}
