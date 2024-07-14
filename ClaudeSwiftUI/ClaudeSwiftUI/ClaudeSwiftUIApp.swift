//import SwiftUI
//import Combine
//import Network
//
//// MARK: - Debugging
//
//func debugLog(_ message: String) {
//    print("DEBUG: \(message)")
//}
//
//// MARK: - WebSocket Connection
//
//class WebSocketManager: ObservableObject {
//    private var webSocketTask: URLSessionWebSocketTask?
//    @Published var isConnected = false
//    @Published var connectionError: String?
//    var messageHandler: ((String) -> Void)?
//    
//    private let monitor = NWPathMonitor()
//    private let monitorQueue = DispatchQueue(label: "WebSocketMonitor")
//
//    init() {
//        setupNetworkMonitoring()
//    }
//
//    private func setupNetworkMonitoring() {
//        monitor.pathUpdateHandler = { [weak self] path in
//            DispatchQueue.main.async {
//                if path.status == .satisfied {
//                    debugLog("Network connection available")
//                    self?.connectionError = nil
//                    self?.connect()
//                } else {
//                    debugLog("No network connection")
//                    self?.connectionError = "No network connection"
//                    self?.disconnect()
//                }
//            }
//        }
//        monitor.start(queue: monitorQueue)
//    }
//
//    func connect() {
//        guard let url = URL(string: "ws://localhost:3000") else {
//            connectionError = "Invalid URL"
//            return
//        }
//        
//        debugLog("Attempting to connect to WebSocket")
//        let request = URLRequest(url: url)
//        let session = URLSession(configuration: .default)
//        webSocketTask = session.webSocketTask(with: request)
//        webSocketTask?.resume()
//        isConnected = true
//        connectionError = nil
//        receiveMessage()
//    }
//
//    func disconnect() {
//        debugLog("Disconnecting WebSocket")
//        webSocketTask?.cancel(with: .normalClosure, reason: nil)
//        isConnected = false
//    }
//
//    private func receiveMessage() {
//        webSocketTask?.receive { [weak self] result in
//            guard let self = self else { return }
//            
//            switch result {
//            case .failure(let error):
//                DispatchQueue.main.async {
//                    debugLog("WebSocket receive error: \(error.localizedDescription)")
//                    self.connectionError = "Error receiving message: \(error.localizedDescription)"
//                    self.isConnected = false
//                }
//            case .success(let message):
//                switch message {
//                case .string(let text):
//                    debugLog("Received WebSocket message: \(text)")
//                    DispatchQueue.main.async {
//                        self.messageHandler?(text)
//                    }
//                @unknown default:
//                    debugLog("Received unknown WebSocket message type")
//                }
//                self.receiveMessage()
//            }
//        }
//    }
//
//    func send(_ message: String) {
//        debugLog("Sending WebSocket message: \(message)")
//        webSocketTask?.send(.string(message)) { [weak self] error in
//            if let error = error {
//                debugLog("WebSocket send error: \(error.localizedDescription)")
//                DispatchQueue.main.async {
//                    self?.connectionError = "Error sending message: \(error.localizedDescription)"
//                }
//            }
//        }
//    }
//}
//
//// MARK: - View Model
//
//class ClaudeRemoteControlViewModel: ObservableObject {
//    @Published var currentTranscription: String = ""
//    @Published var messages: [Message] = []
//    @Published var isConnected: Bool = false
//    @Published var connectionError: String?
//
//    private var webSocketManager = WebSocketManager()
//    private var cancellables = Set<AnyCancellable>()
//
//    init() {
//        setupWebSocket()
//    }
//
//    private func setupWebSocket() {
//        webSocketManager.messageHandler = { [weak self] message in
//            self?.handleWebSocketMessage(message)
//        }
//
//        webSocketManager.$isConnected
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] isConnected in
//                debugLog("WebSocket connection status changed: \(isConnected)")
//                self?.isConnected = isConnected
//            }
//            .store(in: &cancellables)
//
//        webSocketManager.$connectionError
//            .receive(on: DispatchQueue.main)
//            .assign(to: &$connectionError)
//
//        debugLog("Attempting to connect to WebSocket")
//        webSocketManager.connect()
//    }
//
//    private func handleWebSocketMessage(_ message: String) {
//        debugLog("Handling WebSocket message: \(message)")
//        guard let data = message.data(using: .utf8),
//              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//              let type = json["type"] as? String else {
//            debugLog("Invalid message format")
//            return
//        }
//
//        switch type {
//        case "set_input":
//            if let content = json["content"] as? String {
//                debugLog("Updating current transcription: \(content)")
//                DispatchQueue.main.async {
//                    self.currentTranscription = content
//                }
//            }
//        case "message":
//            if let content = json["content"] as? String,
//               let isUser = json["isUser"] as? Bool {
//                debugLog("Adding new message: \(content), isUser: \(isUser)")
//                let newMessage = Message(content: content, isUser: isUser)
//                DispatchQueue.main.async {
//                    self.messages.append(newMessage)
//                }
//            }
//        default:
//            debugLog("Unknown message type: \(type)")
//        }
//    }
//}
//
//// MARK: - Models
//
//struct Message: Identifiable {
//    let id = UUID()
//    let content: String
//    let isUser: Bool
//}
//
//// MARK: - Views
//
//struct ContentView: View {
//    @StateObject private var viewModel = ClaudeRemoteControlViewModel()
//
//    var body: some View {
//        NavigationView {
//            List {
//                Section(header: Text("Current Transcription")) {
//                    Text(viewModel.currentTranscription)
//                        .foregroundColor(.blue)
//                }
//
//                Section(header: Text("Conversation")) {
//                    ForEach(viewModel.messages) { message in
//                        MessageView(message: message)
//                    }
//                }
//            }
//            .listStyle(SidebarListStyle())
//            .frame(minWidth: 300)
//
//            Text("Artifacts Placeholder")
//                .font(.title)
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//        }
//        .navigationTitle("Claude Remote Control")
//        .toolbar {
//            ToolbarItem(placement: .automatic) {
//                if viewModel.isConnected {
//                    Image(systemName: "network")
//                        .foregroundColor(.green)
//                } else {
//                    Image(systemName: "network.slash")
//                        .foregroundColor(.red)
//                }
//            }
//        }
//        .alert(item: Binding<AlertItem?>(
//            get: { viewModel.connectionError.map { AlertItem(message: $0) } },
//            set: { _ in viewModel.connectionError = nil }
//        )) { alertItem in
//            Alert(title: Text("Connection Error"), message: Text(alertItem.message), dismissButton: .default(Text("OK")))
//        }
//    }
//}
//
//struct MessageView: View {
//    let message: Message
//
//    var body: some View {
//        HStack {
//            if message.isUser {
//                Spacer()
//            }
//            Text(message.content)
//                .padding()
//                .background(message.isUser ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
//                .cornerRadius(10)
//            if !message.isUser {
//                Spacer()
//            }
//        }
//    }
//}
//
//struct AlertItem: Identifiable {
//    let id = UUID()
//    let message: String
//}
//
//// MARK: - App Entry Point
//
//@main
//struct ClaudeRemoteControlApp: App {
//    var body: some Scene {
//        WindowGroup {
//            ContentView()
//        }
//    }
//}
