import Foundation
@main struct BluetoothActionCheck {
 static func main() throws {
  let hardware = FeatureHardware()
  var replied = false
  hardware.setConnected(id: "not-a-paired-device", connected: true) { data in
   let result = try! JSONDecoder().decode(FeatureDeviceActionResult.self, from: data)
   precondition(result.error != nil, "Unknown device must be rejected")
   replied = true
  }
  precondition(replied, "Invalid device should reply immediately")
  print("Passed: unpaired device rejected without connection attempt")
 }
}
