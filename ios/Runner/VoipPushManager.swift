// ios/Runner/VoipPushManager.swift

import Foundation
import PushKit
import Flutter

final class VoipPushManager: NSObject, PKPushRegistryDelegate {

  static let shared = VoipPushManager()
  private override init() {}

  private var channel: FlutterMethodChannel?
  private var registry: PKPushRegistry? // keep strong reference

  // If PushKit gives token before Flutter channel is ready
  private var pendingVoipToken: String?

  // Optional: store last payload
  private var lastIncomingPayload: [String: Any] = [:]

  // MARK: - Flutter channel wiring

  func setChannel(_ channel: FlutterMethodChannel) {
    self.channel = channel
    print("[VoIP] Flutter channel set")

    // ✅ Wire CallKit -> Flutter through the same channel (robust event handling)
    // NOTE: This requires CallKitManager.shared.setEventSink to exist.
    CallKitManager.shared.setEventSink { [weak self] event in
      guard let self = self else { return }
      guard let ch = self.channel else { return }

      let payload: [String: Any]

      // If CallKitManager already sends a dictionary, forward as-is
      if let dict = event as? [String: Any] {
        payload = dict
      } else if let s = event as? String {
        payload = ["type": "callkit", "value": s]
      } else if let n = event as? NSNumber {
        payload = ["type": "callkit", "value": n]
      } else if let b = event as? Bool {
        payload = ["type": "callkit", "value": b]
      } else {
        // Fallback for unexpected types
        payload = ["type": "callkit", "value": String(describing: event)]
      }

      ch.invokeMethod("callkitEvent", arguments: payload)
    }

    // ✅ Flush token if it arrived early
    if let t = pendingVoipToken {
      pendingVoipToken = nil
      print("[VoIP] flushing pending voip token len=\(t.count)")
      self.channel?.invokeMethod("voipToken", arguments: t)
    }
  }

  // MARK: - Register PushKit

  func register() {
    // Avoid double-registering
    if registry != nil {
      print("[VoIP] register() skipped; PKPushRegistry already exists")
      return
    }

    let r = PKPushRegistry(queue: DispatchQueue.main)
    r.delegate = self
    r.desiredPushTypes = [.voIP]
    self.registry = r
    print("[VoIP] PKPushRegistry registered desiredPushTypes=voIP")
  }

  // MARK: - Token updates

  func pushRegistry(_ registry: PKPushRegistry,
                    didUpdate pushCredentials: PKPushCredentials,
                    for type: PKPushType) {
    guard type == .voIP else {
      print("[VoIP] didUpdate ignored type=\(type.rawValue)")
      return
    }

    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    print("[VoIP] didUpdate credentials type=voip tokenLen=\(token.count)")

    // If Flutter channel not ready yet, cache token
    guard let ch = channel else {
      pendingVoipToken = token
      print("[VoIP] channel not ready; cached voip token")
      return
    }

    // Send token to Flutter -> MUST be persisted to Firestore users/{uid}.voipToken
    ch.invokeMethod("voipToken", arguments: token)
  }

  func pushRegistry(_ registry: PKPushRegistry,
                    didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    print("[VoIP] didInvalidate token type=voip")

    pendingVoipToken = nil
    channel?.invokeMethod("voipToken", arguments: "")
  }

  // MARK: - Incoming VoIP push (iOS 11/12)

  func pushRegistry(_ registry: PKPushRegistry,
                    didReceiveIncomingPushWith payload: PKPushPayload,
                    for type: PKPushType,
                    completion: @escaping () -> Void) {
    handleIncomingPush(payload: payload, type: type, completion: completion)
  }

  // MARK: - Incoming VoIP push (iOS 13+)

  func pushRegistry(_ registry: PKPushRegistry,
                    didReceiveIncomingPushWith payload: PKPushPayload,
                    for type: PKPushType,
                    withCompletionHandler completion: @escaping () -> Void) {
    handleIncomingPush(payload: payload, type: type, completion: completion)
  }

  // MARK: - Shared handler

  private func handleIncomingPush(payload: PKPushPayload,
                                  type: PKPushType,
                                  completion: @escaping () -> Void) {

    guard type == .voIP else {
      print("[VoIP] incoming push ignored type=\(type.rawValue)")
      completion()
      return
    }

    // ✅ Ensure completion is called exactly once
    var didFinish = false
    let finishOnce: () -> Void = {
      guard !didFinish else { return }
      didFinish = true
      completion()
    }

    // ✅ Safety timeout: never block PushKit completion (CallKit must be fast)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      finishOnce()
    }

    let raw = payload.dictionaryPayload
    var dict: [String: Any] = [:]
    for (k, v) in raw {
      dict[String(describing: k)] = v
    }
    self.lastIncomingPayload = dict

    let keys = Array(dict.keys).sorted()
    print("[VoIP] didReceiveIncomingPush keys=\(keys)")

    // ✅ Ensure this push is really a call
    let isCall =
      (dict["type"] as? String)?.lowercased() == "call" ||
      ((dict["callId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)

    if !isCall {
      print("[VoIP] not a call payload; skipping CallKit")
      finishOnce()
      return
    }

    // Optional: notify Flutter (debug only; safe if channel not ready)
    channel?.invokeMethod("voipPushReceived", arguments: [
      "keys": keys,
      "hasCallId": dict["callId"] != nil,
      "hasCallerId": dict["callerId"] != nil
    ])

    // ✅ Report to CallKit ASAP (call exactly once)
    CallKitManager.shared.reportIncomingCall(payload: dict) {
      finishOnce()
    }
  }
}
