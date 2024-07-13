import SwiftUI
import Combine

// MARK: - WebSocket Connection

class WebSocketManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    @Published var isConnected = false
    var messageHandler: ((String) -> Void)?

    func connect() {
        let url = URL(string: "ws://localhost:3000")!
        let request = URLRequest(url: url)
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        receiveMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
    }

    private func receiveMessage() {
        webSocketTask?.receive { result in
            switch result {
            case .failure(let error):
                print("Error receiving message: \(error)")
                self.isConnected = false
            case .success(let message):
                switch message {
                case .string(let text):
                    DispatchQueue.main.async {
                        self.messageHandler?(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()
            }
        }
    }

    func send(_ message: String) {
        webSocketTask?.send(.string(message)) { error in
            if let error = error {
                print("Error sending message: \(error)")
            }
        }
    }
}

// MARK: - View Model

class ClaudeRemoteControlViewModel: ObservableObject {
    @Published var currentTranscription: String = ""
    @Published var messages: [Message] = []
    @Published var isConnected: Bool = false

    private var webSocketManager = WebSocketManager()
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupWebSocket()
    }

    private func setupWebSocket() {
        webSocketManager.messageHandler = { [weak self] message in
            self?.handleWebSocketMessage(message)
        }

        webSocketManager.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        // Connect to WebSocket when the app starts
        webSocketManager.connect()
    }

    private func handleWebSocketMessage(_ message: String) {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let type = json["type"] as? String else {
            print("Invalid message format")
            return
        }

        switch type {
        case "set_input":
            if let content = json["content"] as? String {
                self.currentTranscription = content
            }
        case "message":
            if let content = json["content"] as? String,
               let isUser = json["isUser"] as? Bool {
                let newMessage = Message(content: content, isUser: isUser)
                self.messages.append(newMessage)
            }
        default:
            print("Unknown message type: \(type)")
        }
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
    let content: String
    // Add more properties as needed for artifacts
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var viewModel = ClaudeRemoteControlViewModel()

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Current Transcription")) {
                    Text(viewModel.currentTranscription)
                        .foregroundColor(.blue)
                }

                Section(header: Text("Conversation")) {
                    ForEach(viewModel.messages) { message in
                        MessageView(message: message)
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 300)

            ArtifactView()
        }
        .navigationTitle("Claude Remote Control")
        .toolbar {
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
                .background(message.isUser ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                .cornerRadius(10)
            if !message.isUser {
                Spacer()
            }
        }
    }
}

struct ArtifactView: View {
    var body: some View {
        VStack {
            Text("Artifacts Placeholder")
                .font(.title)
            Text("This area will display artifacts created by Claude")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
    }
}

// MARK: - App Entry Point

@main
struct ClaudeRemoteControlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
