// Claude Remote Control Client Script with Combined Functionality and Enhanced Logging

(function () {
  "use strict";

  const WS_SERVER_URL = "ws://localhost:3000";
  let socket;

  const CLAUDE_MESSAGE_TYPES = {
    CLAUDE_STATE_CHANGE: "CLAUDE.STATE_CHANGE",
    CLAUDE_RESPONSE_PART_RECEIVED: "CLAUDE.RESPONSE_PART_RECEIVED",
    CLAUDE_RESPONSE_COMPLETE: "CLAUDE.RESPONSE_COMPLETE",
    CLAUDE_SEND_USER_MESSAGE: "CLAUDE.SEND_USER_MESSAGE",
    CLAUDE_SET_CURRENT_INPUT: "CLAUDE.SET_CURRENT_INPUT",
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
      // log(`Sending to server: ${JSON.stringify(data)}`);
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
    const messageInput = document.querySelector(
      '.ProseMirror[contenteditable="true"]'
    );
    if (messageInput) {
      messageInput.textContent = message;
      messageInput.dispatchEvent(new Event("input", { bubbles: true }));
    } else {
      log("Failed to find message input");
    }
  }

  function submitInputToClaude() {
    const sendButton = document.querySelector(
      'button[aria-label="Send Message"]'
    );
    if (sendButton && !sendButton.disabled) {
      sendButton.click();
      setTimeout(() => {
        const messageInput = document.querySelector(
          '.ProseMirror[contenteditable="true"]'
        );
        if (messageInput) {
          messageInput.textContent = "";
          messageInput.dispatchEvent(new Event("input", { bubbles: true }));
        }
      }, 100);
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

    let currentMessageId = null;
    let isGenerating = false;
    let lastContent = "";

    const observer = new MutationObserver((mutations) => {
      log("Mutation observed in chat container");

      const stateIndicator = document.querySelector(
        ".ml-1.mt-0\\.5.flex.items-center.transition-transform.duration-300.ease-out"
      );
      if (!stateIndicator) {
        log("State indicator not found");
      } else {
        const warningLink = stateIndicator.querySelector("a");
        if (!warningLink) {
          log("Warning link not found");
        } else {
          log(`State indicator classes: ${stateIndicator.className}`);
          log(`Warning link opacity: ${warningLink.style.opacity}`);
          log(`Current isGenerating state: ${isGenerating}`);

          const newIsGenerating =
            stateIndicator.classList.contains("-translate-y-2.5") &&
            warningLink.style.opacity === "0";

          if (newIsGenerating !== isGenerating) {
            isGenerating = newIsGenerating;
            log(`Claude state changed. Is generating: ${isGenerating}`);
          }
        }
      }

      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          const addedNode = mutation.addedNodes[0];
          if (addedNode && addedNode.querySelector) {
            const responseDiv = addedNode.querySelector("[data-is-streaming]");
            if (responseDiv) {
              log("Found Claude response div");
              const isStreaming =
                responseDiv.getAttribute("data-is-streaming") === "true";
              log(`Is streaming: ${isStreaming}`);

              if (isStreaming && !currentMessageId) {
                currentMessageId = Date.now().toString();
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
              } else if (!isStreaming && currentMessageId) {
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
                  log(
                    `Content updated (MessageID: ${currentMessageId || "N/A"})`
                  );
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
  log("Claude Remote Control Client Script is now running.");
})();
