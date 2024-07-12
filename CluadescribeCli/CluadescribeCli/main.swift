import Foundation
import Speech
import AVFoundation
import Starscream

// MARK: - Constants
let CLAUDE_WS_URL = "ws://localhost:3000"

class SpeechRecognizer: NSObject, SFSpeechRecognizerDelegate, WebSocketDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var socket: WebSocket?
    private var currentTranscription: String = ""
    
    override init() {
        super.init()
        speechRecognizer.delegate = self
        setupWebSocket()
    }
    
    private func setupWebSocket() {
        print("Setting up WebSocket connection to \(CLAUDE_WS_URL)")
        var request = URLRequest(url: URL(string: CLAUDE_WS_URL)!)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
        print("WebSocket connection attempt initiated")
    }
    
    func startRecording() throws {
        print("Starting recording process")
        if let recognitionTask = self.recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
//        let audioSession = AVAudioSession.sharedInstance()
//        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
//        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
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
                print("Transcription received: \(transcription)")
                
                self.processDoneKeyword(in: transcription)
                
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
                        print("Failed to restart recording: \(error)")
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
        
        print("Recording started successfully")
    }
    
    private func processDoneKeyword(in transcription: String) {
        let components = transcription.components(separatedBy: "done")
        
        if components.count > 1 {
            // There's at least one "done" in the transcription
            for (index, component) in components.enumerated() {
                if index == 0 {
                    // First part (before the first "done")
                    let fullTranscription = currentTranscription + component
                    if !fullTranscription.isEmpty {
                        print("Sending transcription before 'done': \(fullTranscription)")
                        sendTranscriptionToClaude(fullTranscription)
                    }
                } else {
                    // Subsequent parts (after each "done")
                    if !component.isEmpty {
                        print("Sending transcription after 'done': \(component)")
                        sendTranscriptionToClaude(component)
                    }
                }
            }
            currentTranscription = ""
        } else {
            // No "done" found, update currentTranscription
            currentTranscription = transcription
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        print("Recording stopped")
    }
    
    func setInputInClaude(_ transcription: String) {
        print("Setting input in Claude: \(transcription)")
        let message = ["type": "set_input", "content": transcription]
        sendToWebSocket(message)
    }
    
    func submitInputToClaude() {
        print("Submitting input to Claude")
        let message = ["type": "submit_input"]
        sendToWebSocket(message)
    }
    
    func sendToWebSocket(_ message: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Sending message to WebSocket: \(jsonString)")
                socket?.write(string: jsonString)
            }
        } catch {
            print("Error serializing JSON: \(error.localizedDescription)")
        }
    }
    
    func sendTranscriptionToClaude(_ transcription: String) {
        setInputInClaude(transcription)
        submitInputToClaude()
    }
    
    // MARK: - SFSpeechRecognizerDelegate
    
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            print("Speech recognition became available")
        } else {
            print("Speech recognition became unavailable")
        }
    }
    
    // MARK: - WebSocketDelegate
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(let headers):
            print("WebSocket connected with headers: \(headers)")
        case .disconnected(let reason, let code):
            print("WebSocket disconnected with reason: \(reason), code: \(code)")
        case .text(let string):
            print("Received text from WebSocket: \(string)")
        case .binary(let data):
            print("Received binary data from WebSocket: \(data.count) bytes")
        case .ping(_):
            print("Received ping")
        case .pong(_):
            print("Received pong")
        case .viabilityChanged(let isViable):
            print("WebSocket viability changed: \(isViable)")
        case .reconnectSuggested(let isSuggested):
            print("WebSocket reconnect suggested: \(isSuggested)")
        case .cancelled:
            print("WebSocket cancelled")
        case .error(let error):
            print("WebSocket error: \(error?.localizedDescription ?? "Unknown error")")
        case .peerClosed:
            print("WebSocket peer closed")
        }
    }
}

// Main execution
let speechRecognizer = SpeechRecognizer()

do {
    try speechRecognizer.startRecording()
    print("Entering run loop")
    RunLoop.main.run()
} catch {
    print("An error occurred while starting the recording: \(error.localizedDescription)")
}