import express from "express";
import fs from "fs/promises";
import http from "http";
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
        break;
      case "message":
        console.log("New message:", payload.content);
        await saveMessage(payload.content);
        break;
      case "artifact":
        console.log("New artifact:", payload.content);
        await saveArtifact(payload.content);
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

// Save messages to a file
async function saveMessage(content: string): Promise<void> {
  try {
    await fs.appendFile("messages.txt", content + "\n");
  } catch (error) {
    console.error("Error saving message:", error);
  }
}

// Save artifacts to a file
async function saveArtifact(content: string): Promise<void> {
  try {
    await fs.writeFile(`artifact_${Date.now()}.txt`, content);
  } catch (error) {
    console.error("Error saving artifact:", error);
  }
}

// API endpoint to send a message to Claude
app.post("/api/send-message", express.json(), (req, res) => {
  const SendMessageSchema = z.object({
    message: z.string().min(1),
  });

  try {
    const { message } = SendMessageSchema.parse(req.body);

    // Here you would implement the logic to send the message to Claude
    // For now, we'll just log it
    console.log("Sending message to Claude:", message);

    res.json({ success: true });
  } catch (error) {
    if (error instanceof z.ZodError) {
      res.status(400).json({ error: "Invalid request", details: error.errors });
    } else {
      res.status(500).json({ error: "Internal server error" });
    }
  }
});

// Start the server
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
