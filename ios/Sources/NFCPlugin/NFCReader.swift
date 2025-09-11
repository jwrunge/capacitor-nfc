import Foundation
import CoreNFC

@objc public class NFCReader: NSObject, NFCNDEFReaderSessionDelegate {
    private var readerSession: NFCNDEFReaderSession?

    public var onNDEFMessageReceived: (([NFCNDEFMessage]) -> Void)?
    public var onError: ((Error) -> Void)?

    @objc public func startScanning() {
        print("NFCReader startScanning called")

        guard NFCNDEFReaderSession.readingAvailable else {
            print("NFC scanning not supported on this device")
            return
        }
        readerSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        readerSession?.alertMessage = "Hold your iPhone near the NFC tag."
        readerSession?.begin()
    }

    // NFCNDEFReaderSessionDelegate methods for reading
    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        print("NFC reader session error: \(error.localizedDescription)")
        onError?(error)
    }

    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        onNDEFMessageReceived?(messages)
    }

    public func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        
    }

    // Handle detection of NDEF tags (need to connect and read the NDEF message)
    public func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        if tags.count > 1 {
            // Restart polling in 500ms
            let retryInterval = DispatchTimeInterval.milliseconds(500)
            session.alertMessage = "More than one tag detected. Please remove extra tags and try again."
            DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval) {
                session.restartPolling()
            }
            return
        }
        
        // Connect to the found tag and perform NDEF message reading
        let tag = tags.first!
        session.connect(to: tag) { (error: Error?) in
            if let error = error {
                session.invalidate(errorMessage: "Unable to connect to tag.")
                self.onError?(error)
                return
            }
            
            tag.queryNDEFStatus { (ndefStatus: NFCNDEFStatus, capacity: Int, error: Error?) in
                if let error = error {
                    session.invalidate(errorMessage: "Unable to query NDEF status of tag.")
                    self.onError?(error)
                    return
                }
                
                if ndefStatus == .notSupported {
                    session.invalidate(errorMessage: "Tag is not NDEF compliant.")
                    return
                }
                
                tag.readNDEF { (message: NFCNDEFMessage?, error: Error?) in
                    var statusMessage: String
                    if let error = error {
                        statusMessage = "Failed to read NDEF from tag."
                        session.invalidate(errorMessage: statusMessage)
                        self.onError?(error)
                        return
                    }
                    
                    if let message = message {
                        print("NDEF message read: \(message)")
                        statusMessage = "Found 1 NDEF message."
                        session.alertMessage = statusMessage
                        session.invalidate()
                        self.onNDEFMessageReceived?([message])
                    } else {
                        statusMessage = "No NDEF message found."
                        session.invalidate(errorMessage: statusMessage)
                    }
                }
            }
        }
    }
}
