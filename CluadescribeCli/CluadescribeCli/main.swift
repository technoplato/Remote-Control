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
    private var isCollectingNewTranscription: Bool = true
    
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
        // Cancel the previous task if it's running.
        if let task = recognitionTask {
            print("Cancelling previous recognition task")
            task.cancel()
            self.recognitionTask = nil
        }
        
        let inputNode = audioEngine.inputNode
        
        // Create and configure the speech recognition request.
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("Failed to create SFSpeechAudioBufferRecognitionRequest")
            fatalError("Unable to create a SFSpeechAudioBufferRecognitionRequest object")
        }
        recognitionRequest.shouldReportPartialResults = true
        
        // Keep speech recognition data on device
//        if #available(macOS 10.15, *) {
//            recognitionRequest.requiresOnDeviceRecognition = true
//            print("On-device recognition enabled")
//        }
        
        // Create a recognition task for the speech recognition session.
        print("Creating recognition task")
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                print("Transcription received: \(transcription)")
                
                if self.isCollectingNewTranscription {
                    self.currentTranscription = transcription
                    self.setInputInClaude(transcription)
                }
                
                isFinal = result.isFinal
                
                if transcription.lowercased().contains("done") {
                    print("'Done' detected in transcription. Submitting input.")
                    self.submitInputToClaude()
                    self.isCollectingNewTranscription = false
                    // Short delay before starting a new transcription
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.startNewTranscription()
                    }
                }
            }
            
            if let error = error {
                print("Error in recognition task: \(error.localizedDescription)")
            }
            
            if error != nil || isFinal {
                print("Stopping audio engine and removing tap")
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        // Configure the microphone input.
        print("Configuring microphone input")
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        print("Starting audio engine")
        try audioEngine.start()
        
        print("Recording started successfully")
    }
    
    func stopRecording() {
        print("Stopping recording")
        audioEngine.stop()
        recognitionRequest?.endAudio()
        
        print("Recording stopped")
    }
    
    func startNewTranscription() {
        print("Starting new transcription")
        currentTranscription = ""
        isCollectingNewTranscription = true
        setInputInClaude("")
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
            } else {
                print("Failed to create JSON string from data")
            }
        } catch {
            print("Error serializing JSON: \(error.localizedDescription)")
        }
    }
    
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

//print("Press Enter to start recording. Say 'done' to submit the current transcription and start a new one.")
//_ = readLine()

do {
    try speechRecognizer.startRecording()
    print("Entering run loop")
    RunLoop.main.run()
} catch {
    print("An error occurred while starting the recording: \(error.localizedDescription)")
}
