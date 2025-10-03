import Foundation
import CoreNFC
import Security

@objc public class NFCReader: NSObject, NFCTagReaderSessionDelegate {
    private var readerSession: NFCTagReaderSession?

    public var onNDEFMessageReceived: (([NFCNDEFMessage], [String: Any]?) -> Void)?
    public var onError: ((Error) -> Void)?

    @objc public func startScanning() {
        print("NFCReader startScanning called")

        // Debug: Log NFC entitlements actually present at runtime so we can
        // distinguish between code / provisioning issues vs capability setup.
        logNFCEntitlements()

        guard NFCNDEFReaderSession.readingAvailable else {
            print("NFC scanning not supported on this device")
            return
        }
        readerSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: nil)
        readerSession?.alertMessage = "Hold your iPhone near the NFC tag."
        readerSession?.begin()
    }

    // MARK: - Entitlement Debugging
    // Reads the NFC formats entitlement at runtime (if present) and logs it.
    // This helps diagnose the "Missing required entitlement" error by showing
    // whether the final signed app truly contains the expected values.
    private func logNFCEntitlements() {
        if let task = SecTaskCreateFromSelf(nil) {
            if let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.nfc.readersession.formats" as CFString, nil) {
                if let formats = value as? [String] {
                    print("[NFC DEBUG] com.apple.developer.nfc.readersession.formats = \(formats)")
                    if !formats.contains("TAG") {
                        print("[NFC DEBUG] 'TAG' format missing. NFCTagReaderSession will fail. Either add 'TAG' to the entitlement or switch to NFCNDEFReaderSession if you only need NDEF.")
                    }
                } else {
                    print("[NFC DEBUG] NFC formats entitlement present but unexpected type: \(value)")
                }
            } else {
                print("[NFC DEBUG] NFC formats entitlement NOT present on the signed app.")
            }
        } else {
            print("[NFC DEBUG] Could not create SecTask for entitlement inspection.")
        }
    }

    @objc public func cancelScanning() {
        if let session = readerSession {
            session.invalidate()
        }
        readerSession = nil
    }

    // NFCTagReaderSessionDelegate methods
    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print("NFC reader session error: \(error.localizedDescription)")
        onError?(error)
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if tags.count > 1 {
            let retryInterval = DispatchTimeInterval.milliseconds(500)
            session.alertMessage = "More than one tag detected. Please remove extra tags and try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval) {
                session.restartPolling()
            }
            return
        }
        
        let tag = tags.first!
        session.connect(to: tag) { (error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to connect to tag.")
                self.onError?(error)
                return
            }
            
            // Extract tag information
            let tagInfo = self.extractTagInfo(from: tag)
            
            // Try to read NDEF if the tag supports it
            if case let .iso7816(iso7816Tag) = tag {
                self.handleISO7816Tag(iso7816Tag, session: session, tagInfo: tagInfo)
            } else if case let .miFare(miFareTag) = tag {
                self.handleMiFareTag(miFareTag, session: session, tagInfo: tagInfo)
            } else if case let .feliCa(feliCaTag) = tag {
                self.handleFeliCaTag(feliCaTag, session: session, tagInfo: tagInfo)
            } else if case let .iso15693(iso15693Tag) = tag {
                self.handleISO15693Tag(iso15693Tag, session: session, tagInfo: tagInfo)
            } else {
                // Unknown tag type, still return tag info
                session.alertMessage = "Tag detected but no NDEF message found."
                session.invalidate()
                self.onNDEFMessageReceived?([], tagInfo)
            }
        }
    }
    
    private func extractTagInfo(from tag: NFCTag) -> [String: Any] {
        var tagInfo: [String: Any] = [:]
        var techTypes: [String] = []
        var uid: String = ""
        
        switch tag {
        case .iso7816(let iso7816Tag):
            uid = iso7816Tag.identifier.map { String(format: "%02X", $0) }.joined()
            techTypes.append("ISO7816")
            tagInfo["type"] = "ISO7816"
            
        case .miFare(let miFareTag):
            uid = miFareTag.identifier.map { String(format: "%02X", $0) }.joined()
            techTypes.append("MiFare")
            tagInfo["type"] = "MiFare"
            
        case .feliCa(let feliCaTag):
            uid = feliCaTag.currentIDm.map { String(format: "%02X", $0) }.joined()
            techTypes.append("FeliCa")
            tagInfo["type"] = "FeliCa"
            
        case .iso15693(let iso15693Tag):
            uid = iso15693Tag.identifier.map { String(format: "%02X", $0) }.joined()
            techTypes.append("ISO15693")
            tagInfo["type"] = "ISO15693"
            
        @unknown default:
            techTypes.append("Unknown")
            tagInfo["type"] = "Unknown"
        }
        
        tagInfo["uid"] = uid
        tagInfo["techTypes"] = techTypes
        
        return tagInfo
    }
    
    private func handleMiFareTag(_ miFareTag: NFCMiFareTag, session: NFCTagReaderSession, tagInfo: [String: Any]) {
        miFareTag.queryNDEFStatus { (ndefStatus: NFCNDEFStatus, capacity: Int, error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to query NDEF status of tag.")
                self.onError?(error)
                return
            }
            
            if ndefStatus == .notSupported {
                session.alertMessage = "Tag detected but no NDEF message found."
                session.invalidate()
                self.onNDEFMessageReceived?([], tagInfo)
                return
            }
            
            var updatedTagInfo = tagInfo
            updatedTagInfo["maxSize"] = capacity
            updatedTagInfo["isWritable"] = ndefStatus == .readWrite
            
            miFareTag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to read NDEF from tag.")
                    self.onError?(error)
                    return
                }
                
                if let message = message {
                    session.alertMessage = "Found 1 NDEF message."
                    session.invalidate()
                    self.onNDEFMessageReceived?([message], updatedTagInfo)
                } else {
                    session.alertMessage = "Tag detected but no NDEF message found."
                    session.invalidate()
                    self.onNDEFMessageReceived?([], updatedTagInfo)
                }
            }
        }
    }
    
    private func handleISO7816Tag(_ iso7816Tag: NFCISO7816Tag, session: NFCTagReaderSession, tagInfo: [String: Any]) {
        // ISO7816 tags don't typically support NDEF directly
        session.alertMessage = "Tag detected but no NDEF message found."
        session.invalidate()
        self.onNDEFMessageReceived?([], tagInfo)
    }
    
    private func handleFeliCaTag(_ feliCaTag: NFCFeliCaTag, session: NFCTagReaderSession, tagInfo: [String: Any]) {
        feliCaTag.queryNDEFStatus { (ndefStatus: NFCNDEFStatus, capacity: Int, error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to query NDEF status of tag.")
                self.onError?(error)
                return
            }
            
            if ndefStatus == .notSupported {
                session.alertMessage = "Tag detected but no NDEF message found."
                session.invalidate()
                self.onNDEFMessageReceived?([], tagInfo)
                return
            }
            
            var updatedTagInfo = tagInfo
            updatedTagInfo["maxSize"] = capacity
            updatedTagInfo["isWritable"] = ndefStatus == .readWrite
            
            feliCaTag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to read NDEF from tag.")
                    self.onError?(error)
                    return
                }
                
                if let message = message {
                    session.alertMessage = "Found 1 NDEF message."
                    session.invalidate()
                    self.onNDEFMessageReceived?([message], updatedTagInfo)
                } else {
                    session.alertMessage = "Tag detected but no NDEF message found."
                    session.invalidate()
                    self.onNDEFMessageReceived?([], updatedTagInfo)
                }
            }
        }
    }
    
    private func handleISO15693Tag(_ iso15693Tag: NFCISO15693Tag, session: NFCTagReaderSession, tagInfo: [String: Any]) {
        iso15693Tag.queryNDEFStatus { (ndefStatus: NFCNDEFStatus, capacity: Int, error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to query NDEF status of tag.")
                self.onError?(error)
                return
            }
            
            if ndefStatus == .notSupported {
                session.alertMessage = "Tag detected but no NDEF message found."
                session.invalidate()
                self.onNDEFMessageReceived?([], tagInfo)
                return
            }
            
            var updatedTagInfo = tagInfo
            updatedTagInfo["maxSize"] = capacity
            updatedTagInfo["isWritable"] = ndefStatus == .readWrite
            
            iso15693Tag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
                if let error = error {
                    session.invalidate(errorMessage: "Failed to read NDEF from tag.")
                    self.onError?(error)
                    return
                }
                
                if let message = message {
                    session.alertMessage = "Found 1 NDEF message."
                    session.invalidate()
                    self.onNDEFMessageReceived?([message], updatedTagInfo)
                } else {
                    session.alertMessage = "Tag detected but no NDEF message found."
                    session.invalidate()
                    self.onNDEFMessageReceived?([], updatedTagInfo)
                }
            }
        }
    }
}
