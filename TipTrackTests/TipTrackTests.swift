//
//  TipTrackTests.swift
//  TipTrackTests
//
//  Created by Adam Moore on 8/17/26.
//

import Testing
import UIKit
@testable import TipTrack

struct TipTrackTests {

    @Test func parsesPosiTouchCheckoutFields() {
        let lines = [
            "PAYOUTS SUMMARY",
            "TIPS PAID TO SRVRS: VISA 267.69",
            "TOTAL PAYOUTS: 267.69",
            "MEMO: TIP ALLOC",
            "TIP POOL (5%) Bar 9.89",
            "TOTAL CASH TO REMIT -257.80",
            "TIPS FROM SRVR CHKS 267.69",
            "GRATUITIES 217.69",
            "Sales: 1088.47",
            "Chg tip: 267.69",
            "CASHOUT TOTALS ZEROED"
        ]

        let result = ReceiptParser.parse(lines: lines, image: UIImage(), reportType: .automatic)

        #expect(result.credit == 267.69)
        #expect(result.tipOut == 9.89)
    }

    @Test func prioritizesPosiTouchChargedTipField() {
        let lines = [
            "TIPS FROM SRVR CHKS 300.00",
            "Chg tip: 267.69",
            "TIP POOL (5%) Bar",
            "9.89",
            "CASHOUT TOTALS ZEROED"
        ]

        let result = ReceiptParser.parse(lines: lines, image: UIImage(), reportType: .positouch)

        #expect(result.credit == 267.69)
        #expect(result.tipOut == 9.89)
    }
}
