# Local Meeting Recorder

A privacy-first local meeting transcription tool for macOS. Records your meetings and transcribes them locally using MLX Whisper - no data leaves your machine.

## Features

- **Auto-detect Zoom meetings** - Starts recording automatically when you join
- **GPU-accelerated transcription** - Uses MLX Whisper optimized for Apple Silicon
- **Calendar integration** - Names recordings from your calendar events
- **Privacy-first** - Everything runs locally, no cloud services
- **macOS notifications** - Get notified when recording starts/stops

## Requirements

- macOS with Apple Silicon (M1/M2/M3)
- Homebrew
- Python 3.x

## Installation

```bash
# Install dependencies
brew install ffmpeg
pip install mlx-whisper

# Clone the repo
git clone https://github.com/YOUR_USERNAME/meeting-recorder.git
cd meeting-recorder

# Edit the script to set your paths
# Update BASE_DIR, AUDIO_DEVICE as needed

# Make executable
chmod +x record-meeting.sh zoom-watcher.sh

# Install LaunchAgent for auto-start
cp com.local.meeting-recorder.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.local.meeting-recorder.plist
```

## Usage

### Manual Recording
```bash
./record-meeting.sh start    # Start recording
./record-meeting.sh stop     # Stop and transcribe
./record-meeting.sh status   # Check status
```

### Auto Recording
The zoom-watcher runs automatically and detects when you join/leave Zoom meetings.

### Shell Alias
Add to your `~/.zshrc`:
```bash
alias rec="/path/to/record-meeting.sh"
```

## Output Structure

```
meeting/
├── 2024-01-15/
│   ├── team-standup/
│   │   ├── audio.wav
│   │   ├── audio.txt
│   │   ├── audio.srt
│   │   └── audio.vtt
│   └── client-call/
│       └── ...
```

## Configuration

Edit `record-meeting.sh` to customize:

| Setting | Description |
|---------|-------------|
| `BASE_DIR` | Where to save recordings |
| `WHISPER_MODEL` | MLX Whisper model to use |
| `LANGUAGE` | Language for transcription |

## Recommended: System Audio Capture with BlackHole

For reliable transcription, capture system audio directly instead of using your microphone:

### Setup BlackHole

1. Install BlackHole:
   ```bash
   brew install blackhole-2ch
   ```

2. **Reboot your Mac** (required for the audio driver to load)

3. Create a Multi-Output Device:
   - Open **Audio MIDI Setup** (Spotlight → "Audio MIDI Setup")
   - Click **+** → **Create Multi-Output Device**
   - Check both **MacBook Pro Speakers** and **BlackHole 2ch**
   - Rename to "Meeting Audio"

4. Use "Meeting Audio" as your sound output:
   - System Settings → Sound → Output → "Meeting Audio"

The script will automatically detect BlackHole and use it for recording. Check with:
```bash
./record-meeting.sh status
```

## License

MIT
