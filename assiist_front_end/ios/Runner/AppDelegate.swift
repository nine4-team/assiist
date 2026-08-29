import Flutter
import UIKit
import Contacts
import ContactsUI
import SwiftUI

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let contactChannel = FlutterMethodChannel(name: "assiist.contact_access",
                                            binaryMessenger: controller.binaryMessenger)
    
    contactChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      switch call.method {
      case "checkContactAccess":
        self.checkContactAccess(result: result)
      case "requestFullContactAccess":
        self.requestFullContactAccess(result: result)
      case "requestInitialContactAccess":
        self.requestInitialContactAccess(result: result)
      case "presentContactAccessPicker":
        self.presentContactAccessPicker(result: result)
      case "openContactSettings":
        self.openContactSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func checkContactAccess(result: @escaping FlutterResult) {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    
    switch status {
    case .notDetermined:
      result("notDetermined")
    case .restricted:
      result("restricted")
    case .denied:
      result("denied")
    case .authorized:
      result("authorized")
    case .limited:
      if #available(iOS 18.0, *) {
        result("limited")
      } else {
        result("authorized") // Fallback for older iOS
      }
    @unknown default:
      result("unknown")
    }
  }
  
  // iOS 18 specific method for requesting initial contact access
  private func requestInitialContactAccess(result: @escaping FlutterResult) {
    let store = CNContactStore()
    
    // Check current status first
    let currentStatus = CNContactStore.authorizationStatus(for: .contacts)
    print("Current contact status: \(currentStatus.rawValue)")
    
    if currentStatus == .authorized {
      result("authorized")
      return
    }
    
    if currentStatus == .limited {
      result("limited")
      return
    }
    
    if currentStatus == .denied || currentStatus == .restricted {
      result("denied")
      return
    }
    
    // For notDetermined, request access - this should trigger iOS 18 two-stage flow
    print("Requesting initial contact access...")
    
    // Ensure we're on the main thread for UI operations
    DispatchQueue.main.async {
      store.requestAccess(for: .contacts) { (granted, error) in
        print("Initial request completed. Granted: \(granted), Error: \(String(describing: error))")
        
        DispatchQueue.main.async {
          if let error = error {
            print("Error during initial request: \(error)")
            result(FlutterError(code: "CONTACT_ERROR", message: error.localizedDescription, details: nil))
          } else {
            // Check the actual status after request
            let status = CNContactStore.authorizationStatus(for: .contacts)
            print("Status after initial request: \(status.rawValue)")
            
            switch status {
            case .authorized:
              result("authorized")
            case .limited:
              result("limited")
            case .denied:
              result("denied")
            default:
              result("unknown")
            }
          }
        }
      }
    }
  }
  
  // Method for requesting full contact access (legacy and iOS 18)
  private func requestFullContactAccess(result: @escaping FlutterResult) {
    let store = CNContactStore()
    
    // Check current status first
    let currentStatus = CNContactStore.authorizationStatus(for: .contacts)
    print("Current contact status for full access request: \(currentStatus.rawValue)")
    
    if currentStatus == .authorized {
      result("authorized")
      return
    }
    
    if currentStatus == .denied || currentStatus == .restricted {
      result("denied")
      return
    }
    
    // For iOS 18+, requesting access again when we have limited access should show upgrade dialog
    print("Requesting full contact access (this should show upgrade dialog on iOS 18)...")
    
    DispatchQueue.main.async {
      store.requestAccess(for: .contacts) { (granted, error) in
        print("Full access request completed. Granted: \(granted), Error: \(String(describing: error))")
        
        DispatchQueue.main.async {
          if let error = error {
            print("Error during full access request: \(error)")
            result(FlutterError(code: "CONTACT_ERROR", message: error.localizedDescription, details: nil))
          } else {
            // Check the actual status after request
            let status = CNContactStore.authorizationStatus(for: .contacts)
            print("Final status after full access request: \(status.rawValue)")
            
            switch status {
            case .authorized:
              result("authorized")
            case .limited:
              result("limited")
            case .denied:
              result("denied")
            default:
              result("unknown")
            }
          }
        }
      }
    }
  }
  
  // iOS 18 specific method for presenting contact access picker
  @available(iOS 18.0, *)
  private func presentContactAccessPicker(result: @escaping FlutterResult) {
    guard let controller = window?.rootViewController else {
      result(FlutterError(code: "NO_CONTROLLER", message: "No view controller available", details: nil))
      return
    }
    
    // For iOS 18, when we have limited access, we should request full access again
    // This should trigger the system dialog asking "Allow Full Access" vs "Keep Current Selection"
    let store = CNContactStore()
    
    print("Presenting iOS 18 contact access upgrade dialog...")
    
    DispatchQueue.main.async {
      // Request access again - this should show the upgrade dialog on iOS 18
      store.requestAccess(for: .contacts) { (granted, error) in
        print("Contact access upgrade request completed. Granted: \(granted), Error: \(String(describing: error))")
        
        DispatchQueue.main.async {
          if let error = error {
            print("Error during contact access upgrade: \(error)")
            result(FlutterError(code: "CONTACT_ERROR", message: error.localizedDescription, details: nil))
          } else {
            // Check the final authorization status
            let status = CNContactStore.authorizationStatus(for: .contacts)
            print("Final status after upgrade request: \(status.rawValue)")
            
            switch status {
            case .authorized:
              result("authorized")
            case .limited:
              result("limited")
            case .denied:
              result("denied")
            default:
              result("unknown")
            }
          }
        }
      }
    }
  }
  
  private func openContactSettings(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
        if UIApplication.shared.canOpenURL(settingsUrl) {
          UIApplication.shared.open(settingsUrl) { success in
            result(success)
          }
        } else {
          result(false)
        }
      } else {
        result(false)
      }
    }
  }

  @objc private func dismissContactAccess() {
    let controller = window?.rootViewController as! FlutterViewController
    controller.dismiss(animated: true)
  }
}

// Legacy contact picker delegate for fallback scenarios
class ContactPickerDelegate: NSObject, CNContactPickerDelegate {
  private let result: FlutterResult
  
  init(result: @escaping FlutterResult) {
    self.result = result
  }
  
  func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
    picker.dismiss(animated: true) {
      // Check status after dismissal
      let status = CNContactStore.authorizationStatus(for: .contacts)
      switch status {
      case .authorized:
        self.result("authorized")
      case .limited:
        self.result("limited")
      case .denied:
        self.result("denied")
      default:
        self.result("unknown")
      }
    }
  }
  
  func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
    picker.dismiss(animated: true) {
      // Check status after selection
      let status = CNContactStore.authorizationStatus(for: .contacts)
      switch status {
      case .authorized:
        self.result("authorized")
      case .limited:
        self.result("limited")
      case .denied:
        self.result("denied")
      default:
        self.result("unknown")
      }
    }
  }
}
