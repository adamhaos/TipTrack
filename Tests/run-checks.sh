#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
check_dir=$(mktemp -d /tmp/TipTrack-checks.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -module-cache-path "$check_dir/cache" \
    TipTrack/TipTrackSiriRules.swift Tests/SiriRulesChecks.swift -o "$check_dir/siri"
"$check_dir/siri"
xcrun swiftc -module-cache-path "$check_dir/cache" \
    TipTrack/Models.swift TipTrack/TipTrackCSV.swift TipTrack/CalendarFeed.swift \
    TipTrack/TipTrackSiriRules.swift Tests/ReleaseChecks.swift -o "$check_dir/release"
"$check_dir/release"
# Compile the exact production parser without the camera/SwiftUI interface.
python3 - "$check_dir/ReceiptParser.swift" <<'PY'
from pathlib import Path
import sys
source = Path('TipTrack/ReceiptScanner.swift').read_text()
types = source[source.index('struct ReceiptScanResult {'):source.index('enum ReceiptStore {')]
parser = source[source.index('enum ReceiptParser {'):source.index('private struct CameraImagePicker:')]
Path(sys.argv[1]).write_text('import Foundation\n' + types + parser)
PY
xcrun swiftc -module-cache-path "$check_dir/cache" \
    "$check_dir/ReceiptParser.swift" Tests/ReceiptParserChecks.swift -o "$check_dir/receipt"
"$check_dir/receipt"
xcrun swiftc -module-cache-path "$check_dir/cache" \
    TipTrack/CalendarNavigation.swift TipTrack/DashboardCardID.swift Tests/NavigationChecks.swift \
    -o "$check_dir/navigation"
"$check_dir/navigation"
xcrun swiftc -module-cache-path "$check_dir/cache" \
    TipTrack/EarningsInsights.swift Tests/EarningsInsightsChecks.swift -o "$check_dir/insights"
"$check_dir/insights"
