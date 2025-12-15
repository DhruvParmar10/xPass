import Cocoa
import FlutterMacOS
import CoreWLAN
import CoreLocation

class WiFiLocationManager: NSObject, CLLocationManagerDelegate {
  static let shared = WiFiLocationManager()
  private let locationManager = CLLocationManager()
  private var permissionCallback: ((Bool) -> Void)?
  
  override init() {
    super.init()
    locationManager.delegate = self
  }
  
  private func getAuthorizationStatus() -> CLAuthorizationStatus {
    if #available(macOS 11.0, *) {
      return locationManager.authorizationStatus
    } else {
      return CLLocationManager.authorizationStatus()
    }
  }
  
  func requestPermission(completion: @escaping (Bool) -> Void) {
    permissionCallback = completion
    
    // Check current authorization status
    let status = getAuthorizationStatus()
    
    switch status {
    case .authorizedAlways, .authorized:
      completion(true)
    case .denied, .restricted:
      completion(false)
    case .notDetermined:
      // Request permission - this triggers the system prompt
      if #available(macOS 10.15, *) {
        locationManager.requestWhenInUseAuthorization()
      } else {
        // Older macOS - just try to start location updates to trigger prompt
        locationManager.startUpdatingLocation()
        locationManager.stopUpdatingLocation()
        completion(false)
      }
    @unknown default:
      completion(false)
    }
  }
  
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = getAuthorizationStatus()
    let granted = status == .authorizedAlways || status == .authorized
    permissionCallback?(granted)
    permissionCallback = nil
  }
  
  // Legacy delegate method for older macOS
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    let granted = status == .authorizedAlways || status == .authorized
    permissionCallback?(granted)
    permissionCallback = nil
  }
  
  func getWifiSSID() -> String? {
    // First check if we have location permission
    let status = getAuthorizationStatus()
    guard status == .authorizedAlways || status == .authorized else {
      return nil
    }
    
    // Now get SSID using CoreWLAN
    if let wifiClient = CWWiFiClient.shared().interface(),
       let ssid = wifiClient.ssid() {
      return ssid
    }
    return nil
  }
  
  func checkPermissionStatus() -> String {
    let status = getAuthorizationStatus()
    switch status {
    case .authorizedAlways, .authorized:
      return "granted"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    // Register WiFi SSID method channel
    let channel = FlutterMethodChannel(
      name: "com.xpass/wifi",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "getWifiSSID":
        let ssid = WiFiLocationManager.shared.getWifiSSID()
        result(ssid)
        
      case "requestLocationPermission":
        WiFiLocationManager.shared.requestPermission { granted in
          DispatchQueue.main.async {
            result(granted)
          }
        }
        
      case "checkLocationPermission":
        let status = WiFiLocationManager.shared.checkPermissionStatus()
        result(status)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
