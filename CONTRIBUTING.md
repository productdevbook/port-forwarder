# Contributing to PortForwarder

Thank you for your interest in contributing to PortForwarder! This document provides guidelines and instructions for contributing.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/productdevbook/port-forwarder/issues)
2. If not, create a new issue with:
   - Clear, descriptive title
   - Steps to reproduce the bug
   - Expected vs actual behavior
   - macOS version and Mac model (Intel/Apple Silicon)
   - Any relevant logs from the Logs tab in Settings

### Suggesting Features

1. Check existing issues for similar suggestions
2. Create a new issue with:
   - Clear description of the feature
   - Use case / why it would be useful
   - Any implementation ideas (optional)

### Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Test your changes thoroughly
5. Commit with clear messages
6. Push to your fork
7. Open a Pull Request

## Development Setup

### Requirements

- macOS 15.0+ (Sequoia)
- Xcode 16+ with Swift 6.0
- Homebrew (for runtime dependencies)

### Building

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/port-forwarder.git
cd port-forwarder

# Debug build
swift build

# Run directly
swift run PortForwarder

# Create app bundle (for notifications support)
./scripts/build-app.sh
open .build/release/PortForwarder.app
```

### Project Structure

```
Sources/
├── PortForwarderApp.swift    # App entry point
├── Managers/                 # Core business logic
│   ├── ConnectionManager.swift
│   ├── ProcessManager.swift
│   ├── ConfigStorage.swift
│   └── ...
├── Models/                   # Data structures
│   └── ConnectionConfig.swift
└── Views/                    # SwiftUI views
    ├── MenuBarView.swift
    └── SettingsView.swift
```

## Code Style

### Swift Guidelines

- Use Swift 6.0 features and strict concurrency
- All UI code should be `@MainActor` isolated
- Use actors for thread-safe managers
- Follow Apple's Swift API Design Guidelines

### Naming Conventions

- Types: `PascalCase`
- Functions/variables: `camelCase`
- Constants: `camelCase`

### Comments

- Write comments in English
- Document public APIs with `///` doc comments
- Use `//` for implementation notes

## Testing

Currently, no automated test framework is configured. Please test your changes manually:

1. Build and run the app
2. Test affected features
3. Verify no regressions in existing functionality
4. Test with different connection configurations

## Questions?

Feel free to open an issue for any questions about contributing.
