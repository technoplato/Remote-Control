// Claude Remote Control Client Script with Verbose Logging

(function () {
  "use strict";

  const WS_SERVER_URL = "ws://localhost:3000";
  let socket;

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

  function log(message) {
    console.log(`[Debug] ${message}`);
  }

  function connectWebSocket() {
    log("Attempting to connect to WebSocket server...");
    socket = new WebSocket(WS_SERVER_URL);

    socket.onopen = () => {
      log("Connected to WebSocket server");
    };

    socket.onclose = () => {
      log("Disconnected from WebSocket server");
      setTimeout(connectWebSocket, 5000);
    };

    socket.onerror = (error) => {
      log(`WebSocket error: ${error}`);
    };

    socket.onmessage = (event) => {
      const data = JSON.parse(event.data);
      log(`Received message from server: ${JSON.stringify(data)}`);
      if (data.type === CLAUDE_MESSAGE_TYPES.CLAUDE_SET_CURRENT_INPUT) {
        setInputInClaude(data.content);
      } else if (
        data.type === CLAUDE_MESSAGE_TYPES.CLAUDE_SUBMIT_CURRENT_INPUT
      ) {
        submitInputToClaude();
      }
    };
  }

  connectWebSocket();

  function sendToServer(data) {
    if (socket && socket.readyState === WebSocket.OPEN) {
      log(`Sending to server: ${JSON.stringify(data)}`);
      socket.send(JSON.stringify(data));
    } else {
      log("WebSocket is not connected");
    }
  }

  function getFormattedTimestamp() {
    const now = new Date();
    return now.toLocaleString("en-US", {
      weekday: "long",
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
      timeZoneName: "short",
    });
  }

  function getCurrentChatUrl() {
    return window.location.href;
  }

  function setInputInClaude(message) {
    log("Attempting to set input in Claude...");

    const messageInput = document.querySelector(
      '.ProseMirror[contenteditable="true"]'
    );
    log(messageInput ? "Message input found" : "Message input not found");
    if (messageInput) {
      log(`Message input details: ${messageInput.outerHTML}`);

      // Set the message content
      log("Setting message content...");
      messageInput.textContent = message;
      log("Message content set");

      // Dispatch an input event to trigger any necessary UI updates
      log("Dispatching input event...");
      messageInput.dispatchEvent(new Event("input", { bubbles: true }));
      log("Input event dispatched");
    } else {
      log("Failed to find message input");
      log("Current page HTML:");
      log(document.body.innerHTML);
    }
  }

  function submitInputToClaude() {
    log("Attempting to submit input to Claude...");

    const sendButton = document.querySelector(
      'button[aria-label="Send Message"]'
    );
    if (sendButton && !sendButton.disabled) {
      log("Send button found and clickable");
      log(`Send button details: ${sendButton.outerHTML}`);
      sendButton.click();
      log("Send button clicked");

      // Clear the input after submission
      setTimeout(() => {
        const messageInput = document.querySelector(
          '.ProseMirror[contenteditable="true"]'
        );
        if (messageInput) {
          log("Clearing input...");
          messageInput.textContent = "";
          messageInput.dispatchEvent(new Event("input", { bubbles: true }));
          log("Input cleared");
        } else {
          log("Failed to find message input for clearing");
        }
      }, 100); // Short delay to ensure the message is sent before clearing
    } else {
      log("Send button not found or disabled");
    }
  }

  function monitorClaudeResponse() {
    const chatContainer = document.querySelector(".flex-1.flex.flex-col.gap-3");
    if (!chatContainer) {
      log("Chat container not found");
      throw new Error("Chat container not found, cant do anything");
    }
    log("Chat container found, setting up observer");

    let currentMessageId = null;
    let lastContent = "";

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          const addedNode = mutation.addedNodes[0];
          if (addedNode && addedNode.querySelector) {
            const responseDiv = addedNode.querySelector("[data-is-streaming]");
            if (responseDiv) {
              log("Found Claude response div");
              const isStreaming =
                responseDiv.getAttribute("data-is-streaming") === "true";
              const messageId = Date.now().toString();

              if (isStreaming) {
                currentMessageId = messageId;
                log(
                  `Claude started generating (MessageID: ${currentMessageId})`
                );
                sendToServer({
                  type: CLAUDE_MESSAGE_TYPES.CLAUDE_STATE_CHANGE,
                  state: "generating",
                  messageId: currentMessageId,
                  timestamp: getFormattedTimestamp(),
                  url: getCurrentChatUrl(),
                });
              } else {
                log(
                  `Claude finished generating (MessageID: ${currentMessageId})`
                );
                sendToServer({
                  type: CLAUDE_MESSAGE_TYPES.CLAUDE_STATE_CHANGE,
                  state: "finished",
                  messageId: currentMessageId,
                  timestamp: getFormattedTimestamp(),
                  url: getCurrentChatUrl(),
                });
                currentMessageId = null;
              }

              const contentObserver = new MutationObserver(() => {
                const paragraphs = responseDiv.querySelectorAll(
                  ".whitespace-pre-wrap.break-words"
                );
                const content = Array.from(paragraphs)
                  .map((p) => p.textContent)
                  .join("\n\n");

                if (content !== lastContent) {
                  log(`Content updated (MessageID: ${currentMessageId})`);
                  log(`New content: ${content}`);
                  sendToServer({
                    type: CLAUDE_MESSAGE_TYPES.CLAUDE_RESPONSE_PART_RECEIVED,
                    content: content,
                    messageId: currentMessageId,
                    timestamp: getFormattedTimestamp(),
                    url: getCurrentChatUrl(),
                  });
                  lastContent = content;
                }
              });

              contentObserver.observe(responseDiv, {
                childList: true,
                subtree: true,
                characterData: true,
              });
            }
          }
        }
      }
    });

    observer.observe(chatContainer, { childList: true, subtree: true });
    log("Observer set up for Claude responses");
  }

  function monitorUserMessages() {
    const chatContainer = document.querySelector(".flex-1.flex.flex-col.gap-3");
    if (!chatContainer) {
      log("Chat container not found");
      return;
    }
    log("Chat container found, setting up observer for user messages");

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          const addedNode = mutation.addedNodes[0];
          if (addedNode && addedNode.querySelector) {
            const userMessageDiv =
              addedNode.querySelector(".font-user-message");
            if (userMessageDiv) {
              const messageContent = userMessageDiv.querySelector(
                ".whitespace-pre-wrap.break-words"
              );
              if (messageContent) {
                log(`User message detected: ${messageContent.textContent}`);
                sendToServer({
                  type: CLAUDE_MESSAGE_TYPES.CLAUDE_SEND_USER_MESSAGE,
                  content: messageContent.textContent,
                  isUser: true,
                  timestamp: getFormattedTimestamp(),
                  url: getCurrentChatUrl(),
                });
              }
            }
          }
        }
      }
    });

    observer.observe(chatContainer, { childList: true, subtree: true });
    log("Observer set up for user messages");
  }

  function initMonitors() {
    monitorClaudeResponse();
    monitorUserMessages();
  }

  initMonitors();
  log(
    "Claude Remote Control Client Script with Verbose Logging is now running."
  );
})();
