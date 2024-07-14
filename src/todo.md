# Project To-Do List

## High Priority

## Currently Working On

- [ ] Build a user interface that works on iOS and macOS for interacting with Claude website

## Next Up

- [ ] Have the server keep track of how many tokens you've sent and how many tokens you've received

## Done

- [x] Changing trigger word from "done" to "JINX"
- [x] Debugging message receiving issues

### User Interface

- [ ] Implement a sliding drawer that follows the text being said (collapsible)
- [ ] Add visual indicator for ongoing response without showing full text
- [ ] Create a locally running chat interface
- [ ] Develop a simple Swift application for better interaction than reading logs
- [ ] Auto-scroll to bottom of input text in web interface

### Core Functionality

- [ ] Make it easier to start everything
- [ ] When server starts up, it should automatically add the monitor script to claude.ai webpages and somehow know which one to do.
- [ ] Make the trigger word ("JINX") configurable
- [ ] More tightly integrate with the Claude interface for a more complete feature set
- [ ] Implement artifact handling:
  - [ ] Parse out artifacts from Claude responses
  - [ ] Enable downloading and local storage of artifacts
- [ ] Develop methodology for communicating from user's mobile device to server controlling Claude
- [ ] Implement ability to copy large files to Claude (similar to web interface)
- [ ] Ability to interrupt Claude

### Monetization

- [ ] Track token usage via web interface
  - [ ] tokens sent
  - [ ] tokens received
  - [ ] what that would cost via the API
  - [ ] what the user is paying for the Claude service (if we can detect that. team's plan is $150/month, individual plan is $20/month)
- [ ] Option to seamlessly extend the conversation via the API when web interface limits are hit (cost per token, I charge incrementally more than Claude)
- [ ] Feature to run artifacts other than HTML, React, or SVG pages
- [ ] Feature to allow others to continue your conversations / conversation collaboration amongst multiple users
- [ ] Voice mode
- [ ] Interact with local files
- [ ] option to publish websites

### Speech Recognition

- [ ] Allow custom dictionaries for speech recognition
- [ ] If we expose the Speech over websocket, we can use whatever framework for building the UI to potentially make cross platform (e.g., Electron).
  - [ ] If we do that, we can utilize xstate to begin modeling this system more sanely

## Nice to Have

- [ ] Integrate with project management tools (milestones, issues, projects)
- [ ] Implement file change awareness without spamming Claude
- [ ] Implement local intent processing (possibly using Llama 7B or Gemma)
- [ ] Teach Claude how to run commands on local machine and feed back results
- [ ] Allow editing messages
- [ ] Ability to reset transcription
- [ ] Not have to accept microphone permission each time I run transcription via xcode

## Bugs

- [ ] Fix binary data reception in messages
- [ ] Address speech recognition accuracy (e.g., "GitHub" recognized as "GET HUB", "Composable" as "compostable")
