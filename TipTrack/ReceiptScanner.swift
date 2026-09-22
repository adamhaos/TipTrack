import PhotosUI
import SwiftUI
import UIKit
import Vision

struct ReceiptScanResult {
    let image: UIImage
    var credit: Double?
    var cash: Double?
    var tipOut: Double?
    var hours: Double?
}

enum ShiftReportType: String, CaseIterable, Identifiable {
    case automatic = "Auto Detect"
    case positouch = "PosiTouch"
    case toast = "Toast"
    case square = "Square"
    case clover = "Clover"
    case generic = "Other / Generic"

    var id: String { rawValue }
}

enum ReceiptStore {
    static func save(_ image: UIImage, shiftID: UUID) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        let name = "\(shiftID.uuidString).jpg"
        let folder = URL.documentsDirectory.appendingPathComponent("Receipts", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            return name
        } catch { return nil }
    }

    static func image(named name: String?) -> UIImage? {
        guard let url = fileURL(named: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func remove(named name: String?) {
        guard let url = fileURL(named: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func fileURL(named name: String?) -> URL? {
        guard let name, !name.isEmpty, name != ".", name != "..",
              name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        return URL.documentsDirectory.appendingPathComponent("Receipts", isDirectory: true)
            .appendingPathComponent(name)
    }
}

struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    var onCancel: (() -> Void)? = nil
    let onUse: (ReceiptScanResult) -> Void
    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var result: ReceiptScanResult?
    @State private var isShowingCamera = false
    @State private var scanning = false
    @State private var scanID = UUID()
    @State private var reportType = ShiftReportType.automatic
    @State private var message = "Take a clear photo of the checkout slip or choose one from Photos."

    init(embedded: Bool = false, onCancel: (() -> Void)? = nil,
         preferredReportType: ShiftReportType = .automatic,
         onUse: @escaping (ReceiptScanResult) -> Void) {
        self.embedded = embedded
        self.onCancel = onCancel
        self.onUse = onUse
        _reportType = State(initialValue: preferredReportType)
    }

    var body: some View {
        if embedded {
            embeddedContent
                .sheet(isPresented: $isShowingCamera) {
                    CameraImagePicker { selected in image = selected; scan(selected) }
                }
                .onChange(of: selectedItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let selected = UIImage(data: data) {
                            image = selected
                            scan(selected)
                        }
                    }
                }
                .onChange(of: reportType) { _, _ in
                    if let image { scan(image) }
                }
        } else {
            standaloneContent
        }
    }

    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { onCancel?() } label: {
                    Label("Close", systemImage: "xmark")
                }
                Spacer()
                Text("Checkout Slip").font(.headline)
            }
            Picker("Shift Report Type", selection: $reportType) {
                ForEach(ShiftReportType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Choose a Checkout Slip", systemImage: "doc.viewfinder")
                        .font(.headline)
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            HStack {
                Button { isShowingCamera = true } label: {
                    Label("Camera", systemImage: "camera.fill")
                }
                Spacer()
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
            }
            .buttonStyle(.bordered)
            if scanning { ProgressView("Reading checkout slip…") }
            if let result {
                Text("Recognized Draft").font(.headline)
                recognizedRow("Credit Tips", result.credit)
                recognizedRow("Cash Tips", result.cash)
                recognizedRow("Tip Out", result.tipOut)
            }
            Text("Reads credit tips, Toast amounts owed to you as cash tips, and tip-out. Review the amounts in your shift before saving. The photo is attached when you save the shift.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                if let result { onUse(result) }
            } label: {
                Text("Use Draft & Attach Slip").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(result == nil || scanning)
        }
        .padding(.top, 6)
    }

    private var standaloneContent: some View {
        NavigationStack {
            Form {
                Section("Shift Report Type") {
                    Picker("Format", selection: $reportType) {
                        ForEach(ShiftReportType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ContentUnavailableView("No Receipt Selected", systemImage: "doc.viewfinder",
                            description: Text(message))
                    }
                    HStack {
                        Button { isShowingCamera = true } label: { Label("Camera", systemImage: "camera.fill") }
                        Spacer()
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Label("Photos", systemImage: "photo.on.rectangle")
                        }
                    }
                }
                if scanning { Section { ProgressView("Reading receipt…") } }
                if let result {
                    Section("Recognized Draft") {
                        recognizedRow("Credit Tips", result.credit)
                        recognizedRow("Cash Tips", result.cash)
                        recognizedRow("Tip Out", result.tipOut)
                    }
                }
                Section {
                    Text("TipTrack reads card tips, Toast amounts owed to you as cash tips, and tip-out. Always review the amounts before saving; receipt layouts vary, and the scan is never saved automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scan Checkout Slip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Draft") { if let result { onUse(result); dismiss() } }.disabled(result == nil || scanning)
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker { selected in image = selected; scan(selected) }
            }
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let selected = UIImage(data: data) {
                        image = selected
                        scan(selected)
                    }
                }
            }
            .onChange(of: reportType) { _, _ in
                if let image { scan(image) }
            }
        }
    }

    private func recognizedRow(_ title: String, _ value: Double?, currency: Bool = true) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let value {
                Text(currency ? value.formatted(.currency(code: "USD")) : value.formatted(.number.precision(.fractionLength(0...2))))
                    .bold().monospacedDigit()
            } else { Text("Not found").foregroundStyle(.secondary) }
        }
    }

    private func scan(_ selected: UIImage) {
        guard let cgImage = selected.cgImage else { return }
        let currentScanID = UUID()
        scanID = currentScanID
        let selectedReportType = reportType
        scanning = true
        result = nil
        let orientation = CGImagePropertyOrientation(selected.imageOrientation)
        Task {
            let lines = await Task.detached {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                try? handler.perform([request])
                return ReceiptTextRecognizer.reconstructedLines(from: request.results ?? [])
            }.value
            guard scanID == currentScanID else { return }
            result = ReceiptParser.parse(lines: lines, image: selected, reportType: selectedReportType)
            scanning = false
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

private enum ReceiptTextRecognizer {
    private struct TextFragment {
        let text: String
        let bounds: CGRect
    }

    private struct TextRow {
        var verticalCenter: CGFloat
        var height: CGFloat
        var fragments: [TextFragment]
    }

    nonisolated static func reconstructedLines(
        from observations: [VNRecognizedTextObservation]
    ) -> [String] {
        let verticalObservationCount = observations.reduce(into: 0) { count, observation in
            if observation.boundingBox.height > observation.boundingBox.width {
                count += 1
            }
        }
        let effectiveOrientation: CGImagePropertyOrientation =
            verticalObservationCount > observations.count / 2 ? .right : .up

        let fragments = observations.compactMap { observation -> TextFragment? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return TextFragment(
                text: text,
                bounds: orientedBounds(observation.boundingBox, orientation: effectiveOrientation)
            )
        }
        .sorted {
            if abs($0.bounds.midY - $1.bounds.midY) > 0.01 {
                return $0.bounds.midY > $1.bounds.midY
            }
            return $0.bounds.minX < $1.bounds.minX
        }

        var rows: [TextRow] = []
        for fragment in fragments {
            let matchingIndex = rows.indices.min { first, second in
                abs(rows[first].verticalCenter - fragment.bounds.midY)
                    < abs(rows[second].verticalCenter - fragment.bounds.midY)
            }

            if let matchingIndex {
                let row = rows[matchingIndex]
                let tolerance = max(row.height, fragment.bounds.height) * 0.65
                if abs(row.verticalCenter - fragment.bounds.midY) <= tolerance {
                    rows[matchingIndex].fragments.append(fragment)
                    let count = CGFloat(rows[matchingIndex].fragments.count)
                    rows[matchingIndex].verticalCenter =
                        ((row.verticalCenter * (count - 1)) + fragment.bounds.midY) / count
                    rows[matchingIndex].height = max(row.height, fragment.bounds.height)
                    continue
                }
            }

            rows.append(
                TextRow(
                    verticalCenter: fragment.bounds.midY,
                    height: fragment.bounds.height,
                    fragments: [fragment]
                )
            )
        }

        return rows
            .sorted { $0.verticalCenter > $1.verticalCenter }
            .map { row in
                row.fragments
                    .sorted { $0.bounds.minX < $1.bounds.minX }
                    .map(\.text)
                    .joined(separator: " ")
            }
    }

    private nonisolated static func orientedBounds(
        _ bounds: CGRect,
        orientation: CGImagePropertyOrientation
    ) -> CGRect {
        switch orientation {
        case .up, .upMirrored:
            return bounds
        case .down, .downMirrored:
            return CGRect(
                x: 1 - bounds.maxX,
                y: 1 - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
        case .right, .rightMirrored:
            return CGRect(
                x: bounds.minY,
                y: 1 - bounds.maxX,
                width: bounds.height,
                height: bounds.width
            )
        case .left, .leftMirrored:
            return CGRect(
                x: 1 - bounds.maxY,
                y: bounds.minX,
                width: bounds.height,
                height: bounds.width
            )
        }
    }
}

enum ReceiptParser {
    static func parse(lines: [String], image: UIImage, reportType: ShiftReportType) -> ReceiptScanResult {
        var output = ReceiptScanResult(image: image)
        let detectedType = reportType == .automatic ? detectType(in: lines) : reportType
        output.credit = value(for: creditLabels(for: detectedType), in: lines)
        output.tipOut = value(for: tipOutLabels(for: detectedType), in: lines)
        if detectedType == .toast {
            output.cash = owedToAmount(in: lines)
        }
        return output
    }

    private static func detectType(in lines: [String]) -> ShiftReportType {
        let text = lines.joined(separator: " ").lowercased()
        if text.contains("cashout totals zeroed")
            || text.contains("tips from srvr chks")
            || (text.contains("tip alloc") && text.contains("chg tip")) {
            return .positouch
        }
        if text.contains("toast") || text.range(of: #"\bowed\s+to\s+"#, options: .regularExpression) != nil {
            return .toast
        }
        if text.contains("square") || text.contains("team sales") { return .square }
        if text.contains("clover") || text.contains("employee report") { return .clover }
        return .generic
    }

    private static func creditLabels(for type: ShiftReportType) -> [String] {
        let checkoutSlipLabels = [
            "chg tip",
            "chg tips",
            "charge tip",
            "charged tip",
            "tips from srvr chks",
            "tips from server chks",
            "tips from server checks"
        ]
        switch type {
        case .positouch:
            return checkoutSlipLabels
        case .toast:
            return ["non-cash tips", "credit card tips", "credit tips", "card tips"] + checkoutSlipLabels
        case .square:
            return ["card tips", "credit card tips", "credit tips"] + checkoutSlipLabels
        case .clover:
            return ["credit card tips", "card tips", "charged tips"] + checkoutSlipLabels
        case .automatic, .generic:
            return checkoutSlipLabels + [
                "non-cash tips",
                "credit card tips",
                "credit tips",
                "card tips",
                "charged tips"
            ]
        }
    }

    private static func tipOutLabels(for type: ShiftReportType) -> [String] {
        let checkoutSlipLabels = ["tip pool", "bar tip", "tip alloc"]
        switch type {
        case .positouch:
            return checkoutSlipLabels
        case .toast:
            return [
                "house tip share",
                "tips withheld",
                "tip share",
                "tip out",
                "tipout"
            ] + checkoutSlipLabels
        case .square:
            return ["tip distribution", "tips distributed", "tip out"] + checkoutSlipLabels
        case .clover:
            return ["tip adjustment", "tips owed", "tip out"] + checkoutSlipLabels
        case .automatic, .generic:
            return checkoutSlipLabels + [
                "house tip share",
                "tips withheld",
                "tip share",
                "tip out",
                "tipout",
                "tip distribution",
                "tips distributed",
                "tip adjustment",
                "tips owed"
            ]
        }
    }

    private static func owedToAmount(in lines: [String]) -> Double? {
        // Only read the amount after the named payout label, never sales or tips earned.
        guard let label = try? NSRegularExpression(
            pattern: #"\bowed\s+to\s+[^:$\r\n]+(?=:|\$)"#, options: .caseInsensitive),
              let amount = try? NSRegularExpression(
                pattern: #"^\s*:?\s*\$?\s*-?\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?"#) else { return nil }
        for (index, line) in lines.enumerated() {
            guard let match = label.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let labelRange = Range(match.range, in: line) else { continue }
            let suffix = String(line[labelRange.upperBound...])
            if let match = amount.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)),
               let range = Range(match.range, in: suffix),
               let value = lastMonetaryNumber(in: String(suffix[range])) {
                return value
            }
            // OCR may put the payout on its own line; accept only a bare amount.
            let remainder = suffix.replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.isEmpty, lines.indices.contains(index + 1), isNumberOnly(lines[index + 1]) {
                return lastMonetaryNumber(in: lines[index + 1])
            }
        }
        return nil
    }

    private static func value(for labels: [String], in lines: [String]) -> Double? {
        // Label order is significant. Reports can repeat similar totals, so prefer
        // the system-specific field before falling back to its aliases.
        for label in labels {
            for (index, line) in lines.enumerated() {
                let normalizedLine = line.lowercased()
                guard normalizedLine.contains(label) else { continue }

                if let value = lastMonetaryNumber(in: line) {
                    return value
                }

                guard lines.indices.contains(index + 1) else { continue }
                let nextLine = lines[index + 1]
                let normalizedNextLine = nextLine.lowercased()
                let isRelatedContinuation = normalizedNextLine.contains("bar")
                    || normalizedNextLine.contains("tip")
                    || isNumberOnly(nextLine)
                if isRelatedContinuation, let value = lastMonetaryNumber(in: nextLine) {
                    return value
                }
            }
        }
        return nil
    }

    private static func isNumberOnly(_ text: String) -> Bool {
        let stripped = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(stripped) != nil
    }

    private static func lastMonetaryNumber(in text: String) -> Double? {
        let pattern = #"-?\$?\s*([0-9][0-9,]*(?:[\.,][0-9]{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: text),
                  let valueRange = Range(match.range(at: 1), in: text) else {
                continue
            }

            let suffix = text[fullRange.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !suffix.hasPrefix("%") else { continue }

            let rawNumber = String(text[valueRange])
            let number: String
            if !rawNumber.contains("."),
               let commaIndex = rawNumber.lastIndex(of: ","),
               rawNumber.distance(from: rawNumber.index(after: commaIndex), to: rawNumber.endIndex) <= 2 {
                let whole = rawNumber[..<commaIndex].replacingOccurrences(of: ",", with: "")
                let fraction = rawNumber[rawNumber.index(after: commaIndex)...]
                number = "\(whole).\(fraction)"
            } else {
                number = rawNumber.replacingOccurrences(of: ",", with: "")
            }

            if let value = Double(number) {
                return abs(value)
            }
        }
        return nil
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker
        init(parent: CameraImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
