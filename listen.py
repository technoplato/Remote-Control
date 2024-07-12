import os
import json
import pyaudio
import websockets
import asyncio
import logging
from dotenv import load_dotenv
from deepgram import DeepgramClient, DeepgramClientOptions, LiveOptions, LiveTranscriptionEvents

# Set up logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')

# Load environment variables
load_dotenv()
logging.debug("Environment variables loaded")

# Deepgram API Key
DEEPGRAM_API_KEY = os.getenv('DEEPGRAM_API_KEY')
logging.debug(f"Deepgram API Key: {'*' * (len(DEEPGRAM_API_KEY) - 4) + DEEPGRAM_API_KEY[-4:]}")

# Claude WebSocket URL
CLAUDE_WS_URL = os.getenv('CLAUDE_WS_URL', 'ws://localhost:3000')
logging.debug(f"Claude WebSocket URL: {CLAUDE_WS_URL}")

# Audio settings
CHANNELS = 1
FRAME_RATE = 16000
CHUNK = 8000
FORMAT = pyaudio.paInt16
logging.debug(f"Audio settings - Channels: {CHANNELS}, Frame Rate: {FRAME_RATE}, Chunk: {CHUNK}")

# Global variables
transcript_buffer = ""
is_final = False

async def send_to_claude(message):
    logging.debug(f"Attempting to send message to Claude: {message[:50]}...")
    try:
        async with websockets.connect(CLAUDE_WS_URL) as ws:
            await ws.send(json.dumps({
                "type": "send_message",
                "content": message
            }))
            logging.debug("Message sent to Claude")
            response = await ws.recv()
            logging.debug(f"Received response from Claude: {response[:50]}...")
            print(f"Claude response: {response}")
    except Exception as e:
        logging.error(f"Error sending message to Claude: {e}")

def on_message(result):
    global transcript_buffer, is_final
    logging.debug("on_message callback triggered")
    try:
        logging.debug(f"Full Deepgram response: {json.dumps(result, indent=2)}")
        sentence = result['channel']['alternatives'][0]['transcript']
        logging.debug(f"Raw sentence from Deepgram: {sentence}")
        if len(sentence) == 0:
            logging.debug("Empty sentence received, returning")
            return
        print(f"Transcription: {sentence}")
        logging.info(f"Transcription: {sentence}")
        transcript_buffer += sentence + " "
        logging.debug(f"Updated transcript buffer: {transcript_buffer}")
        if "done" in sentence.lower():
            logging.info("'done' detected in transcript")
            is_final = True
    except Exception as e:
        logging.error(f"Error in on_message: {e}")

def on_metadata(self, metadata, **kwargs):
    logging.debug(f"Received metadata: {metadata}")

def on_error(self, error, **kwargs):
    logging.error(f"Deepgram error: {error}")

def on_close(self, code, reason, **kwargs):
    logging.info(f"WebSocket closed with code {code}: {reason}")

def audio_generator():
    logging.debug("Starting audio generator")
    p = pyaudio.PyAudio()
    try:
        stream = p.open(format=FORMAT, channels=CHANNELS, rate=FRAME_RATE, input=True, frames_per_buffer=CHUNK)
        logging.debug("Audio stream opened")
        
        while True:
            data = stream.read(CHUNK)
            logging.debug(f"Read audio chunk of size: {len(data)}")
            yield data
    except Exception as e:
        logging.error(f"Error in audio generator: {e}")
    finally:
        logging.debug("Closing audio stream")
        stream.stop_stream()
        stream.close()
        p.terminate()

def main():
    global is_final
    logging.info("Starting main function")

    # Configure DeepgramClientOptions
    config = DeepgramClientOptions(
        options={"keepalive": "true"}
    )
    logging.debug("Deepgram client options configured")

    # Create a Deepgram client
    deepgram = DeepgramClient(DEEPGRAM_API_KEY, config)
    logging.debug("Deepgram client created")

    # Create a websocket connection
    dg_connection = deepgram.listen.live.v("1")
    logging.debug("Deepgram websocket connection created")

    # Register event handlers
    dg_connection.on(LiveTranscriptionEvents.Transcript, lambda *args, **kwargs: on_message(args[1]))
    dg_connection.on(LiveTranscriptionEvents.Metadata, lambda *args, **kwargs: on_metadata(*args, **kwargs)) 
    dg_connection.on(LiveTranscriptionEvents.Error, on_error)
    dg_connection.on(LiveTranscriptionEvents.Close, on_close)
    logging.debug("Event handlers registered")

    # Set up LiveOptions
    options = LiveOptions(
        punctuate=True,
        interim_results=False,
        language='en-US',
        model='nova-2'
    )
    logging.debug(f"LiveOptions set up: {options}")

    # Start the connection
    dg_connection.start(options)
    logging.info("Deepgram connection started")

    print("Listening... Say 'done' to send the transcribed message to Claude.")
    logging.info("Listening for audio input")

    try:
        for audio_chunk in audio_generator():
            if is_final:
                logging.info("Final transcript received, breaking audio loop")
                break
            dg_connection.send(audio_chunk)
            logging.debug(f"Sent audio chunk of size {len(audio_chunk)} to Deepgram")
    except KeyboardInterrupt:
        logging.info("Keyboard interrupt detected")
        print("\nStopping...")
    except Exception as e:
        logging.error(f"Unexpected error in main audio loop: {e}")
    finally:
        logging.info("Finishing Deepgram connection")
        dg_connection.finish()

    if is_final:
        logging.info(f"Sending final message to Claude: {transcript_buffer.strip()[:50]}...")
        print(f"Sending message to Claude: {transcript_buffer.strip()}")
        asyncio.run(send_to_claude(transcript_buffer.strip()))
    else:
        logging.warning("Script ended without receiving a final transcript")

if __name__ == "__main__":
    logging.info("Script started")
    main()
    logging.info("Script ended")