import express from "express";
import fs from "fs/promises";
import http from "http";
import path from "path";
import { WebSocket, WebSocketServer } from "ws";
import { z } from "zod";

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const PORT = process.env.PORT || 3000;

// Zod schemas for payload validation
const ClaudeStateSchema = z.object({
  type: z.literal("claude_state"),
  state: z.enum(["generating", "finished"]),
  messageId: z.string(),
  timestamp: z.string(),
  url: z.string().url(),
});

const MessageSchema = z.object({
  type: z.literal("message"),
  content: z.string(),
  messageId: z.string().optional(),
  isUser: z.boolean().optional(),
  timestamp: z.string(),
  url: z.string().url(),
});

const SendMessageSchema = z.object({
  type: z.literal("send_message"),
  content: z.string(),
});

const PayloadSchema = z.discriminatedUnion("type", [
  ClaudeStateSchema,
  MessageSchema,
  SendMessageSchema,
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
      case "claude_state":
        console.log("Claude state:", payload.state);
        await updateLogEntry(payload);
        break;
      case "message":
        console.log("New message:", payload.content);
        await updateLogEntry(payload);
        break;
      case "send_message":
        console.log("Sending message to Claude:", payload.content);
        // Send the message to all connected clients
        clients.forEach((client) => {
          if (client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify(payload));
          }
        });
        break;
    }
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.error("Validation error:", error.errors);
    } else {
      console.error("Unknown error:", error);
    }
  }
}

function formatLogEntry(payload: Payload): string {
  const header = `${payload.timestamp}\nFrom: ${payload.url}\n`;
  let content = "";

  switch (payload.type) {
    case "claude_state":
      content = `Claude state: ${payload.state}\n`;
      break;
    case "message":
      content = `${payload.isUser ? "User" : "Claude"}: ${payload.content}\n`;
      break;
    case "send_message":
      content = `Sending to Claude: ${payload.content}\n`;
      break;
  }

  return `${header}${content}\n`;
}

async function updateLogEntry(payload: Payload): Promise<void> {
  const logFile = path.join(__dirname, "messages.txt");
  try {
    let logContent = await fs.readFile(logFile, "utf-8");
    const entries = logContent.split("\n\n");
    const messageId = (payload as any).messageId;

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
    type: "send_message",
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
