import Flutter
import UIKit
import Intents

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let liveActivityChannelName = "nyit_events/live_activities"
  private let siriShortcutsChannelName = "nyit_events/siri_shortcuts"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let liveActivityChannel = FlutterMethodChannel(
        name: liveActivityChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      liveActivityChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "startOrUpdate":
          result(true)
        case "end":
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let siriChannel = FlutterMethodChannel(
        name: siriShortcutsChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      siriChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "donateOpenEvent":
          self.donateActivity(activityType: "edu.nyit.campusevents.openEvent")
          result(true)
        case "donateShowQr":
          self.donateActivity(activityType: "edu.nyit.campusevents.showCheckinQr")
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func donateActivity(activityType: String) {
    let activity = NSUserActivity(activityType: activityType)
    activity.isEligibleForSearch = true
    activity.isEligibleForPrediction = true
    activity.persistentIdentifier = NSUserActivityPersistentIdentifier(activityType)
    activity.suggestedInvocationPhrase = "Open NYIT Events"
    if let controller = window?.rootViewController {
      controller.userActivity = activity
    }
    activity.becomeCurrent()
  }
}
