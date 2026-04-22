//
//  MediaPlaybackService.swift
//  sleep
//
//  Unified facade over the three "fall asleep audio" sources:
//    - Apple Music (MusicKit.ApplicationMusicPlayer)
//    - Podcasts (AVPlayer on the episode URL from PodcastService)
//    - In-app sounds / meditations / stories (delegated to SoundService)
//
//  Exposes a single NowPlaying concept + a sleep timer that fades out and
//  stops, regardless of the underlying source.
//

import AVFoundation
import Foundation
import MusicKit
import os

// MARK: - NowPlaying

struct NowPlayingInfo: Sendable, Equatable {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let source: Source

    enum Source: String, Sendable {
        case appleMusic
        case podcast
        case sound
    }
}

// MARK: - MediaPlaybackService

@Observable
@MainActor
final class MediaPlaybackService {

    // MARK: - Observable state

    var nowPlaying: NowPlayingInfo?
    var isPlaying: Bool = false
    /// Seconds remaining on the sleep timer (0 = no timer).
    var timerRemaining: TimeInterval = 0

    // MARK: - Private

    private var avPlayer: AVPlayer?
    private var avPlayerItem: AVPlayerItem?
    private var countdownTimer: Timer?
    private var fadeTimer: Timer?

    // Reference to the existing SoundService facade so sound/meditation/story
    // playback stays consistent with the Mixer screen.
    weak var soundService: SoundService?

    // MARK: - Apple Music auth

    /// Returns the current MusicKit authorization state. If not determined,
    /// prompts the user. Call before trying to play Apple Music content.
    @MainActor
    func requestAppleMusicAuthorization() async -> MusicAuthorization.Status {
        var status = MusicAuthorization.currentStatus
        if status == .notDetermined {
            status = await MusicAuthorization.request()
        }
        AppLogger.sound.info("🎵 Apple Music authorization: \(String(describing: status))")
        return status
    }

    /// True iff the user is authorized. The subscription check is advisory
    /// only — if Apple's privacy-acknowledgement or subscription lookup
    /// errors, we still let the UI through and let playback-time surface
    /// the real prompt (that's the MusicKit-recommended pattern).
    @MainActor
    func hasAppleMusicAccess() async -> Bool {
        guard MusicAuthorization.currentStatus == .authorized else { return false }
        do {
            let subscription = try await MusicSubscription.current
            return subscription.canPlayCatalogContent
        } catch {
            AppLogger.sound.info("🎵 Subscription check deferred — \(error.localizedDescription). Proceeding with authorization = true.")
            // Don't block the UI on this. First-launch users need to see
            // search / pickers so MusicKit can present the privacy prompt
            // when they actually try to play.
            return true
        }
    }

    // MARK: - Play: Apple Music

    /// Queue and play an Apple Music item (song, album, playlist). Preserves
    /// the user's system Music app state (uses ApplicationMusicPlayer).
    @MainActor
    func playAppleMusic<Item: PlayableMusicItem>(
        _ item: Item,
        title: String,
        subtitle: String,
        artworkURL: URL?,
        timerMinutes: Int
    ) async {
        stop()
        let player = ApplicationMusicPlayer.shared
        player.queue = [item]
        do {
            try await player.prepareToPlay()
            try await player.play()
            nowPlaying = NowPlayingInfo(
                title: title,
                subtitle: subtitle,
                artworkURL: artworkURL,
                source: .appleMusic
            )
            isPlaying = true
            AppLogger.sound.info("🎵 Apple Music started — \(title)")
            startSleepTimer(minutes: timerMinutes)
        } catch {
            AppLogger.sound.error("🎵 Apple Music playback failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Play: Podcast

    /// Stream a podcast episode via AVPlayer.
    @MainActor
    func playPodcast(_ episode: PodcastEpisode, timerMinutes: Int) {
        stop()
        let item = AVPlayerItem(url: episode.audioURL)
        let player = AVPlayer(playerItem: item)
        player.volume = 1.0
        player.play()
        avPlayer = player
        avPlayerItem = item
        nowPlaying = NowPlayingInfo(
            title: episode.title,
            subtitle: episode.showName,
            artworkURL: episode.artworkURL,
            source: .podcast
        )
        isPlaying = true
        AppLogger.sound.info("🎙️ Podcast started — \(episode.title)")
        startSleepTimer(minutes: timerMinutes)
    }

    // MARK: - Play: Sound / Meditation / Story

    /// Play an in-app SoundItem via the existing SoundService.
    /// Handles both file-backed (rain, ocean) and TTS-backed (meditations, stories).
    @MainActor
    func playSound(_ sound: SoundItem, timerMinutes: Int) {
        stop()
        guard let soundService = soundService else {
            AppLogger.sound.error("🎙️ MediaPlaybackService: no SoundService attached")
            return
        }
        soundService.addSound(sound)
        soundService.play(timerMinutes: 0) // we own the timer here
        nowPlaying = NowPlayingInfo(
            title: sound.name,
            subtitle: sound.category.rawValue,
            artworkURL: nil,
            source: .sound
        )
        isPlaying = true
        AppLogger.sound.info("🎙️ Sound started — \(sound.name)")
        startSleepTimer(minutes: timerMinutes)
    }

    // MARK: - Stop / Timer

    @MainActor
    func stop() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        fadeTimer?.invalidate()
        fadeTimer = nil
        timerRemaining = 0

        if let source = nowPlaying?.source {
            switch source {
            case .appleMusic:
                ApplicationMusicPlayer.shared.stop()
            case .podcast:
                avPlayer?.pause()
                avPlayer = nil
                avPlayerItem = nil
            case .sound:
                soundService?.stopAndClear()
            }
        }

        nowPlaying = nil
        isPlaying = false
        AppLogger.sound.info("🎙️ MediaPlaybackService stopped")
    }

    /// 0 or negative → no timer (play until user stops).
    private func startSleepTimer(minutes: Int) {
        countdownTimer?.invalidate()
        guard minutes > 0 else {
            timerRemaining = 0
            return
        }
        timerRemaining = TimeInterval(minutes * 60)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.timerRemaining -= 1
                if self.timerRemaining <= 0 {
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    await self.fadeOutAndStop(duration: 5)
                }
            }
        }
    }

    /// Step counter for the fade-out timer. Hoisted to an instance property
    /// so the Timer's `@Sendable` block doesn't have to capture a local
    /// `var step` (Swift 6 forbids mutating captured-var across actors).
    private var fadeStep: Int = 0

    /// Linear volume ramp to 0 over `duration` seconds, then stop.
    @MainActor
    private func fadeOutAndStop(duration: TimeInterval) async {
        let steps = 20
        let stepInterval = duration / Double(steps)
        fadeStep = 0
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fadeStep += 1
                let fraction = Float(1.0 - Double(self.fadeStep) / Double(steps))
                if let source = self.nowPlaying?.source {
                    switch source {
                    case .appleMusic:
                        // MusicKit doesn't expose volume; rely on stop() at step 20.
                        break
                    case .podcast:
                        self.avPlayer?.volume = max(0, fraction)
                    case .sound:
                        // SoundService handles its own fade when timer hits 0;
                        // we just stop it at the end below.
                        break
                    }
                }
                if self.fadeStep >= steps {
                    self.fadeTimer?.invalidate()
                    self.fadeTimer = nil
                    self.stop()
                }
            }
        }
    }
}
