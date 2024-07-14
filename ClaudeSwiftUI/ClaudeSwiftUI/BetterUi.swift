import SwiftUI
import Combine

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

// MARK: - ViewModel

class ClaudeViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var currentInput: String = ""
    @Published var artifacts: [Artifact] = []
    @Published var showArtifacts: Bool = true
    @Published var selectedArtifact: Artifact?
    @Published var copiedContents: [CopiedContent] = []
    @Published var showChatControls: Bool = false
    
    init() {
        // Sample data
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
    
    func sendMessage() {
        let newMessage = Message(content: currentInput, isUser: true)
        messages.append(newMessage)
        // Simulate Claude's response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let claudeResponse = Message(content: "This is a simulated response from Claude.", isUser: false)
            self.messages.append(claudeResponse)
        }
        currentInput = ""
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var viewModel = ClaudeViewModel()
    @State private var showingArtifact = false
    
    var body: some View {
        NavigationView {
            HStack(spacing: 0) {
                VStack {
                    chatView
                    inputView
                }
                .frame(maxWidth: .infinity)
                
                if viewModel.showArtifacts {
                    artifactView
                        .frame(width: 300)
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
                    Button(action: { viewModel.showArtifacts.toggle() }) {
                        Image(systemName: "sidebar.right")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showChatControls) {
                ChatControlsView(viewModel: viewModel)
            }
        }
    }
    
    var chatView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.messages) { message in
                    MessageView(message: message)
                }
            }
            .padding()
        }
    }
    
    var inputView: some View {
        VStack {
            TextEditor(text: $viewModel.currentInput)
                .frame(height: 100)
                .padding(5)
                .background(Color(.systemGray))
                .cornerRadius(8)
            
            HStack {
                Spacer()
                Button(action: viewModel.sendMessage) {
                    Text("Send")
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
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
                }
            }
        }
        .background(Color(.systemGray))
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
            }
            .padding()
            
            Text(artifact.content)
                .padding()
            
            HStack {
                Text("Last edited \(artifact.lastEdited, formatter: itemFormatter)")
                Spacer()
                Button(action: {}) {
                    Image(systemName: "doc.on.clipboard")
                }
                Button(action: {}) {
                    Image(systemName: "plus")
                }
            }
            .padding()
        }
        .background(Color(.systemGray))
    }
}

struct ChatControlsView: View {
    @ObservedObject var viewModel: ClaudeViewModel
    
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
            .navigationTitle("Chat controls")
//            .navigationBarItems(trailing: Button("Done") {
//                viewModel.showChatControls = false
//            })
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

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// MARK: - App

@main
struct ClaudeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
