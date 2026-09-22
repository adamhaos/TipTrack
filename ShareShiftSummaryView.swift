import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

private enum ShiftShareField: String, CaseIterable, Identifiable {
    case creditTips, cashTips, tipOut, netCash, creditAndBase, basePay, baseRate, hours, hourly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creditTips: "Credit Tips"
        case .cashTips: "Cash Tips"
        case .tipOut: "Tip Out"
        case .netCash: "Net Cash"
        case .creditAndBase: "Credit + Base Pay"
        case .basePay: "Base Pay"
        case .baseRate: "Base Hourly Rate"
        case .hours: "Hours Worked"
        case .hourly: "Hourly Earnings"
        }
    }

    func value(for shift: Shift) -> String? {
        switch self {
        case .creditTips: shift.creditTip.formatted(.currency(code: "USD"))
        case .cashTips: shift.cashTip.formatted(.currency(code: "USD"))
        case .tipOut: shift.barTipOut.formatted(.currency(code: "USD"))
        case .netCash: shift.netCash.formatted(.currency(code: "USD"))
        case .creditAndBase: shift.creditEarnings.formatted(.currency(code: "USD"))
        case .basePay:
            shift.hoursWorked != nil && shift.hourlyRate > 0 ? shift.basePay.formatted(.currency(code: "USD")) : nil
        case .baseRate:
            shift.hourlyRate > 0 ? shift.hourlyRate.formatted(.currency(code: "USD")) + "/hr" : nil
        case .hours:
            shift.hoursWorked.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " hrs" }
        case .hourly:
            shift.hourlyAverage.map { $0.formatted(.currency(code: "USD")) + "/hr" }
        }
    }
}

struct ShareShiftSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let shift: Shift

    @State private var includeWorkplace = true
    @State private var includeDate = true
    @State private var includeTotal = true
    @State private var fields: Set<ShiftShareField> = Set(ShiftShareField.allCases)
    @State private var includeDownload = true
    @State private var sharePayload: ShiftSummarySharePayload?
    @State private var renderError = false

    init(shift: Shift) {
        self.shift = shift
        _includeWorkplace = State(initialValue: shift.job != nil)
        _fields = State(initialValue: Set(ShiftShareField.allCases.filter { $0.value(for: shift) != nil }))
    }

    private static let downloadURL = URL(string: "https://apps.apple.com/us/app/tiptrack3r/id6809030435")!

    private var card: ShareableShiftCard {
        ShareableShiftCard(
            workplace: includeWorkplace ? shift.job?.name : nil,
            workplaceIcon: shift.job?.iconSymbolName ?? "briefcase",
            date: includeDate ? shift.date : nil,
            totalEarnings: includeTotal ? shift.totalEarnings : nil,
            metrics: ShiftShareField.allCases.compactMap { field in
                guard fields.contains(field), let value = field.value(for: shift) else { return nil }
                return ShiftShareMetric(id: field.rawValue, title: field.title, value: value)
            },
            downloadURL: includeDownload ? Self.downloadURL : nil
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(action: renderAndShare) {
                        Label("Create & Share Image", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }

                Section("Preview") {
                    GeometryReader { geometry in
                        card
                            .frame(width: 600, height: card.imageHeight)
                            .scaleEffect(geometry.size.width / 600, anchor: .topLeading)
                    }
                    .aspectRatio(600 / card.imageHeight, contentMode: .fit)
                    .accessibilityElement(children: .combine)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    Toggle("Workplace Name", isOn: $includeWorkplace)
                        .disabled(shift.job == nil)
                    Toggle("Shift Date", isOn: $includeDate)
                    Toggle("Total Earnings", isOn: $includeTotal)
                    ForEach(ShiftShareField.allCases) { field in
                        Toggle(field.title, isOn: Binding(
                            get: { fields.contains(field) },
                            set: { enabled in
                                if enabled { fields.insert(field) } else { fields.remove(field) }
                            }
                        ))
                        .disabled(field.value(for: shift) == nil)
                    }
                } header: {
                    Text("Shift Details")
                } footer: {
                    Text("All available details are included by default. Turn off anything you don’t want to share. Hourly earnings are total earnings divided by hours worked. Add hours or a base hourly rate to your shift to enable those details.")
                }

                Section {
                    Toggle("App Download QR Code", isOn: $includeDownload)
                } header: {
                    Text("Made with TipTrack3r")
                } footer: {
                    Text("Adds a scannable App Store link to the card. The shared attachment is your image; only the app link is encoded in the QR code.")
                }

            }
            .protectEarnings()
            .navigationTitle("Share Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't Create Image", isPresented: $renderError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please try sharing your shift again.")
            }
            .sheet(item: $sharePayload) { payload in
                ShiftSummaryActivityView(items: [payload.image])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @MainActor
    private func renderAndShare() {
        let renderer = ImageRenderer(content: card
            .frame(width: 600, height: card.imageHeight)
            .environment(\.colorScheme, .light))
        renderer.scale = 2
        guard let image = renderer.uiImage else { renderError = true; return }
        // The sheet and its content come from the same state change, including on the first tap.
        sharePayload = ShiftSummarySharePayload(image: image)
    }
}

private struct ShiftSummarySharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ShiftShareMetric: Identifiable {
    let id: String
    let title: String
    let value: String
}

private struct ShareableShiftCard: View {
    let workplace: String?
    var workplaceIcon: String = "briefcase"
    let date: Date?
    let totalEarnings: Double?
    let metrics: [ShiftShareMetric]
    let downloadURL: URL?

    // Keep preview and export at identical proportions, with space for every selected row.
    var imageHeight: CGFloat {
        360 + CGFloat((metrics.count + 1) / 2) * 94
            + (workplace == nil ? 0 : 56) + (date == nil ? 0 : 32)
            + (downloadURL == nil ? 0 : 108)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.23),
                                    Color(red: 0.16, green: 0.20, blue: 0.39)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(Color(red: 0.61, green: 0.83, blue: 0.96))
                    Text("TipTrack3r").tracking(-0.5)
                    Spacer()
                    Text("SHIFT SUMMARY")
                        .font(.system(size: 11, weight: .semibold)).tracking(2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .font(.system(size: 22, weight: .bold))

                VStack(alignment: .leading, spacing: 8) {
                    Text(totalEarnings == nil ? "Another shift in the books." : "TOTAL EARNINGS")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(totalEarnings == nil ? 0 : 2)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(totalEarnings.map { $0.formatted(.currency(code: "USD")) } ?? "Shift complete")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 12)

                if workplace != nil || date != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if let workplace {
                            Label(workplace, systemImage: workplaceIcon)
                                .font(.system(size: 19, weight: .semibold))
                                .lineLimit(2)
                                .frame(height: 48, alignment: .topLeading)
                        }
                        if let date {
                            Label(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()), systemImage: "calendar")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                if !metrics.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(Array(stride(from: 0, to: metrics.count, by: 2)), id: \.self) { index in
                            HStack(spacing: 12) {
                                ShareMetricTile(metric: metrics[index])
                                if index + 1 < metrics.count {
                                    ShareMetricTile(metric: metrics[index + 1])
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
                Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                if let downloadURL, let qrImage = ShareDownloadQR.image(for: downloadURL) {
                    HStack(spacing: 18) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .padding(8)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("QR code to download TipTrack3r from the App Store")
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Make every shift count.")
                                .font(.system(size: 19, weight: .semibold))
                            Text("Scan to get TipTrack3r")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.7))
                            Label("Available on the App Store", systemImage: "apple.logo")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                } else {
                    Text("Tracked with TipTrack3r")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(36)
            .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct ShareMetricTile: View {
    let metric: ShiftShareMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            Text(metric.value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(height: 82)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

private enum ShareDownloadQR {
    static func image(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
                                                     from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct ShiftSummaryActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
