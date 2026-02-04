import Foundation
import AVFoundation
import ScreenCaptureKit
import WhisperKit

// MARK: - Audio Recorder using ScreenCaptureKit
class SystemAudioRecorder: NSObject, SCStreamDelegate, SCStreamOutput {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var isRecording = false

    func startRecording(to url: URL) async throws {
        outputURL = url

        // Get available content to capture
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // Create a filter - we want audio only, no specific app
        let filter = SCContentFilter(display: content.displays.first!, excludingApplications: [], exceptingWindows: [])

        // Configure the stream for audio capture only
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 16000  // Whisper expects 16kHz
        config.channelCount = 1    // Mono

        // We don't need video
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        // Create and start the stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)

        // Set up audio file
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        audioFile = try AVAudioFile(forWriting: url, settings: audioFormat.settings)

        // Add stream output for audio
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)

        try await stream?.startCapture()
        isRecording = true
        print("✓ Recording started - capturing system audio")
    }

    func stopRecording() async {
        guard isRecording else { return }

        try? await stream?.stopCapture()
        stream = nil
        audioFile = nil
        isRecording = false
        print("✓ Recording stopped")
    }

    // SCStreamOutput delegate - handles audio samples
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let audioFile = audioFile else { return }

        // Convert CMSampleBuffer to AVAudioPCMBuffer and write to file
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        guard let audioFormat = AVAudioFormat(streamDescription: asbd.pointee) else { return }

        let numSamples = sampleBuffer.numSamples
        guard numSamples > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(numSamples)) else {
            return
        }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Copy audio data
        if let blockBuffer = sampleBuffer.dataBuffer {
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

            if let dataPointer = dataPointer, let channelData = pcmBuffer.floatChannelData {
                // Convert to float (assuming 32-bit float input)
                let floatPointer = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: numSamples)
                for i in 0..<numSamples {
                    channelData[0][i] = floatPointer[i]
                }
            }
        }

        try? audioFile.write(from: pcmBuffer)
    }

    // SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Stream stopped with error: \(error)")
    }
}

// MARK: - Zoom Detection
func isZoomInMeeting() -> Bool {
    let runningApps = NSWorkspace.shared.runningApplications
    guard runningApps.contains(where: { $0.bundleIdentifier == "us.zoom.xos" }) else {
        return false
    }

    // Check for CptHost process (Zoom meeting indicator)
    let task = Process()
    task.launchPath = "/usr/bin/pgrep"
    task.arguments = ["-f", "CptHost"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    try? task.run()
    task.waitUntilExit()

    return task.terminationStatus == 0
}

// MARK: - Transcription
func transcribe(audioURL: URL, outputDir: URL) async throws {
    print("📝 Transcribing with WhisperKit...")

    let whisperKit = try await WhisperKit(model: "large-v3-turbo")

    let result = try await whisperKit.transcribe(audioPath: audioURL.path)

    // Save transcript
    let transcriptURL = outputDir.appendingPathComponent("transcript.txt")
    let text = result.map { $0.text }.joined(separator: "\n")
    try text.write(to: transcriptURL, atomically: true, encoding: .utf8)

    print("✓ Transcript saved to: \(transcriptURL.path)")
    print("\n--- Transcript Preview ---")
    print(String(text.prefix(500)))
}

// MARK: - Main
@main
struct MeetingRecorder {
    static func main() async {
        print("🎙️ Meeting Recorder")
        print("━━━━━━━━━━━━━━━━━━━━")

        let args = CommandLine.arguments

        if args.count < 2 {
            print("Usage: MeetingRecorder <start|stop|status|transcribe>")
            return
        }

        let command = args[1]
        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Local Records/meeting")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH-mm-ss"
        let timeStr = timeFormatter.string(from: Date())

        let recorder = SystemAudioRecorder()

        switch command {
        case "start":
            let meetingDir = baseDir
                .appendingPathComponent(dateStr)
                .appendingPathComponent("meeting-\(timeStr)")

            try? FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)

            let audioURL = meetingDir.appendingPathComponent("audio.wav")

            do {
                try await recorder.startRecording(to: audioURL)
                print("Recording to: \(audioURL.path)")
                print("Press Ctrl+C to stop")

                // Keep running until interrupted
                let semaphore = DispatchSemaphore(value: 0)
                signal(SIGINT) { _ in
                    Task {
                        await recorder.stopRecording()
                        exit(0)
                    }
                }
                semaphore.wait()
            } catch {
                print("Error: \(error)")
            }

        case "status":
            if isZoomInMeeting() {
                print("✓ Zoom meeting detected")
            } else {
                print("○ No Zoom meeting")
            }

        case "transcribe":
            if args.count < 3 {
                print("Usage: MeetingRecorder transcribe <audio_file>")
                return
            }
            let audioURL = URL(fileURLWithPath: args[2])
            let outputDir = audioURL.deletingLastPathComponent()

            do {
                try await transcribe(audioURL: audioURL, outputDir: outputDir)
            } catch {
                print("Transcription error: \(error)")
            }

        default:
            print("Unknown command: \(command)")
        }
    }
}
