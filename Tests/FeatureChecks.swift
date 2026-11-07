import Foundation
@main struct FeatureChecks {
 static func main() throws {
  var count = 0
  func check(_ value: Bool, _ label: String) { precondition(value, label); count += 1 }
  let old = [FeatureDevice(id: "a", name: "Headphones", connected: true)]
  check(FeatureLayout.transitions(old: old, new: old).isEmpty, "no duplicate Bluetooth event")
  let changes = FeatureLayout.transitions(old: old, new: [.init(id: "a", name: "Headphones", connected: false)])
  check(changes.count == 1 && !changes[0].1, "disconnect transition")
  check(FeatureLayout.transitions(old: [], new: old).count == 1, "new connection detected")
  check(FeatureForecast.condition(95).1 == "cloud.bolt.rain.fill", "thunderstorm code")
  check(FeatureForecast.condition(73).0 == "Snow", "snow code")
  let payload = Data(#"{"current":{"temperature_2m":12.3,"apparent_temperature":10.2,"weather_code":3,"wind_speed_10m":4.5,"is_day":0}}"#.utf8)
  check(try JSONDecoder().decode(FeatureForecast.self, from: payload).current.temperature_2m == 12.3, "Open-Meteo current payload")
  check(FeaturePlace.krasnodar.name == "Краснодар", "default city")
  print("Passed \(count) feature checks")
 }
}
