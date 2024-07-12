// Claude Remote Control Client Script - Fixed

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
                });
              } else {
                log(
                  `Claude finished generating (MessageID: ${currentMessageId})`
                );
                sendToServer({
                  type: "claude_state",
                  state: "finished",
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
  log("Claude Remote Control Client Script - Fixed is now running.");
})();
