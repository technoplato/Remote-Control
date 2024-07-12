import { z } from "zod";

const WS_SERVER_URL = "ws://localhost:3000";

// Zod schemas for payload validation
const ClaudeStateSchema = z.object({
  type: z.literal("claude_state"),
  state: z.enum(["generating", "finished"]),
});

const MessageSchema = z.object({
  type: z.literal("message"),
  content: z.string(),
});

const ArtifactSchema = z.object({
  type: z.literal("artifact"),
  content: z.string(),
});

const PayloadSchema = z.discriminatedUnion("type", [
  ClaudeStateSchema,
  MessageSchema,
  ArtifactSchema,
]);

type Payload = z.infer<typeof PayloadSchema>;

class ClaudeRemoteControl {
  private socket: WebSocket | null = null;

  constructor() {
    this.connectWebSocket();
  }

  private connectWebSocket(): void {
    this.socket = new WebSocket(WS_SERVER_URL);

    this.socket.onopen = () => {
      console.log("Connected to WebSocket server");
    };

    this.socket.onclose = () => {
      console.log("Disconnected from WebSocket server");
      setTimeout(() => this.connectWebSocket(), 5000); // Attempt to reconnect after 5 seconds
    };

    this.socket.onerror = (error) => {
      console.error("WebSocket error:", error);
    };
  }

  private sendToServer(data: Payload): void {
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      try {
        // Validate the payload before sending
        PayloadSchema.parse(data);
        this.socket.send(JSON.stringify(data));
      } catch (error) {
        console.error("Invalid payload:", error);
      }
    } else {
      console.error("WebSocket is not connected");
    }
  }

  private monitorClaudeState(): void {
    const chatContainer = document.querySelector(".flex-1.flex.flex-col.gap-3");
    if (!chatContainer) return;

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          const lastMessage = chatContainer.lastElementChild;
          if (
            lastMessage instanceof HTMLElement &&
            lastMessage.classList.contains("group")
          ) {
            const streamingElement = lastMessage.querySelector(
              "[data-is-streaming]"
            );
            if (streamingElement instanceof HTMLElement) {
              const isStreaming =
                streamingElement.getAttribute("data-is-streaming") === "true";
              this.sendToServer({
                type: "claude_state",
                state: isStreaming ? "generating" : "finished",
              });
            }
          }
        }
      }
    });

    observer.observe(chatContainer, { childList: true, subtree: true });
  }

  private monitorMessages(): void {
    const chatContainer = document.querySelector(".flex-1.flex.flex-col.gap-3");
    if (!chatContainer) return;

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          const newMessage = mutation.addedNodes[0];
          if (
            newMessage instanceof HTMLElement &&
            newMessage.classList.contains("group")
          ) {
            const messageContent = newMessage.querySelector(
              ".whitespace-pre-wrap"
            )?.textContent;
            if (messageContent) {
              this.sendToServer({
                type: "message",
                content: messageContent,
              });
            }
          }
        }
      }
    });

    observer.observe(chatContainer, { childList: true });
  }

  private monitorArtifacts(): void {
    const chatContainer = document.querySelector(".flex-1.flex.flex-col.gap-3");
    if (!chatContainer) return;

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          const newNode = mutation.addedNodes[0];
          if (
            newNode instanceof HTMLElement &&
            newNode.classList.contains("group")
          ) {
            const artifactElement = newNode.querySelector(
              ".font-styrene.relative"
            );
            if (artifactElement instanceof HTMLElement) {
              const artifactContent = artifactElement.textContent;
              if (artifactContent) {
                this.sendToServer({
                  type: "artifact",
                  content: artifactContent,
                });
              }
            }
          }
        }
      }
    });

    observer.observe(chatContainer, { childList: true, subtree: true });
  }

  public initMonitors(): void {
    this.monitorClaudeState();
    this.monitorMessages();
    this.monitorArtifacts();
  }
}

// Initialize and start the remote control
const remoteControl = new ClaudeRemoteControl();
remoteControl.initMonitors();

console.log("Claude Remote Control TypeScript Client is now running.");
