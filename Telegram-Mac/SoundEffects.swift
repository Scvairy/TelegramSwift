//
//  SoundEffects.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 10.01.2020.
//  Copyright © 2020 Telegram. All rights reserved.
//

import Cocoa
import AudioToolbox
import AVFoundation
import Accelerate

enum SoundEffect {
    case quizCorrect
    case quizIncorrect
    case confetti
    case sent
    var name: String {
        switch self {
        case .quizCorrect:
            return "quiz-correct"
        case .quizIncorrect:
            return "quiz-incorrect"
        case .confetti:
            return "confetti"
        case .sent:
            return "sent"
        }
    }
    var ext: String {
        switch self {
        case .quizCorrect, .quizIncorrect, .confetti, .sent:
            return "mp3"
        }
    }
}


func playSoundEffect(_ sound: SoundEffect) {
    if let p = Bundle.main.path(forResource: sound.name, ofType: sound.ext), SystemSoundEffect.play(path: p, volume: 0.1) {
        return
    }
    let afterSentSound:NSSound? = {
        
        let p = Bundle.main.path(forResource: sound.name, ofType: sound.ext)
        var sound:NSSound?
        if let p = p {
            sound = NSSound(contentsOfFile: p, byReference: true)
            sound?.volume = 0.1
        }
        
        return sound
    }()
    afterSentSound?.play()
}

// Short effects are played through System Sound Services instead of NSSound/MediaPlayer.
// Those open a regular audio session, which macOS treats as media playback: when AirPods
// are connected to an iPhone that is playing something, Automatic Switching moves them to
// the Mac just to play a sent-message or notification sound. System sounds don't take part
// in that arbitration. They have no volume control, so the volume is baked into a cached copy.
final class SystemSoundEffect {
    private static var cache: [String: SystemSoundID] = [:]

    static func play(path: String, volume: Float) -> Bool {
        let key = "\(path)#\(volume)"
        if let soundId = cache[key] {
            AudioServicesPlaySystemSound(soundId)
            return true
        }
        guard let url = prepare(path: path, volume: volume) else {
            return false
        }
        var soundId: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &soundId) == noErr else {
            return false
        }
        // play even if "Play user interface sound effects" is turned off, as NSSound did
        var isUISound: UInt32 = 0
        AudioServicesSetProperty(kAudioServicesPropertyIsUISound, UInt32(MemoryLayout<SystemSoundID>.size), &soundId, UInt32(MemoryLayout<UInt32>.size), &isUISound)
        cache[key] = soundId
        AudioServicesPlaySystemSound(soundId)
        return true
    }

    private static func prepare(path: String, volume: Float) -> URL? {
        do {
            let input = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            let format = input.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length)) else {
                return nil
            }
            try input.read(into: buffer)
            if volume != 1, let channels = buffer.floatChannelData {
                var gain = volume
                for channel in 0 ..< Int(format.channelCount) {
                    vDSP_vsmul(channels[channel], 1, &gain, channels[channel], 1, vDSP_Length(buffer.frameLength))
                }
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sound-effects", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
            var settings = format.settings
            settings[AVLinearPCMIsNonInterleaved] = false
            let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            try output.write(from: buffer)
            return url
        } catch {
            return nil
        }
    }
}
