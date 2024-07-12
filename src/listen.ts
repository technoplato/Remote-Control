import { createClient, LiveTranscriptionEvents } from "@deepgram/sdk";
import { config } from "dotenv";
import fs from "fs";
import record from "node-record-lpcm16";
import WebSocket from "ws";
import { z } from "zod";

// Load environment variables
config();

// Define and validate environment variables
const envSchema = z.object({
  DEEPGRAM_API_KEY: z.string().min(1, {
    message:
      "DEEPGRAM_API_KEY is required. Get one at https://console.deepgram.com/signup?jump=keys",
  }),
  CLAUDE_WS_URL: z.string().url({
    message: "CLAUDE_WS_URL must be a valid WebSocket URL",
  }),
});

function log(message: string) {
  const timestamp = new Date().toISOString();
  const logMessage = `${timestamp}: ${message}\n`;
  console.log(logMessage);
  fs.appendFileSync("listen_log.txt", logMessage);
}

function logError(message: string, error: any) {
  const timestamp = new Date().toISOString();
  const errorMessage = `${timestamp} ERROR: ${message}\n${
    error.stack || error
  }\n`;
  console.error(errorMessage);
  fs.appendFileSync("listen_error_log.txt", errorMessage);
}

try {
  const env = envSchema.parse(process.env);

  // Initialize Deepgram client
  const deepgram = createClient(env.DEEPGRAM_API_KEY);

  // Initialize WebSocket connection to Claude
  const claudeWs = new WebSocket(env.CLAUDE_WS_URL);

  claudeWs.on("open", () => {
    log("Connected to Claude WebSocket");
  });

  claudeWs.on("error", (error) => {
    logError("Claude WebSocket error:", error);
  });

  // Start Deepgram live transcription
  const live = deepgram.listen.live({
    model: "nova",
    punctuate: true,
    language: "en-US",
    encoding: "linear16",
    sample_rate: 16000,
  });

  live.on(LiveTranscriptionEvents.Open, () => {
    log("Deepgram connection opened");

    // Start recording and streaming audio to Deepgram
    let recording;
    try {
      recording = record.record({
        sampleRate: 16000,
        channels: 1,
        audioType: "raw",
        recorder: "sox",
      });

      recording
        .stream()
        .on("data", (chunk) => {
          try {
            live.send(chunk);
          } catch (error) {
            logError("Error sending audio chunk to Deepgram:", error);
          }
        })
        .on("error", (error) => {
          logError("Error in audio stream:", error);
        });

      log("Recording started");
    } catch (error) {
      logError("Error starting audio recording:", error);
    }
  });

  let transcriptBuffer = "";

  live.on(LiveTranscriptionEvents.Transcript, (data) => {
    try {
      const transcript = data.channel.alternatives[0].transcript;
      if (transcript.trim()) {
        log(`Transcript: ${transcript}`);
        transcriptBuffer += transcript + " ";

        if (transcript.toLowerCase().includes("done")) {
          log(`Sending message to Claude: ${transcriptBuffer}`);
          claudeWs.send(
            JSON.stringify({
              type: "send_message",
              content: transcriptBuffer.trim(),
            })
          );
          transcriptBuffer = "";
        }
      }
    } catch (error) {
      logError("Error processing transcript:", error);
    }
  });

  live.on(LiveTranscriptionEvents.Error, (error) => {
    logError("Deepgram error:", error);
  });

  claudeWs.on("message", (data) => {
    try {
      const message = JSON.parse(data.toString());
      if (message.type === "message") {
        log(`Claude response: ${message.content}`);
      }
    } catch (error) {
      logError("Error processing Claude response:", error);
    }
  });

  process.on("SIGINT", () => {
    log("Shutting down...");
    live.finish();
    claudeWs.close();
    process.exit(0);
  });

  log('Listening... Say "done" to send the transcribed message to Claude.');
} catch (error) {
  logError("Error during setup:", error);
  process.exit(1);
}
