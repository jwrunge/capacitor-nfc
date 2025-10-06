import Foundation
import CoreNFC
#if canImport(Security)
import Security
#endif

@objc public class NFCReader: NSObject, NFCTagReaderSessionDelegate, NFCNDEFReaderSessionDelegate {
    private var readerSession: NFCTagReaderSession?
    private var ndefReaderSession: NFCNDEFReaderSession?
    private var hasTagEntitlement: Bool? // nil = unknown/not checked
    private var entitlementChecked = false

    public var onNDEFMessageReceived: (([NFCNDEFMessage], [String: Any]?) -> Void)?
    public var onError: ((Error) -> Void)?

    @objc public func startScanning() {
        print("NFCReader startScanning called")

    logNFCFormatsIfAvailable()

        guard NFCNDEFReaderSession.readingAvailable else {
            print("NFC scanning not supported on this device")
            return
        }
        // Perform entitlement pre-check once and cache result
        if !entitlementChecked {
            hasTagEntitlement = checkTagEntitlement()
            entitlementChecked = true
            if let value = hasTagEntitlement {
                print("[NFC] Pre-check TAG entitlement result: \(value)")
            }
        }

        if hasTagEntitlement == false {
            print("[NFC] Skipping NFCTagReaderSession due to missing TAG entitlement; starting fallback immediately")
            startFallbackNDEFSession()
            return
        }

        readerSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: nil)
        readerSession?.alertMessage = "Hold your iPhone near the NFC tag."
        readerSession?.begin()
    }

    private func logNFCFormatsIfAvailable() {
        #if NFC_DEBUG_ENTITLEMENTS && canImport(Security) && os(iOS)
        guard let task = SecTaskCreateFromSelf(nil) else { print("[NFC DEBUG] Cannot create SecTask"); return }
        let key = "com.apple.developer.nfc.readersession.formats" as CFString
        guard let raw = SecTaskCopyValueForEntitlement(task, key, nil) else { print("[NFC DEBUG] formats entitlement ABSENT"); return }
        if let formats = raw as? [String] {
            print("[NFC DEBUG] formats entitlement at runtime = \(formats)")
            if !formats.contains("TAG") { print("[NFC DEBUG] 'TAG' missing -> NFCTagReaderSession will fail") }
            if !formats.contains("NDEF") { print("[NFC DEBUG] 'NDEF' missing -> NDEF read/write limited") }
        } else { print("[NFC DEBUG] formats entitlement unexpected type: \(raw)") }
        #endif
    }

    private func checkTagEntitlement() -> Bool? {
        #if canImport(Security) && os(iOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        let key = "com.apple.developer.nfc.readersession.formats" as CFString
        guard let raw = SecTaskCopyValueForEntitlement(task, key, nil) else { return nil }
        if let formats = raw as? [String] {
            return formats.contains("TAG")
        }
        return nil
        #else
        return nil
        #endif
    }

    @objc public func cancelScanning() {
        if let session = readerSession { session.invalidate() }
        if let ndef = ndefReaderSession { ndef.invalidate() }
        readerSession = nil
        ndefReaderSession = nil
    }

    // NFCTagReaderSessionDelegate methods
    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {

    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print("NFC reader session error: \(error.localizedDescription)")
        // Automatic fallback: if missing entitlement, attempt NDEF-only session once
        if let nfcError = error as? NFCReaderError,
           nfcError.localizedDescription.contains("Missing required entitlement"),
           readerSession != nil { // ensure this is our initial session
            print("[NFC] Attempting fallback to NFCNDEFReaderSession")
            readerSession = nil
            startFallbackNDEFSession()
            return
        }
        onError?(error)
    }

    private func startFallbackNDEFSession() {
        guard NFCNDEFReaderSession.readingAvailable else { return }
        // Avoid multiple fallback sessions
        if ndefReaderSession != nil { return }
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = "Hold your iPhone near the NFC tag. (NDEF mode)"
        ndefReaderSession = session
        session.begin()
    }

    // MARK: - NFCNDEFReaderSessionDelegate
    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        print("NDEF reader session error: \(error.localizedDescription)")
        if (session === ndefReaderSession) { ndefReaderSession = nil }
        onError?(error)
    }

    // Called when the NFCNDEFReaderSession becomes active (needed to silence runtime delegate warning)
    public func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        let isFallback = (session === ndefReaderSession)
        print("NDEF reader session became active (fallback mode: \(isFallback))")
        if isFallback {
            // Emit an empty message set with a fallback flag so JS layer can distinguish mode immediately.
            onNDEFMessageReceived?([], ["fallback": true])
        }
    }

    public func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        // Mirror writer logic for reading first NDEF tag
        if tags.count > 1 {
            let retryInterval = DispatchTimeInterval.milliseconds(500)
            session.alertMessage = "More than one tag detected. Please try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval) {
                session.restartPolling()
            }
            return
        }
        guard let tag = tags.first else { return }
        session.connect(to: tag) { connectError in
            if let connectError = connectError {
                session.invalidate(errorMessage: "Unable to connect to tag.")
                self.onError?(connectError)
                return
            }
            tag.queryNDEFStatus { status, _, statusError in
                if let statusError = statusError {
                    session.invalidate(errorMessage: "Unable to query the NDEF status of tag.")
                    self.onError?(statusError)
                    return
                }
                guard status != .notSupported else {
                    session.invalidate(errorMessage: "Tag is not NDEF compliant.")
                    return
                }
                tag.readNDEF { message, readError in
                    if let readError = readError {
                        session.invalidate(errorMessage: "Failed to read NDEF message.")
                        self.onError?(readError)
                        return
                    }
                    if let message = message {
                        session.alertMessage = "Found 1 NDEF message."
                        session.invalidate()
                        self.onNDEFMessageReceived?([message], nil)
                    } else {
                        session.alertMessage = "No NDEF message found."
                        session.invalidate()
                        self.onNDEFMessageReceived?([], nil)
                    }
                }
            }
        }
    }

    // Some SDK versions (and build settings) still require this legacy delegate method.
    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Forward directly; no tag info available in this callback.
        if !messages.isEmpty {
            session.invalidate()
            onNDEFMessageReceived?(messages, nil)
        }
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

        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found.")
            return
        }
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
