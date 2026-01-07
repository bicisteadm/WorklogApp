- [x] Verify that the copilot-instructions.md file in the .github directory is created. (hotovo)

- [x] Clarify Project Requirements (macOS SwiftUI, SwiftData perzistence, logování času)

- [x] Scaffold the Project (Xcode projekt, SwiftUI pohledy, modely)

- [x] Customize the Project (přechod na SwiftData, úprava UI datových vazeb)

- [x] Install Required Extensions (není potřeba)

- [ ] Compile the Project

- [ ] Create and Run Task

- [ ] Launch the Project

- [ ] Ensure Documentation is Complete

## Development Guidelines

- **Code Language**: All code comments, variable names, function names, and documentation must be written in English. This ensures consistency and maintainability across the codebase.

- **Testing**: Write corresponding tests for every new feature or code change:
  - Unit tests for business logic (models, relationships, data operations)
  - UI tests for user interactions (when feasible on the platform)
  - Tests must cover both basic scenarios (happy path) and edge cases
  - Run tests before committing: `xcodebuild test -scheme WorklogApp -destination 'platform=macOS'`

- Work through each checklist item systematically.
- Keep communication concise and focused.
- Follow development best practices.
