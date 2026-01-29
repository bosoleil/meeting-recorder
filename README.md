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
| `AUDIO_DEVICE` | Microphone device number |
| `LANGUAGE` | Language for transcription |

## License

MIT
