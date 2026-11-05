import UIKit
import Flutter
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge, .criticalAlert]
    ) { _, _ in }

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.jose.recordatorios/native_alerts",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "updateConfig",
           let args = call.arguments as? [String: Any] {
          let enabled = args["autoReminderEnabled"] as? Bool ?? true
          let intervalMin = args["intervalMinutes"] as? Int ?? 45
          let promiseText = args["promiseText"] as? String ?? "Dios cumplirá Su propósito en mi vida."
          UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
          if enabled {
            let content = UNMutableNotificationContent()
            content.title = "Recordatorios • Recuerda Tu Promesa"
            content.body = "“\(promiseText)”"
            content.sound = .defaultCritical
            if #available(iOS 15.0, *) {
              content.interruptionLevel = .timeSensitive
            }
            let trigger = UNTimeIntervalNotificationTrigger(
              timeInterval: TimeInterval(max(60, intervalMin * 60)),
              repeats: true
            )
            let req = UNNotificationRequest(
              identifier: "recordatorios_auto_ios",
              content: content,
              trigger: trigger
            )
            UNUserNotificationCenter.current().add(req)
          }
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
