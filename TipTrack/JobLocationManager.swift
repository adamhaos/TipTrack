import CoreLocation
import Observation

@MainActor @Observable
final class JobLocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = JobLocationManager()
    private let manager = CLLocationManager()
    var location: CLLocation?
    var message: String?
    var requesting = false
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func request() {
        requesting = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default:
            message = "Allow location access in iOS Settings to select nearby jobs."
            requesting = false
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if requesting { request() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        requesting = false
        message = nil
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        requesting = false
        message = "Location is unavailable. Day and schedule rules can still select a job."
    }
    func suggestedJob(jobs: [Job], date: Date) -> Job? {
        if Calendar.current.isDateInToday(date), let location,
           abs(location.timestamp.timeIntervalSinceNow) < 300, location.horizontalAccuracy >= 0 {
            let nearby = jobs.filter { job in
                guard let lat = job.latitude, let lon = job.longitude else { return false }
                let distance = location.distance(from: CLLocation(latitude: lat, longitude: lon))
                let effectiveRadius = max(job.locationRadius, location.horizontalAccuracy)
                return distance <= effectiveRadius
            }
            if nearby.count == 1 { return nearby.first }
        }
        let scheduled = ScheduleStore.shared.events.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }
        let scheduledJobs = Set(scheduled.map(\.jobID))
        if scheduledJobs.count == 1, let id = scheduledJobs.first,
           let job = jobs.first(where: { $0.id == id }) { return job }
        let weekday = String(Calendar.current.component(.weekday, from: date))
        let matching = jobs.filter { $0.selectionDays.split(separator: ",").map(String.init).contains(weekday) }
        if matching.count == 1 { return matching.first }
        return jobs.first(where: \.isDefault) ?? jobs.first
    }
}
