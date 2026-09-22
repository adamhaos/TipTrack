import Foundation

// The parser carries its image unchanged; these checks need no camera or UIKit.
struct UIImage { }

@main
struct ReceiptParserChecks {
    static func main() {
        let checkout = ReceiptParser.parse(lines: [
            "PAYOUTS SUMMARY", "TIPS PAID TO SRVRS: VISA 267.69", "TOTAL PAYOUTS: 267.69",
            "MEMO: TIP ALLOC", "TIP POOL (5%) Bar 9.89", "TOTAL CASH TO REMIT -257.80",
            "TIPS FROM SRVR CHKS 267.69", "GRATUITIES 217.69", "Sales: 1088.47",
            "Chg tip: 267.69", "CASHOUT TOTALS ZEROED"
        ], image: UIImage(), reportType: .automatic)
        precondition(checkout.credit == 267.69 && checkout.tipOut == 9.89)
        let continuation = ReceiptParser.parse(lines: [
            "TIPS FROM SRVR CHKS 300.00", "Chg tip: 267.69", "TIP POOL (5%) Bar", "9.89"
        ], image: UIImage(), reportType: .positouch)
        precondition(continuation.credit == 267.69 && continuation.tipOut == 9.89)
        let decimal = ReceiptParser.parse(lines: ["Credit card tips 267,69", "Tip out 9,89"],
            image: UIImage(), reportType: .toast)
        precondition(decimal.credit == 267.69 && decimal.tipOut == 9.89)
        let toastOwed = ReceiptParser.parse(lines: [
            "Toast", "Total tips earned: $350.00", "Cash tips: $75.00",
            "OWED TO ADAM: $250.00", "House tip share: $20.00"
        ], image: UIImage(), reportType: .automatic)
        precondition(toastOwed.cash == 250 && toastOwed.tipOut == 20)
        let namedPayout = ReceiptParser.parse(lines: ["owed to Jamie 2: $1,234.56 Other total $999.00"],
            image: UIImage(), reportType: .toast)
        precondition(namedPayout.cash == 1234.56)
        let payoutContinuation = ReceiptParser.parse(lines: ["OWED TO ADAM:", "$98.76"],
            image: UIImage(), reportType: .automatic)
        precondition(payoutContinuation.cash == 98.76)
        let zeroPayout = ReceiptParser.parse(lines: ["OWED TO ADAM: $0.00"],
            image: UIImage(), reportType: .toast)
        precondition(zeroPayout.cash == 0)
        let missingPayout = ReceiptParser.parse(lines: ["Toast", "Cash tips $100.00", "OWED TO ADAM:", "Sales $900.00"],
            image: UIImage(), reportType: .automatic)
        precondition(missingPayout.cash == nil)
        // A job preference selects the report rules even when OCR misses the POS branding.
        let unbrandedReport = ["Chg tip $10.00", "Credit card tips $125.00", "Tip pool $20.00", "House tip share $15.00"]
        let explicitToast = ReceiptParser.parse(lines: unbrandedReport, image: UIImage(), reportType: .toast)
        let automaticReport = ReceiptParser.parse(lines: unbrandedReport, image: UIImage(), reportType: .automatic)
        precondition(explicitToast.credit == 125 && explicitToast.tipOut == 15)
        precondition(automaticReport.credit == 10 && automaticReport.tipOut == 20)
        let missing = ReceiptParser.parse(lines: ["Sales 1000.00", "Tip Pool (5%) Bar"],
            image: UIImage(), reportType: .generic)
        precondition(missing.credit == nil && missing.tipOut == nil)
        print("Receipt parser checks passed: checkout fields, preferred labels, continuation lines, decimal commas, and missing values.")
    }
}
