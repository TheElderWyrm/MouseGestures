# Suggested Commands

## Build Commands
```bash
# Build the app
/Users/eldritchbookwyrm/Archive/Claude/MouseGestures\ Project/build.sh

# Clean build
xcodebuild clean -project MouseGestures.xcodeproj -configuration Release

# Build for release
xcodebuild build -project MouseGestures.xcodeproj -scheme MouseGestures -configuration Release -derivedDataPath ./build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## File Management
```bash
# Add file to Xcode project
python3 /Users/eldritchbookwyrm/Archive/Claude/MouseGestures\ Project/add_file_to_xcode.py <file_path>

# Backup project
cp -R /Users/eldritchbookwyrm/Archive/Claude/MouseGestures\ Project/MouseGestures /Users/eldritchbookwyrm/Archive/Claude/Past\ Versions/MouseGestures_backup_$(date +%Y%m%d_%H%M%S)
```

## Logs
```bash
# View app logs
tail -f /Users/eldritchbookwyrm/Library/Logs/MouseGestures/*.log
```

## System Commands (Darwin/macOS)
```bash
# List files
ls -la

# Find files
find . -name "*.swift"

# Search in files
grep -r "pattern" .

# View file
cat filename

# Git operations (if using git)
git status
git add .
git commit -m "message"
```