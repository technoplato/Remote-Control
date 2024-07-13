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

class SpeechRecognizer: NSObject, SFSpeechRecognizerDelegate, WebSocketDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var socket: WebSocket?
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
        var request = URLRequest(url: URL(string: CLAUDE_WS_URL)!)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
        log("WebSocket connection attempt initiated")
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
                
//                // Check for "logging" to toggle logging
                // Not working and I'm not going to futs about
//                if transcription.lowercased().contains("logging") {
//                    isLoggingEnabled.toggle()
//                    log("Logging " + (isLoggingEnabled ? "enabled" : "disabled"))
//                }
                
                self.processCurrentTranscriptionSection(transcription)
                
                // Debug: Split transcription by "jinx" and print relevant section
                let sections = transcription.components(separatedBy: "jinx")
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
        if currentTranscriptionSection.lowercased().contains("jinx") {
            let components = currentTranscriptionSection.components(separatedBy: "jinx")
            if !components.isEmpty {
                let completedSection = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !completedSection.isEmpty {
                    log("Sending completed section: \(completedSection)")
                    sendTranscriptionToClaude(completedSection)
                    lastCompletedSection = fullTranscription.components(separatedBy: "jinx")[0...completedSectionCount].joined(separator: "jinx") + "jinx"
                    completedSectionCount += 1
                    currentTranscription = components.dropFirst().joined(separator: "jinx").trimmingCharacters(in: .whitespacesAndNewlines)
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
        let message = ["type": "set_input", "content": transcription]
        sendToWebSocket(message)
    }
    
    func submitInputToClaude() {
        log("Submitting input to Claude")
        let message = ["type": "submit_input"]
        sendToWebSocket(message)
    }
    
    func sendToWebSocket(_ message: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                log("Sending message to WebSocket: \(jsonString)")
                socket?.write(string: jsonString)
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
    
    // MARK: - WebSocketDelegate
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            log("WebSocket connected with headers: \(headers)")
        case .disconnected(let reason, let code):
            log("WebSocket disconnected with reason: \(reason), code: \(code)")
        case .text(let string):
            log("Received text from WebSocket: \(string)")
        case .binary(let data):
            log("Received binary data from WebSocket: \(data.count) bytes")
        case .ping(_):
            log("Received ping")
        case .pong(_):
            log("Received pong")
        case .viabilityChanged(let isViable):
            log("WebSocket viability changed: \(isViable)")
        case .reconnectSuggested(let isSuggested):
            log("WebSocket reconnect suggested: \(isSuggested)")
        case .cancelled:
            log("WebSocket cancelled")
        case .error(let error):
            log("WebSocket error: \(error?.localizedDescription ?? "Unknown error")")
        case .peerClosed:
            log("WebSocket peer closed")
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
