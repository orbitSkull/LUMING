# DaPub-Reader Task List

## Phase 1: Project Setup
- [x] Initialize Flutter project
- [x] Set up git repository
- [x] Add required dependencies to pubspec.yaml
- [x] Configure Android permissions for file access
- [x] Create basic folder structure

## Phase 2: Basic UI Implementation
- [x] Create home screen with file picker/button
- [x] Design EPUB reader screen layout
- [x] Implement file selection functionality
- [x] Add basic navigation between screens

## Phase 3: EPUB Reading Integration
- [x] Research and select EPUB parsing library
- [x] Implement EPUB file loading and parsing
- [x] Extract text content from EPUB files
- [x] Display EPUB content in readable format
- [x] Add basic text formatting

## Phase 4: TTS Integration with Piper Plugin
- [x] Add piper_tts_plugin dependency
- [x] Implement voice model loading functionality
- [x] Create TTS synthesis service
- [x] Integrate with EPUB text content
- [x] Add playback controls
- [x] Implement voice selection UI

## Phase 5: Reader Feature Enhancements
- [x] Add settings for speech rate and pitch
- [x] Implement bookmarking/saving reading position
- [x] Implement custom bookmarks
- [x] Implement progress tracking
- [x] Add error handling for unsupported files

## Phase 6: Reader Mode Testing
- [x] Test with various EPUB files
- [x] Ensure proper Android permissions handling
- [x] Test TTS functionality with different voices
- [x] Release build creation

## Phase 7: Writer Mode Setup
- [x] Create dual-mode navigation structure
- [x] Implement mode switcher (Reader/Writer)
- [x] Add Writer footer navigation (5 buttons)
- [x] Create Projects screen
- [x] Create IdeaBox screen
- [x] Create Writer Stats screen
- [x] Create Reader Portal screen
- [x] Create Studio Settings screen

## Phase 8: Writer Features Implementation
- [x] Implement Projects Manager
  - [x] Placeholder screen created
- [x] Implement IdeaBox
  - [x] Placeholder screen created
- [x] Implement Writer Stats
  - [x] Placeholder screen created
- [x] Implement Reader Portal
  - [x] Bridge to Reader Library implemented
- [x] Implement Studio Settings
  - [x] Placeholder screen created
- [ ] Implement Writer Stats
  - [ ] Word count tracking
  - [ ] Daily writing streaks
  - [ ] Velocity metrics
  - [ ] Session timer
  - [ ] Writing goals
- [ ] Implement Reader Portal
  - [ ] Bridge to Reader Library
  - [ ] Your Creations integration
- [ ] Implement Studio Settings
  - [ ] Typewriter Mode
  - [ ] EPUB export presets
  - [ ] Custom dictionaries
  - [ ] Auto-save settings

## Phase 9: Writer Creative Features
- [ ] Auto-save drafts
- [ ] Writing prompts generator
- [ ] Focus mode (distraction-free)
- [ ] Character tracking
- [ ] Timeline view
- [ ] Revision history
- [ ] Export as EPUB
- [ ] Voice typing

## Phase 10: Final Testing
- [ ] Test Writer mode functionality
- [ ] Test mode switching
- [ ] Test export features
- [ ] Performance optimization
- [ ] Bug fixes
- [ ] Final release build

## Writer Mode Footer Structure
```
0: Projects    - File-manager for manuscripts
1: IdeaBox    - Quick-capture scratchpad  
2: Writer Stats - Dashboard for metrics
3: Reader Portal - Return to Reader Library
4: Studio Settings - Typewriter/export settings
```

## Reader Mode Footer Structure
```
0: Library    - EPUB book collection
1: Continue  - Resume last book
2: Stats    - Reading statistics
3: Writer   - Switch to Writer mode
4: Settings - App settings
```