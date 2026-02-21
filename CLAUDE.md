# KGB (Known Good Build)

macOS menu bar app.

## xcodebuild (verified 2026-02-21)

### Build Commands
```bash
xcodebuild build -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift
```

### Test Commands
```bash
# All tests
xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' 2>&1 | xcsift

# Single test class
xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' -only-testing:KGBTests/<TestClass> 2>&1 | xcsift

# Single test method
xcodebuild test -project KGB/KGB.xcodeproj -scheme "KGB" -destination 'platform=macOS' -only-testing:KGBTests/<TestClass>/<testMethod> 2>&1 | xcsift
```
