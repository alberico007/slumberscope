//
//  WeatherService.swift
//  sleep
//
//

import CoreLocation
import Foundation
import MapKit
import os
import WeatherKit

// MARK: - WakeUpWeather

struct WakeUpWeather {
    let temperature: String        // e.g. "68°F"
    let condition: String          // e.g. "Partly Cloudy"
    let symbolName: String         // SF Symbol name
    let feelsLike: String          // e.g. "Feels like 65°F"
    let humidity: String           // e.g. "72%"
    let cityName: String           // e.g. "San Francisco"
}

// MARK: - WeatherService

@Observable
@MainActor
final class WeatherService: NSObject {

    // MARK: - Observable State

    var weather: WakeUpWeather?
    var isLoading = false
    var error: String?

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    // MARK: - Fetch

    func fetchWakeUpWeather() async {
        isLoading = true
        error = nil

        do {
            let location = try await requestLocation()
            let raw = try await WeatherService.shared.weather(for: location)

            // Reverse geocode for city name
            let geocodeRequest = MKReverseGeocodingRequest(location: location)
            let mapItem = try? await geocodeRequest?.mapItems.first
            let city = mapItem?.address?.shortAddress ?? mapItem?.address?.fullAddress ?? "Your Location"

            let formatter = MeasurementFormatter()
            formatter.unitOptions = .providedUnit
            formatter.numberFormatter.maximumFractionDigits = 0

            let tempF = raw.currentWeather.temperature.converted(to: .fahrenheit)
            let feelsF = raw.currentWeather.apparentTemperature.converted(to: .fahrenheit)
            let humidity = raw.currentWeather.humidity

            let condition = raw.currentWeather.condition.description
            AppLogger.general.info("🌤️ Weather fetched: \(condition)")

            await MainActor.run {
                self.weather = WakeUpWeather(
                    temperature: "\(Int(tempF.value.rounded()))°F",
                    condition: condition,
                    symbolName: raw.currentWeather.symbolName,
                    feelsLike: "Feels like \(Int(feelsF.value.rounded()))°F",
                    humidity: "\(Int((humidity * 100).rounded()))% humidity",
                    cityName: city
                )
                self.isLoading = false
            }
        } catch {
            AppLogger.general.error("Weather fetch failed: \(error.localizedDescription)")
            await MainActor.run {
                self.error = "Weather unavailable"
                self.isLoading = false
            }
        }
    }

    // MARK: - Location

    private func requestLocation() async throws -> CLLocation {
        // If we already have a fresh location, use it
        if let loc = currentLocation, Date().timeIntervalSince(loc.timestamp) < 3600 {
            return loc
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation

            let status = locationManager.authorizationStatus
            if status == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationManager.requestLocation()
            } else {
                continuation.resume(throwing: CLError(.denied))
                self.locationContinuation = nil
            }
        }
    }
}

// MARK: - WeatherService (shared singleton alias for WeatherKit)

private extension WeatherService {
    static let shared = WeatherKit.WeatherService.shared
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.currentLocation = location
            self?.locationContinuation?.resume(returning: location)
            self?.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.locationContinuation?.resume(throwing: error)
            self?.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        nonisolated(unsafe) let mgr = manager
        Task { @MainActor [weak self] in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                mgr.requestLocation()
            } else if status == .denied || status == .restricted {
                self?.locationContinuation?.resume(throwing: CLError(.denied))
                self?.locationContinuation = nil
            }
        }
    }
}

// MARK: - WeatherCondition description

extension WeatherCondition {
    var description: String {
        switch self {
        case .blizzard: return "Blizzard"
        case .blowingDust: return "Blowing Dust"
        case .blowingSnow: return "Blowing Snow"
        case .breezy: return "Breezy"
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .drizzle: return "Drizzle"
        case .flurries: return "Flurries"
        case .foggy: return "Foggy"
        case .freezingDrizzle: return "Freezing Drizzle"
        case .freezingRain: return "Freezing Rain"
        case .frigid: return "Frigid"
        case .hail: return "Hail"
        case .haze: return "Haze"
        case .heavyRain: return "Heavy Rain"
        case .heavySnow: return "Heavy Snow"
        case .hot: return "Hot"
        case .hurricane: return "Hurricane"
        case .isolatedThunderstorms: return "Isolated Thunderstorms"
        case .mostlyClear: return "Mostly Clear"
        case .mostlyCloudy: return "Mostly Cloudy"
        case .partlyCloudy: return "Partly Cloudy"
        case .rain: return "Rain"
        case .scatteredThunderstorms: return "Scattered Thunderstorms"
        case .sleet: return "Sleet"
        case .smoky: return "Smoky"
        case .snow: return "Snow"
        case .strongStorms: return "Strong Storms"
        case .sunFlurries: return "Sun Flurries"
        case .sunShowers: return "Sun Showers"
        case .thunderstorms: return "Thunderstorms"
        case .tropicalStorm: return "Tropical Storm"
        case .windy: return "Windy"
        case .wintryMix: return "Wintry Mix"
        @unknown default: return "Unknown"
        }
    }
}
