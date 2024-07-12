// Updated Claude Remote Control Client Script

(function () {
  "use strict";

  const WS_SERVER_URL = "ws://localhost:3000";
  let socket;

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
      if (data.type === "send_message") {
        sendMessageToClaude(data.content);
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

  function sendMessageToClaude(message) {
    const messageInput = document.querySelector(
      '.ProseMirror[contenteditable="true"]'
    );
    const sendButton = document.querySelector(
      'button[aria-label="Send Message"]'
    );

    if (messageInput && sendButton) {
      // Set the message content
      messageInput.textContent = message;

      // Dispatch an input event to trigger any necessary UI updates
      messageInput.dispatchEvent(new Event("input", { bubbles: true }));

      // Click the send button
      sendButton.click();

      log(`Sent message to Claude: ${message}`);
    } else {
      log("Failed to find message input or send button");
    }
  }

  function monitorClaudeResponse() {
    const chatContainer = document.querySelector(".flex-1.flex.flex-col.gap-3");
    if (!chatContainer) {
      log("Chat container not found");
      return;
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
                  type: "claude_state",
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
                  type: "claude_state",
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
                    type: "message",
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
                  type: "message",
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
  log("Updated Claude Remote Control Client Script is now running.");
})();
