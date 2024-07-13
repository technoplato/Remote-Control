# Project To-Do List

## High Priority

### User Interface

- [ ] Build a user interface that works on iOS and macOS for interacting with Claude website
- [ ] Implement a sliding drawer that follows the text being said (collapsible)
- [ ] Add visual indicator for ongoing response without showing full text
- [ ] Create a locally running chat interface
- [ ] Develop a simple Swift application for better interaction than reading logs

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

### Speech Recognition

- [ ] Allow custom dictionaries for speech recognition

## Currently Working On

- [x] Changing trigger word from "done" to "JINX"
- [x] Debugging message receiving issues

## Next Up

- [ ] Implement local intent processing (possibly using Llama 7B or Gemma)
- [ ] Teach Claude how to run commands on local machine and feed back results

## Nice to Have

- [ ] Integrate with project management tools (milestones, issues, projects)
- [ ] Implement file change awareness without spamming Claude
- [ ] Auto-scroll to bottom of input text in web interface

## Bugs

- [ ] Fix binary data reception in messages
- [ ] Address speech recognition accuracy (e.g., "GitHub" recognized as "GET HUB", "Composable" as "compostable")

## Ongoing Improvements

- [ ] Enhance integration with Claude's capabilities
- [ ] Optimize performance and user experience
