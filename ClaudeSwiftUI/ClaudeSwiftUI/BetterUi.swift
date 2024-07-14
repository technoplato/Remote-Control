import SwiftUI
import Combine
import Network

// MARK: - Application Overview and Requirements

/**
 Claude Remote Control - macOS SwiftUI Application
 
 Purpose:
 This application serves as a client for interacting with the Claude AI assistant. It provides a user interface
 similar to the web-based Claude interface, allowing users to send messages, view responses, and manage artifacts.
 
 Key Requirements:
 1. WebSocket Connection: Establish and maintain a WebSocket connection to the Claude server.
 2. Real-time Transcription Display: Show the current speech transcription as it's being processed.
 3. Message History: Display a scrollable history of user messages and Claude's responses.
 4. Artifact Management: Allow users to view, create, and manage artifacts (large text chunks or code snippets).
 5. Chat Controls: Provide an interface for managing artifacts and copied content.
 6. macOS UI Compatibility: Ensure the application looks and functions appropriately on macOS.
 
 This file contains the entire application, including networking, view models, and UI components.
 */

struct CLAUDE_MESSAGE_TYPES {
    static let CLAUDE_STATE_CHANGE = "CLAUDE.STATE_CHANGE"
    static let CLAUDE_RESPONSE_PART_RECEIVED = "CLAUDE.RESPONSE_PART_RECEIVED"
    static let CLAUDE_RESPONSE_COMPLETE = "CLAUDE.RESPONSE_COMPLETE"
    static let CLAUDE_SEND_USER_MESSAGE = "CLAUDE.SEND_USER_MESSAGE"
    static let CLAUDE_SET_CURRENT_INPUT = "CLAUDE.SET_CURRENT_INPUT"
    static let CLAUDE_SUBMIT_CURRENT_INPUT = "CLAUDE.SUBMIT_CURRENT_INPUT"
}


// MARK: - Debugging

/// Utility function for logging debug messages
func debugLog(_ message: String) {
    print("DEBUG: \(message)")
}

// MARK: - WebSocket Connection

/**
 Requirement: WebSocket Connection
 The WebSocketManager class handles the establishment and maintenance of a WebSocket connection to the Claude server.
 It manages connection states, sends and receives messages, and notifies the application of any connection changes.
 */
class WebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    @Published var isConnected = false
    @Published var connectionError: String?
    var messageHandler: ((String) -> Void)?
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "WebSocketMonitor")
    
    init() {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.status == .satisfied {
                    debugLog("Network connection available")
                    self?.connectionError = nil
                    self?.connect()
                } else {
                    debugLog("No network connection")
                    self?.connectionError = "No network connection"
                    self?.disconnect()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    func connect() {
        guard let url = URL(string: "ws://localhost:3000") else {
            connectionError = "Invalid URL"
            return
        }
        
        debugLog("Attempting to connect to WebSocket")
        let request = URLRequest(url: url)
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        connectionError = nil
        receiveMessage()
    }
    
    func disconnect() {
        debugLog("Disconnecting WebSocket")
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    debugLog("WebSocket receive error: \(error.localizedDescription)")
                    self.connectionError = "Error receiving message: \(error.localizedDescription)"
                    self.isConnected = false
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    debugLog("Received WebSocket message: \(text)")
                    DispatchQueue.main.async {
                        self.messageHandler?(text)
                    }
                @unknown default:
                    debugLog("Received unknown WebSocket message type")
                }
                self.receiveMessage()
            }
        }
    }
    
    func send(_ message: String) {
        debugLog("Sending WebSocket message: \(message)")
        webSocketTask?.send(.string(message)) { [weak self] error in
            if let error = error {
                debugLog("WebSocket send error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.connectionError = "Error sending message: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - View Model

/**
 Requirement: Real-time Transcription Display, Message History, Artifact Management
 The ClaudeViewModel class serves as the central data store and business logic handler for the application.
 It manages the WebSocket connection, processes incoming messages, and maintains the state of the UI.
 */
class ClaudeViewModel: ObservableObject {
    @Published var currentTranscription: String = ""
    @Published var messages: [Message] = []
    @Published var isConnected: Bool = false
    @Published var connectionError: String?
    @Published var artifacts: [Artifact] = []
    @Published var showArtifacts: Bool = true
    @Published var selectedArtifact: Artifact?
    @Published var copiedContents: [CopiedContent] = []
    @Published var showChatControls: Bool = false
    @Published var isClaudeTyping: Bool = false
    
    private var webSocketManager = WebSocketManager()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupWebSocket()
        setupSampleData()
    }
    
    private func setupWebSocket() {
        webSocketManager.messageHandler = { [weak self] message in
            self?.handleWebSocketMessage(message)
        }
        
        webSocketManager.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                debugLog("WebSocket connection status changed: \(isConnected)")
                self?.isConnected = isConnected
            }
            .store(in: &cancellables)
        
        webSocketManager.$connectionError
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionError)
        
        debugLog("Attempting to connect to WebSocket")
        webSocketManager.connect()
    }
    
    private func setupSampleData() {
        artifacts = [
            Artifact(title: "Updated SpeechRecognizer class", content: "// Code here", versions: ["1", "2", "3"]),
            Artifact(title: "Complete updated SpeechRecognizer script", content: "// Code here", versions: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]),
            Artifact(title: "Transcription Processor with Unit Tests", content: "// Code here", versions: ["1"])
        ]
        copiedContents = [
            CopiedContent(content: "Pasted content", size: "4.67 KB", lines: 90),
            CopiedContent(content: "paste-2.txt", size: "7.67 KB", lines: 215),
            CopiedContent(content: "Pasted content", size: "4.98 KB", lines: 97)
        ]
    }
    
    
    
    
    
    
    
    private func handleWebSocketMessage(_ message: String) {
        debugLog("Handling WebSocket message: \(message)")
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let type = json["type"] as? String else {
            debugLog("Invalid message format")
            return
        }
        
        DispatchQueue.main.async {
            switch type {
            case CLAUDE_MESSAGE_TYPES.CLAUDE_SET_CURRENT_INPUT:
                if let content = json["content"] as? String {
                    debugLog("Updating current transcription: \(content)")
                    self.currentTranscription = content
                }
            case CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_PART_RECEIVED,
                 CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_COMPLETE,
                 CLAUDE_MESSAGE_TYPES.CLAUDE_SEND_USER_MESSAGE:
                if let content = json["content"] as? String,
                   let isUser = json["isUser"] as? Bool {
                    debugLog("Adding new message: \(content), isUser: \(isUser)")
                    let newMessage = Message(content: content, isUser: isUser)
                    self.messages.append(newMessage)
                    if !isUser && type == CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_COMPLETE {
                        self.isClaudeTyping = false
                    }
                }
            case CLAUDE_MESSAGE_TYPES.CLAUDE_STATE_CHANGE:
                if let state = json["state"] as? String {
                    self.isClaudeTyping = (state == "generating")
                }
            default:
                debugLog("Unknown message type: \(type)")
            }
        }
    }
    
    func sendMessage(_ content: String) {
        let message = [
            "type": CLAUDE_MESSAGE_TYPES.CLAUDE_SEND_USER_MESSAGE,
            "content": content
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketManager.send(jsonString)
            self.messages.append(Message(content: content, isUser: true))
            self.isClaudeTyping = true
        }
    }
    
    func toggleArtifacts() {
        showArtifacts.toggle()
    }
    
    func toggleChatControls() {
        showChatControls.toggle()
    }
}

// MARK: - Models

struct Message: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
}

struct Artifact: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    var versions: [String] = []
    var lastEdited: Date = Date()
}

struct CopiedContent: Identifiable {
    let id = UUID()
    let content: String
    let size: String
    let lines: Int
}

struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - Views

/**
 Requirement: macOS UI Compatibility
 The ContentView struct defines the main user interface for the application.
 It's designed to work well on macOS, utilizing native UI components and layout structures.
 */
struct ContentView: View {
    @StateObject private var viewModel = ClaudeViewModel()
    @State private var inputText: String = ""
    @State private var showingArtifactPane: Bool = true
    
    var body: some View {
        NavigationView {
            HSplitView {
                VStack {
                    chatView
                    inputView
                }
                .frame(minWidth: 300)
                
                if showingArtifactPane {
                    artifactView
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                }
            }
            .navigationTitle("Claude Remote Control")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { viewModel.showChatControls.toggle() }) {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingArtifactPane.toggle() }) {
                        Image(systemName: "sidebar.right")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    if viewModel.isConnected {
                        Image(systemName: "network")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "network.slash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showChatControls) {
            ChatControlsView(viewModel: viewModel)
        }
        .alert(item: Binding<AlertItem?>(
            get: { viewModel.connectionError.map { AlertItem(message: $0) } },
            set: { _ in viewModel.connectionError = nil }
        )) { alertItem in
            Alert(title: Text("Connection Error"), message: Text(alertItem.message), dismissButton: .default(Text("OK")))
        }
    }
    
    var chatView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !viewModel.currentTranscription.isEmpty {
                    Text(viewModel.currentTranscription)
                        .foregroundColor(.blue)
                        .padding()
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(10)
                }
                
                ForEach(viewModel.messages) { message in
                    MessageView(message: message)
                }
                
                if viewModel.isClaudeTyping {
                    HStack {
                        Text("Claude is typing...")
                            .foregroundColor(.secondary)
                        ProgressView()
                    }
                    .padding()
                }
            }
            .padding()
        }
    }
    
    var inputView: some View {
        VStack {
            TextEditor(text: $inputText)
                .frame(height: 100)
                .padding(5)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
            
            HStack {
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    if let string = pasteboard.string(forType: .string) {
                        inputText += string
                    }
                }) {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(BorderlessButtonStyle())
                
                Spacer()
                
                Button(action: {
                    viewModel.sendMessage(inputText)
                    inputText = ""
                }) {
                    Text("Send")
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
                .buttonStyle(BorderlessButtonStyle())
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    var artifactView: some View {
        VStack {
            if let artifact = viewModel.selectedArtifact {
                ArtifactDetailView(artifact: artifact, onClose: { viewModel.selectedArtifact = nil })
            } else {
                Text("Artifacts")
                    .font(.headline)
                    .padding()
                
                if viewModel.artifacts.isEmpty {
                    Text("No artifacts available")
                        .foregroundColor(.secondary)
                } else {
                    List(viewModel.artifacts) { artifact in
                        Button(action: { viewModel.selectedArtifact = artifact }) {
                            HStack {
                                Image(systemName: "doc.text")
                                VStack(alignment: .leading) {
                                    Text(artifact.title)
                                    Text("\(artifact.versions.count) versions")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .background(Color(.textBackgroundColor))
    }
}

struct MessageView: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            Text(message.content)
                .padding()
                .background(message.isUser ? Color.accentColor.opacity(0.2) : Color(.textBackgroundColor))
                .cornerRadius(10)
            if !message.isUser {
                Spacer()
            }
        }
    }
}

struct ArtifactDetailView: View {
    let artifact: Artifact
    let onClose: () -> Void
    
    var body: some View {
        VStack {
            HStack {
                Text(artifact.title)
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            ScrollView {
                Text(artifact.content)
                    .padding()
            }
            
            HStack {
                Text("Last edited \(artifact.lastEdited, formatter: itemFormatter)")
                Spacer()
                Button(action: {}) {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(PlainButtonStyle())
                Button(action: {}) {
                    Image(systemName: "plus")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
        }
        .background(Color(.textBackgroundColor))
    }
}

/**
 Requirement: Chat Controls
 The ChatControlsView provides an interface for managing artifacts and copied content.
 It's presented as a sheet when the user clicks the ellipsis button in the toolbar.
 */
struct ChatControlsView: View {
    @ObservedObject var viewModel: ClaudeViewModel
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Artifacts")) {
                    ForEach(viewModel.artifacts) { artifact in
                        HStack {
                            Image(systemName: "doc.text")
                            Text(artifact.title)
                        }
                    }
                }
                
                Section(header: Text("Content")) {
                    ForEach(viewModel.copiedContents) { content in
                        HStack {
                            Image(systemName: "doc")
                            VStack(alignment: .leading) {
                                Text(content.content)
                                Text("\(content.size) • \(content.lines) extracted lines")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
//            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Chat Controls")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}()

// MARK: - App

@main
struct ClaudeRemoteControlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

// MARK: - Preview

/**
 Preview provider for SwiftUI previews in Xcode.
 This allows developers to see a preview of the UI components without running the full application.
 */
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
