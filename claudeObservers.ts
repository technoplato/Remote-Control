// Updated Console-friendly version of the Claude Remote Control Client Script

(function () {
  "use strict";

  const WS_SERVER_URL = "ws://localhost:3000";
  let socket;

  // Connect to WebSocket server
  function connectWebSocket() {
    socket = new WebSocket(WS_SERVER_URL);

    socket.onopen = () => {
      console.log("Connected to WebSocket server");
    };

    socket.onclose = () => {
      console.log("Disconnected from WebSocket server");
      setTimeout(connectWebSocket, 5000); // Attempt to reconnect after 5 seconds
    };

    socket.onerror = (error) => {
      console.error("WebSocket error:", error);
    };
  }

  connectWebSocket();

  // Send data to WebSocket server
  function sendToServer(data) {
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(data));
    } else {
      console.error("WebSocket is not connected");
    }
  }

  // Monitor Claude's response state
  function monitorClaudeState() {
    const chatContainer = document.querySelector(".flex-1.flex.flex-col.gap-3");
    if (!chatContainer) return;

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          const addedNode = mutation.addedNodes[0];
          if (addedNode && addedNode.querySelector) {
            const streamingElement = addedNode.querySelector(
              "[data-is-streaming]"
            );
            if (streamingElement) {
              const isStreaming =
                streamingElement.getAttribute("data-is-streaming") === "true";
              sendToServer({
                type: "claude_state",
                state: isStreaming ? "generating" : "finished",
              });
            }
          }
        }
      }
    });

    observer.observe(chatContainer, { childList: true, subtree: true });
  }

  // Monitor and capture messages
  function monitorMessages() {
    const chatContainer = document.querySelector(".flex-1.flex.flex-col.gap-3");
    if (!chatContainer) return;

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          const addedNode = mutation.addedNodes[0];
          if (addedNode && addedNode.querySelector) {
            const messageContent = addedNode.querySelector(
              ".whitespace-pre-wrap.break-words"
            );
            if (messageContent) {
              const isUserMessage =
                addedNode.querySelector(".font-user-message") !== null;
              sendToServer({
                type: "message",
                content: messageContent.textContent,
                isUser: isUserMessage,
              });
            }
          }
        }
      }
    });

    observer.observe(chatContainer, { childList: true, subtree: true });
  }

  // Monitor and capture artifacts
  function monitorArtifacts() {
    const chatContainer = document.querySelector(".flex-1.flex.flex-col.gap-3");
    if (!chatContainer) return;

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList") {
          const addedNode = mutation.addedNodes[0];
          if (addedNode && addedNode.querySelector) {
            const artifactElement = addedNode.querySelector(
              ".font-styrene.relative"
            );
            if (artifactElement) {
              const artifactContent = artifactElement.textContent;
              sendToServer({
                type: "artifact",
                content: artifactContent,
              });
            }
          }
        }
      }
    });

    observer.observe(chatContainer, { childList: true, subtree: true });
  }

  // Initialize all monitors
  function initMonitors() {
    monitorClaudeState();
    monitorMessages();
    monitorArtifacts();
  }

  // Start monitoring immediately
  initMonitors();

  console.log("Updated Claude Remote Control Client Script is now running.");
})();
