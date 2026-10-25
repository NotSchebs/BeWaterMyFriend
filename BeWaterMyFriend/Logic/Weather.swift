import CoreLocation
import Foundation

/// Today's maximum temperature from Open-Meteo (free, no key, no account).
/// https://open-meteo.com/en/docs
/// Only a rounded location (2 decimals ≈ 1 km) is sent.
nonisolated enum OpenMeteo {
    static func url(latitude: Double, longitude: Double) -> URL? {
        let lat = (latitude * 100).rounded() / 100
        let lon = (longitude * 100).rounded() / 100
        return URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
                   + "&daily=temperature_2m_max&timezone=auto&forecast_days=1")
    }

    /// Today's maximum in °C, or nil if the response doesn't contain it.
    static func parseMaxTemperature(_ data: Data) -> Double? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = root["daily"] as? [String: Any],
              let values = daily["temperature_2m_max"] as? [Any],
              let first = values.first as? NSNumber
        else { return nil }
        return first.doubleValue
    }
}

/// Gets one approximate location (with permission) and today's maximum temperature.
@MainActor
final class WeatherService: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        [.denied, .restricted].contains(manager.authorizationStatus)
    }

    /// Today's maximum temperature in °C, or nil (no permission, offline, …).
    func todaysMaxTemperature() async -> Double? {
        guard let location = await currentLocation(),
              let url = OpenMeteo.url(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return OpenMeteo.parseMaxTemperature(data)
    }

    private func currentLocation() async -> CLLocation? {
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -3 * 3600 {
            return recent
        }
        guard continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            default: finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .notDetermined: break
            default: self.finish(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
