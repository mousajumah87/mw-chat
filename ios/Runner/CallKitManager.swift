//ios/Runner/CallKitManager.swift

import Foundation
import CallKit
import AVFoundation
import CryptoKit

final class CallKitManager: NSObject, CXProviderDelegate {
  static let shared = CallKitManager()

  private let provider: CXProvider
  private let callController = CXCallController()

  // Event sink -> VoipPushManager -> Flutter
  private var eventSink: (([String: Any]) -> Void)?

  // Track the last call UUID so you can end it later if needed
  private var lastUUID: UUID?

  // ------------------------------
  // Persisted mapping: uuid <-> callId
  // (So Answer/End can send callId back to Flutter)
  // ------------------------------
  private let callIdKeyPrefix = "mw_callkit_callid_"

  private func storeCallId(_ callId: String, for uuid: UUID) {
    let key = callIdKeyPrefix + uuid.uuidString
    UserDefaults.standard.set(callId, forKey: key)
    UserDefaults.standard.synchronize()
  }

  private func lookupCallId(for uuid: UUID) -> String {
    let key = callIdKeyPrefix + uuid.uuidString
    let v = UserDefaults.standard.string(forKey: key) ?? ""
    return v.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func clearCallId(for uuid: UUID) {
    let key = callIdKeyPrefix + uuid.uuidString
    UserDefaults.standard.removeObject(forKey: key)
    UserDefaults.standard.synchronize()
  }

  private override init() {
    let config = CXProviderConfiguration(localizedName: "MW")
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.generic]
    config.includesCallsInRecents = false

    // Optional: if you have an icon
    // config.iconTemplateImageData = UIImage(named: "CallKitIcon")?.pngData()

    self.provider = CXProvider(configuration: config)
    super.init()
    self.provider.setDelegate(self, queue: nil)
  }

  func setEventSink(_ sink: @escaping ([String: Any]) -> Void) {
    self.eventSink = sink
  }

  // Create stable UUID from callId (Firestore doc id)
  private func stableUUID(from callId: String) -> UUID {
    let data = Data(callId.utf8)
    let digest = SHA256.hash(data: data)
    let bytes = Array(digest)

    let uuidBytes = (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5],
      bytes[6], bytes[7],
      bytes[8], bytes[9],
      bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    )
    return UUID(uuid: uuidBytes)
  }

  /// payload should include callId/callerId/callType
  func reportIncomingCall(payload: [String: Any], completion: @escaping () -> Void) {
    let callId = (payload["callId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? UUID().uuidString

    let callerIdRaw = (payload["callerId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? "Unknown"

    let callType = ((payload["callType"] as? String) ?? (payload["type"] as? String) ?? "audio")
      .lowercased()
    let hasVideo = (callType == "video")

    let uuid = stableUUID(from: callId)
    self.lastUUID = uuid

    // ✅ Persist mapping so Answer/End can send callId back to Flutter
    storeCallId(callId, for: uuid)

    let update = CXCallUpdate()
    update.hasVideo = hasVideo

    // Avoid showing internal IDs (UIDs) to user.
    // If callerId looks like a UID, show privacy-safe label.
    let displayHandle: String
    if callerIdRaw.count > 20 { // typical Firebase UID length
      displayHandle = "MW Caller"
    } else {
      displayHandle = callerIdRaw.isEmpty ? "MW Caller" : callerIdRaw
    }

    update.remoteHandle = CXHandle(type: .generic, value: displayHandle)
    update.localizedCallerName = "MW"

    print("[CallKit] reportNewIncomingCall callId=\(callId) uuid=\(uuid.uuidString) hasVideo=\(hasVideo)")

    provider.reportNewIncomingCall(with: uuid, update: update) { error in
      if let error = error {
        print("[CallKit] reportNewIncomingCall ERROR: \(error)")
        // If it fails, cleanup mapping
        self.clearCallId(for: uuid)
      } else {
        print("[CallKit] reportNewIncomingCall OK")
      }
      completion()
    }
  }

  // Allow Flutter to end call by UUID
  func endCall(uuidString: String) {
    guard let uuid = UUID(uuidString: uuidString) else { return }
    let endAction = CXEndCallAction(call: uuid)
    let tx = CXTransaction(action: endAction)
    callController.request(tx) { error in
      if let error = error {
        print("[CallKit] endCall ERROR: \(error)")
      } else {
        print("[CallKit] endCall OK uuid=\(uuidString)")
      }
      // Optional: clear mapping when Flutter ends call
      self.clearCallId(for: uuid)
    }
  }

  // MARK: - CXProviderDelegate

  func providerDidReset(_ provider: CXProvider) {
    print("[CallKit] providerDidReset")
    // Best effort cleanup for last UUID
    if let uuid = lastUUID {
      clearCallId(for: uuid)
    }
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    let uuidStr = action.callUUID.uuidString
    let callId = lookupCallId(for: action.callUUID)

    print("[CallKit] ANSWER uuid=\(uuidStr) callId=\(callId)")

    eventSink?([
      "event": "answer",
      "uuid": uuidStr,
      "callId": callId
    ])

    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let uuidStr = action.callUUID.uuidString
    let callId = lookupCallId(for: action.callUUID)

    print("[CallKit] END uuid=\(uuidStr) callId=\(callId)")

    eventSink?([
      "event": "end",
      "uuid": uuidStr,
      "callId": callId
    ])

    // ✅ clear mapping once call ended
    clearCallId(for: action.callUUID)

    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    print("[CallKit] didActivate audioSession")

    // Make WebRTC/Voice audio reliable
    do {
      try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
      try audioSession.setActive(true)
    } catch {
      print("[CallKit] audioSession setup ERROR: \(error)")
    }

    eventSink?([
      "event": "audioActivated"
    ])
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    print("[CallKit] didDeactivate audioSession")
    eventSink?([
      "event": "audioDeactivated"
    ])
  }
}
