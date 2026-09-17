import Flutter
import UIKit

import FirebaseCore
import GoogleMaps
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure Firebase only when the bundle ships GoogleService-Info.plist
    // (managed in Xcode). Until then the app falls back to SSE + HTTP polling.
    if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
      FirebaseApp.configure()
      if #available(iOS 10.0, *) {
        UNUserNotificationCenter.current().delegate = self
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
          options: authOptions,
          completionHandler: { _, _ in }
        )
      }
      application.registerForRemoteNotifications()
    }
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey:
                                           "com.google.android.geo.API_KEY") as? String,
       !mapsApiKey.isEmpty {
      GMSServices.provideAPIKey(mapsApiKey)
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}