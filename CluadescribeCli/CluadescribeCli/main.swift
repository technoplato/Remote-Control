import Foundation
import Speech
import AVFoundation
import Starscream

// MARK: - Constants
let CLAUDE_WS_URL = "ws://localhost:3000"

// MARK: - Global Logging Control
var isLoggingEnabled = true

func log(_ message: String) {
    if isLoggingEnabled {
        print(message)
    }
}

// MARK: - Claude Message Types
struct CLAUDE_MESSAGE_TYPES {
    /**
     * Sent when Claude starts or stops generating a response
     * Triggered by: Claude beginning to type or finishing a response
     */
    static let CLAUDE_STATE_CHANGE = "CLAUDE.STATE_CHANGE"
    
    /**
     * Sent when a part of Claude's response is received
     * Triggered by: Claude generating part of a response
     */
    static let CLAUDE_RESPONSE_PART_RECEIVED = "CLAUDE.RESPONSE_PART_RECEIVED"
    
    /**
     * Sent when a complete message from Claude is received
     * Triggered by: Claude finishing a complete response
     */
    static let CLAUDE_RESPONSE_COMPLETE = "CLAUDE.RESPONSE_COMPLETE"
    
    /**
     * Sent when a user message is to be sent to Claude
     * Triggered by: User submitting a message in the UI
     */
    static let CLAUDE_SEND_USER_MESSAGE = "CLAUDE.SEND_USER_MESSAGE"
    
    /**
     * Sent when setting the current input in the Claude interface
     * Triggered by: Real-time speech transcription updates
     */
    static let CLAUDE_SET_CURRENT_INPUT = "CLAUDE.SET_CURRENT_INPUT"
    
    /**
     * Sent when submitting the current input to Claude
     * Triggered by: User finalizing their input (e.g., after speech recognition is complete)
     */
    static let CLAUDE_SUBMIT_CURRENT_INPUT = "CLAUDE.SUBMIT_CURRENT_INPUT"
}

class WebSocketManager {
    static let shared = WebSocketManager()
    private var sockets: [String: WebSocket] = [:]
    
    private init() {}
    
    func createSocket(identifier: String, url: String) {
        let request = URLRequest(url: URL(string: url)!)
        let socket = WebSocket(request: request)
        socket.delegate = self
        sockets[identifier] = socket
        socket.connect()
    }
    
    func sendMessage(to identifier: String, message: String) {
        if let socket = sockets[identifier] {
            socket.write(string: message)
        } else {
            log("Socket with identifier \(identifier) not found")
        }
    }
}

extension WebSocketManager: WebSocketDelegate {
    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        switch event {
        case .connected(let headers):
            log("WebSocket connected: \(headers)")
        case .text(let string):
            log("Received text: \(string)")
        case .disconnected(let reason, let code):
            log("WebSocket disconnected: \(reason) with code: \(code)")
        case .error(let error):
            log("WebSocket error: \(error?.localizedDescription ?? "Unknown error")")
        default:
            break
        }
    }
    
}

class SpeechRecognizer: NSObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var currentTranscription: String = ""
    private var lastCompletedSection: String = ""
    private var completedSectionCount: Int = 0
    
    override init() {
        super.init()
        speechRecognizer.delegate = self
        setupWebSocket()
    }
    
    private func setupWebSocket() {
        log("Setting up WebSocket connection to \(CLAUDE_WS_URL)")
        WebSocketManager.shared.createSocket(identifier: "speechRecognizer", url: CLAUDE_WS_URL)
    }
    
    func startRecording() throws {
        log("Starting recording process")
        if let recognitionTask = self.recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        let inputNode = audioEngine.inputNode
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object")
        }
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                log("Transcription received: \(transcription)")
                
                self.processCurrentTranscriptionSection(transcription)
                
                // Debug: Split transcription by "zap" and print relevant section
                let sections = transcription.components(separatedBy: "zap")
                if self.completedSectionCount < sections.count {
                    log("Current section (debug): \(sections[self.completedSectionCount])")
                }
                
                isFinal = result.isFinal
            }
            
            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // Send any remaining transcription
                if !self.currentTranscription.isEmpty {
                    self.sendTranscriptionToClaude(self.currentTranscription)
                    self.currentTranscription = ""
                }
                
                // Restart recording after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    do {
                        try self.startRecording()
                    } catch {
                        log("Failed to restart recording: \(error)")
                    }
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        log("Recording started successfully")
    }
    
    private func processCurrentTranscriptionSection(_ fullTranscription: String) {
        log("Processing transcription: \(fullTranscription)")
        
        let currentTranscriptionSection: String
        if lastCompletedSection.isEmpty {
            currentTranscriptionSection = fullTranscription
        } else {
            if let range = fullTranscription.range(of: lastCompletedSection) {
                currentTranscriptionSection = String(fullTranscription[range.upperBound...])
            } else {
                log("Error: Cannot find last completed section in full transcription")
                return
            }
        }
        
        log("Current transcription section: \(currentTranscriptionSection)")
        
        // TODO configurable hotwords
        if currentTranscriptionSection.lowercased().contains("zap") {
            let components = currentTranscriptionSection.components(separatedBy: "zap")
            if !components.isEmpty {
                let completedSection = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !completedSection.isEmpty {
                    log("Sending completed section: \(completedSection)")
                    sendTranscriptionToClaude(completedSection)
                    lastCompletedSection = fullTranscription.components(separatedBy: "zap")[0...completedSectionCount].joined(separator: "zap") + "zap"
                    completedSectionCount += 1
                    currentTranscription = components.dropFirst().joined(separator: "zap").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } else {
            currentTranscription = currentTranscriptionSection.trimmingCharacters(in: .whitespacesAndNewlines)
            setInputInClaude(currentTranscription)
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        log("Recording stopped")
    }
    
    func setInputInClaude(_ transcription: String) {
        log("Setting input in Claude: \(transcription)")
        let message = ["type": CLAUDE_MESSAGE_TYPES.CLAUDE_SET_CURRENT_INPUT, "content": transcription]
        sendToWebSocket(message)
    }
    
    func submitInputToClaude() {
        log("Submitting input to Claude")
        let message = ["type": CLAUDE_MESSAGE_TYPES.CLAUDE_SUBMIT_CURRENT_INPUT]
        sendToWebSocket(message)
    }
    
    func sendToWebSocket(_ message: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                log("Sending message to WebSocket: \(jsonString)")
                WebSocketManager.shared.sendMessage(to: "speechRecognizer", message: jsonString)
            }
        } catch {
            log("Error serializing JSON: \(error.localizedDescription)")
        }
    }
    
    func sendTranscriptionToClaude(_ transcription: String) {
        setInputInClaude(transcription)
        submitInputToClaude()
    }
    
    // MARK: - SFSpeechRecognizerDelegate
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            log("Speech recognition became available")
        } else {
            log("Speech recognition became unavailable")
        }
    }
}

// Main execution
let speechRecognizer = SpeechRecognizer()

do {
    try speechRecognizer.startRecording()
    log("Entering run loop")
    RunLoop.main.run()
} catch {
    log("An error occurred while starting the recording: \(error.localizedDescription)")
}
