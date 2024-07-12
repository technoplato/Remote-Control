import os
import json
import pyaudio
import websockets
import asyncio
from dotenv import load_dotenv
from deepgram import DeepgramClient, DeepgramClientOptions, LiveOptions, LiveTranscriptionEvents

# Load environment variables
load_dotenv()

# Deepgram API Key
DEEPGRAM_API_KEY = os.getenv('DEEPGRAM_API_KEY')

# Claude WebSocket URL
CLAUDE_WS_URL = os.getenv('CLAUDE_WS_URL', 'ws://localhost:3000')

# Audio settings
CHANNELS = 1
FRAME_RATE = 16000
CHUNK = 8000
FORMAT = pyaudio.paInt16

# Global variables
transcript_buffer = ""
is_final = False

async def send_to_claude(message):
    async with websockets.connect(CLAUDE_WS_URL) as ws:
        await ws.send(json.dumps({
            "type": "send_message",
            "content": message
        }))
        response = await ws.recv()
        print(f"Claude response: {response}")

def on_message(self, result, **kwargs):
    global transcript_buffer, is_final
    sentence = result.channel.alternatives[0].transcript
    if len(sentence) == 0:
        return
    print(f"Transcription: {sentence}")
    transcript_buffer += sentence + " "
    if "done" in sentence.lower():
        is_final = True

def on_error(self, error, **kwargs):
    print(f"Error: {error}")

def audio_generator():
    p = pyaudio.PyAudio()
    stream = p.open(format=FORMAT, channels=CHANNELS, rate=FRAME_RATE, input=True, frames_per_buffer=CHUNK)
    
    try:
        while True:
            yield stream.read(CHUNK)
    finally:
        stream.stop_stream()
        stream.close()
        p.terminate()

def main():
    global is_final

    # Configure DeepgramClientOptions
    config = DeepgramClientOptions(
        options={"keepalive": "true"}
    )

    # Create a Deepgram client
    deepgram = DeepgramClient(DEEPGRAM_API_KEY, config)

    # Create a websocket connection
    dg_connection = deepgram.listen.live.v("1")

    # Register event handlers
    dg_connection.on(LiveTranscriptionEvents.Transcript, on_message)
    dg_connection.on(LiveTranscriptionEvents.Error, on_error)

    # Set up LiveOptions
    options = LiveOptions(
        punctuate=True,
        interim_results=False,
        language='en-US',
        model='nova-2'
    )

    # Start the connection
    dg_connection.start(options)

    print("Listening... Say 'done' to send the transcribed message to Claude.")

    try:
        for audio_chunk in audio_generator():
            if is_final:
                break
            dg_connection.send(audio_chunk)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        dg_connection.finish()

    if is_final:
        print(f"Sending message to Claude: {transcript_buffer.strip()}")
        asyncio.run(send_to_claude(transcript_buffer.strip()))

if __name__ == "__main__":
    main()