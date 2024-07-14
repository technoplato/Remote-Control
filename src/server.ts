import express from "express";
import http from "http";
import { WebSocketServer } from "ws";
import { z } from "zod";

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const PORT = process.env.PORT || 3000;

/**
 * Message types for Claude Remote Control system
 */
const CLAUDE_MESSAGE_TYPES = {
  /**
   * Sent when Claude starts or stops generating a response
   * Triggered by: Claude beginning to type or finishing a response
   */
  CLAUDE_STATE_CHANGE: "CLAUDE.STATE_CHANGE",

  /**
   * Sent when a part of Claude's response is received
   * Triggered by: Claude generating part of a response
   */
  CLAUDE_RESPONSE_PART_RECEIVED: "CLAUDE.RESPONSE_PART_RECEIVED",

  /**
   * Sent when a complete message from Claude is received
   * Triggered by: Claude finishing a complete response
   */
  CLAUDE_RESPONSE_COMPLETE: "CLAUDE.RESPONSE_COMPLETE",

  /**
   * Sent when a user message is to be sent to Claude
   * Triggered by: User submitting a message in the UI
   */
  CLAUDE_SEND_USER_MESSAGE: "CLAUDE.SEND_USER_MESSAGE",

  /**
   * Sent when setting the current input in the Claude interface
   * Triggered by: Real-time speech transcription updates
   */
  CLAUDE_SET_CURRENT_INPUT: "CLAUDE.SET_CURRENT_INPUT",

  /**
   * Sent when submitting the current input to Claude
   * Triggered by: User finalizing their input (e.g., after speech recognition is complete)
   */
  CLAUDE_SUBMIT_CURRENT_INPUT: "CLAUDE.SUBMIT_CURRENT_INPUT",
};

// Zod schemas for payload validation
const ClaudeStateChangeSchema = z.object({
  type: z.literal(CLAUDE_MESSAGE_TYPES.CLAUDE_STATE_CHANGE),
  state: z.enum(["generating", "finished"]),
  messageId: z.string(),
  timestamp: z.string(),
  url: z.string().url(),
});

const ClaudeResponsePartReceivedSchema = z.object({
  type: z.literal(CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_PART_RECEIVED),
  content: z.string(),
  messageId: z.string(),
  timestamp: z.string(),
  url: z.string().url(),
});

const ClaudeResponseCompleteSchema = z.object({
  type: z.literal(CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_COMPLETE),
  content: z.string(),
  messageId: z.string(),
  timestamp: z.string(),
  url: z.string().url(),
});

const ClaudeSendUserMessageSchema = z.object({
  type: z.literal(CLAUDE_MESSAGE_TYPES.CLAUDE_SEND_USER_MESSAGE),
  content: z.string(),
});

const ClaudeSetCurrentInputSchema = z.object({
  type: z.literal(CLAUDE_MESSAGE_TYPES.CLAUDE_SET_CURRENT_INPUT),
  content: z.string(),
});

const ClaudeSubmitCurrentInputSchema = z.object({
  type: z.literal(CLAUDE_MESSAGE_TYPES.CLAUDE_SUBMIT_CURRENT_INPUT),
});

const PayloadSchema = z.discriminatedUnion("type", [
  ClaudeStateChangeSchema,
  ClaudeResponsePartReceivedSchema,
  ClaudeResponseCompleteSchema,
  ClaudeSendUserMessageSchema,
  ClaudeSetCurrentInputSchema,
  ClaudeSubmitCurrentInputSchema,
]);

type Payload = z.infer<typeof PayloadSchema>;

// Store WebSocket connections
const clients = new Set<WebSocket>();

// Handle WebSocket connections
wss.on("connection", (ws: WebSocket) => {
  console.log("New WebSocket connection");
  clients.add(ws);

  ws.on("message", async (message: string) => {
    try {
      const data = JSON.parse(message);
      await processWebSocketMessage(data);
    } catch (error) {
      console.error("Error processing message:", error);
      ws.send(JSON.stringify({ error: "Invalid message format" }));
    }
  });

  ws.on("close", () => {
    console.log("WebSocket connection closed");
    clients.delete(ws);
  });
});

// Process WebSocket messages
async function processWebSocketMessage(data: unknown): Promise<void> {
  try {
    const payload = PayloadSchema.parse(data);

    switch (payload.type) {
      case CLAUDE_MESSAGE_TYPES.CLAUDE_STATE_CHANGE:
      case CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_PART_RECEIVED:
      case CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_COMPLETE:
      case CLAUDE_MESSAGE_TYPES.CLAUDE_SEND_USER_MESSAGE:
      case CLAUDE_MESSAGE_TYPES.CLAUDE_SET_CURRENT_INPUT:
      case CLAUDE_MESSAGE_TYPES.CLAUDE_SUBMIT_CURRENT_INPUT:
        console.log(`Received ${payload.type} event:`, payload);
        // Send the message to all connected clients
        clients.forEach((client) => {
          if (client.readyState === WebSocket.OPEN) {
            const payload = JSON.stringify(data);
            console.log(`[would be] Sending payload to client: ${payload}`);

            client.send(payload);
          }
        });
        await updateLogEntry(payload);
        break;
      default:
        console.error("Unknown message type:", payload.type);
    }
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.error("Validation error:", error.errors);
      console.error("Received data:", JSON.stringify(data, null, 2));
    } else {
      console.error("Unknown error:", error);
    }
  }
}

function formatLogEntry(payload: Payload): string {
  const header = `${payload.timestamp}\nFrom: ${payload.url}\n`;
  let content = "";

  switch (payload.type) {
    case CLAUDE_MESSAGE_TYPES.CLAUDE_STATE_CHANGE:
      content = `Claude state: ${payload.state}\n`;
      break;
    case CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_PART_RECEIVED:
    case CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_COMPLETE:
      content = `Claude: ${payload.content}\n`;
      break;
    case CLAUDE_MESSAGE_TYPES.CLAUDE_SEND_USER_MESSAGE:
      content = `Sending to Claude: ${payload.content}\n`;
      break;
    case CLAUDE_MESSAGE_TYPES.CLAUDE_SET_CURRENT_INPUT:
      content = `Setting input: ${payload.content}\n`;
      break;
    case CLAUDE_MESSAGE_TYPES.CLAUDE_SUBMIT_CURRENT_INPUT:
      content = `Submitting input\n`;
      break;
  }

  return `${header}${content}\n`;
}

async function updateLogEntry(payload: Payload): Promise<void> {
  return;
  const logFile = path.join(__dirname, "messages.txt");
  try {
    let logContent = await fs.readFile(logFile, "utf-8");
    const entries = logContent.split("\n\n");
    const messageId = "messageId" in payload ? payload.messageId : null;

    if (messageId) {
      const index = entries.findIndex((entry) =>
        entry.includes(`MessageID: ${messageId}`)
      );
      if (index !== -1) {
        entries[index] = formatLogEntry(payload);
      } else {
        entries.push(formatLogEntry(payload));
      }
    } else {
      entries.push(formatLogEntry(payload));
    }

    logContent = entries.join("\n\n");
    await fs.writeFile(logFile, logContent);
  } catch (error) {
    console.error("Error updating log:", error);
  }
}

// API endpoint to send a message to Claude
app.post("/api/send-message", express.json(), (req, res) => {
  const { message } = req.body;
  if (!message) {
    return res.status(400).json({ error: "Message is required" });
  }

  const payload: Payload = {
    type: CLAUDE_MESSAGE_TYPES.CLAUDE_SEND_USER_MESSAGE,
    content: message,
  };

  // Send the message to all connected clients
  clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(payload));
    }
  });

  res.json({ success: true });
});

// Start the server
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
