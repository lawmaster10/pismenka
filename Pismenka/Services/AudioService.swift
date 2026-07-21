//
//  AudioService.swift
//  Pismenka
//
//  Audio playback service for letters and sound effects
//  Optimized with caching, preloading, and asset validation
//

import Foundation
import AVFoundation
import Combine
import UIKit

private enum AudioAssetLocation {
    static let root = "Sounds"
    static let letters = "Sounds/Letters"
    static let numbers = "Sounds/Numbers"
    static let cermakLetters = "Sounds/PersonalizedLetters/Cermak"
    static let blends = "Sounds/Blends"

    static func subdirectories(for filename: String, type: String, usePersonalizedCzechLetters: Bool) -> [String?] {
        guard type == "m4a" else { return [root, nil] }

        if filename.hasPrefix("cz_blend_") {
            return [blends, root, nil]
        }

        if isNumberAsset(filename) {
            return [numbers, root, nil]
        }

        if isCzechLetterAsset(filename), usePersonalizedCzechLetters {
            return [cermakLetters, letters, root, nil]
        }

        if filename.hasPrefix("en_") || isCzechLetterAsset(filename) {
            return [letters, root, nil]
        }

        return [root, nil]
    }

    /// Number voice clips: `en_0`…`en_100` / `cz_0`…`cz_100` (matches
    /// `^(en|cz)_[0-9]{1,3}$` with the value capped at 100).
    static func isNumberAsset(_ filename: String) -> Bool {
        for prefix in ["en_", "cz_"] where filename.hasPrefix(prefix) {
            let digits = filename.dropFirst(prefix.count)
            guard (1...3).contains(digits.count),
                  digits.allSatisfy({ $0.isASCII && $0.isWholeNumber }),
                  let value = Int(digits),
                  (0...100).contains(value) else {
                return false
            }
            return true
        }
        return false
    }

    private static func isCzechLetterAsset(_ filename: String) -> Bool {
        filename.hasPrefix("cz_")
            && !isNumberAsset(filename)
            && !filename.hasPrefix("cz_syl_")
            && !filename.hasPrefix("cz_blend_")
            && !filename.hasPrefix("cz_word_")
    }
}

/// Word forms for the 0…100 number curriculum, used as the TTS fallback when
/// a bundled number clip is missing. Speech synthesizers read bare digit
/// strings unreliably (e.g. "26" as "two six"), so the fallback always feeds
/// the full spoken form. Mirrors `NUMBER_SPOKEN_FORMS` in
/// `generate_audio_assets.py`.
enum NumberSpokenForm {
    private static let englishOnes = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen"
    ]

    private static let englishTens: [Int: String] = [
        2: "twenty", 3: "thirty", 4: "forty", 5: "fifty",
        6: "sixty", 7: "seventy", 8: "eighty", 9: "ninety"
    ]

    /// Czech counting forms: feminine "jedna"/"dvě" (never "jeden"/"dva"),
    /// as used when counting aloud with children.
    private static let czechOnes = [
        "nula", "jedna", "dvě", "tři", "čtyři", "pět", "šest", "sedm", "osm", "devět",
        "deset", "jedenáct", "dvanáct", "třináct", "čtrnáct", "patnáct", "šestnáct",
        "sedmnáct", "osmnáct", "devatenáct"
    ]

    private static let czechTens: [Int: String] = [
        2: "dvacet", 3: "třicet", 4: "čtyřicet", 5: "padesát",
        6: "šedesát", 7: "sedmdesát", 8: "osmdesát", 9: "devadesát"
    ]

    static func spokenForm(for key: String, language: GameLanguage) -> String? {
        guard let value = Int(key), (0...100).contains(value) else { return nil }
        switch language.resolvedLanguage {
        case .czech:
            return czech(value)
        case .english, .system:
            return english(value)
        }
    }

    static func english(_ value: Int) -> String? {
        guard (0...100).contains(value) else { return nil }
        if value == 100 { return "one hundred" }
        if value < 20 { return englishOnes[value] }
        let tens = englishTens[value / 10]!
        let ones = value % 10
        return ones == 0 ? tens : "\(tens)-\(englishOnes[ones])"
    }

    static func czech(_ value: Int) -> String? {
        guard (0...100).contains(value) else { return nil }
        if value == 100 { return "sto" }
        if value < 20 { return czechOnes[value] }
        let tens = czechTens[value / 10]!
        let ones = value % 10
        return ones == 0 ? tens : "\(tens) \(czechOnes[ones])"
    }
}

private func resolveBundledAudioURL(
    filename: String,
    type: String,
    bundle: Bundle = .main,
    usePersonalizedCzechLetters: Bool = false
) -> URL? {
    for subdirectory in AudioAssetLocation.subdirectories(
        for: filename,
        type: type,
        usePersonalizedCzechLetters: usePersonalizedCzechLetters
    ) {
        if let url = bundle.url(forResource: filename, withExtension: type, subdirectory: subdirectory) {
            return url
        }
    }
    return nil
}

@MainActor
class AudioService: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    static let shared = AudioService()
    
    // MARK: - Cached Players & URLs
    
    /// Cache of prepared AVAudioPlayers by filename (e.g., "sfx_correct", "en_a")
    private var playerCache: [String: AVAudioPlayer] = [:]
    
    /// Cache of resolved URLs to avoid repeated bundle lookups
    private var urlCache: [String: URL] = [:]
    
    /// Currently playing voice player (for delegate tracking)
    private var activeVoicePlayer: AVAudioPlayer?
    
    /// Currently playing SFX player
    private var activeSfxPlayer: AVAudioPlayer?

    /// Dedicated player for the Winner celebration "Wow!" clip. Kept off the
    /// regular voice channel so that prompt cancellation logic in `playSound`
    /// does not interrupt the celebration mid-flight, and so the celebration
    /// can deliberately overlap a queued applause SFX.
    private var activeCelebrationVoicePlayer: AVAudioPlayer?

    /// Pending dispatch for the applause leg of the Winner celebration. Keeps
    /// a handle so `stop()` can cancel it if the session ends early.
    private var winnerApplauseTask: Task<Void, Never>?

    /// Last-resort voice playback when bundled letter files are missing.
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var activeSpeechUtterance: AVSpeechUtterance?
    private var usePersonalizedCzechLetters = false
    
    @Published var lastPlaybackFailed: Bool = false
    @Published var missingAssets: [String] = []

    private var isSessionActive: Bool = false
    
    /// Pending action to execute after current voice audio finishes
    private var pendingVoiceCompletion: (() -> Void)?
    private var pendingSpeechCompletion: (() -> Void)?
    
    /// SFX filenames to preload
    private let sfxFiles = [
        "sfx_correct",
        "sfx_wrong",
        "sfx_streak_5",
        "sfx_streak_10",
        "sfx_click",
        "sfx_applause"
    ]

    /// Single recorded "Wow!" clip used for every Winner celebration,
    /// regardless of the child's profile language. The exclamation reads
    /// as universally celebratory and avoids the awkward Czech tail-overlap
    /// the per-language version had.
    private let winnerCelebrationVoiceFile = "sfx_wow_en"

    /// Delay between the start of the spoken celebration and the start of
    /// the applause clip. Tuned so the applause begins under the tail of
    /// "Wow!" the way a real crowd would react.
    private let winnerApplauseLeadInSeconds: Double = 0.55
    
    private override init() {
        super.init()
        speechSynthesizer.delegate = self
        setupAudioSession()
        setupNotificationHandling()
    }

    func setPersonalizedCzechLettersEnabled(_ enabled: Bool) {
        guard usePersonalizedCzechLetters != enabled else { return }
        usePersonalizedCzechLetters = enabled
        resetPlaybackObjects()
        urlCache.removeAll()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    private func setupNotificationHandling() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesWereReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
        center.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Audio interrupted (phone call, etc.)
            stop()
            isSessionActive = false
        case .ended:
            // The next playback should rebuild the session state. Some
            // interruptions end without `.shouldResume`, but prompts are
            // always user/app initiated here rather than continuous media.
            isSessionActive = false
            setupAudioSession()
        @unknown default:
            break
        }
    }

    @objc private func handleMediaServicesWereReset(notification: Notification) {
        resetPlaybackObjects()
        isSessionActive = false
        setupAudioSession()
    }

    @objc private func handleAppDidBecomeActive(notification: Notification) {
        // iOS can suspend/deactivate audio after lock or a long idle period
        // without our cached flag reflecting the real AVAudioSession state.
        // Drop prepared players so the next prompt uses fresh audio objects.
        resetPlaybackObjects()
        isSessionActive = false
        setupAudioSession()
    }

    @objc private func handleAppWillResignActive(notification: Notification) {
        isSessionActive = false
    }
    
    // MARK: - Asset Validation
    
    /// Validate all expected audio assets exist at launch. Call from app init.
    func validateAssets(for languages: [GameLanguage] = [.english, .czech]) {
        let missing = missingAssetNames(for: languages)
        if !missing.isEmpty {
            print("⚠️ Missing audio assets: \(missing)")
            DispatchQueue.main.async {
                self.missingAssets = missing
            }
        } else {
            debugAudioLog("✅ All audio assets validated")
            DispatchQueue.main.async {
                self.missingAssets = []
            }
        }
    }

    func missingAssetNames(for languages: [GameLanguage] = [.english, .czech]) -> [String] {
        var missing: [String] = []
        for sfx in sfxFiles where resolveURL(filename: sfx, type: "mp3") == nil {
            missing.append("\(sfx).mp3")
        }
        if resolveURL(filename: winnerCelebrationVoiceFile, type: "m4a") == nil {
            missing.append("\(winnerCelebrationVoiceFile).m4a")
        }
        for lang in languages {
            let prefix = lang.audioPrefix
            for letter in lang.letters {
                let filename = "\(prefix)_\(audioKey(for: letter))"
                if resolveURL(filename: filename, type: "m4a") == nil {
                    missing.append("\(filename).m4a")
                }
            }
            for asset in requiredCurriculumVoiceAssets(for: lang) where resolveURL(filename: asset, type: "m4a") == nil {
                missing.append("\(asset).m4a")
            }
        }
        return missing.sorted()
    }
    
    // MARK: - Preloading

    /// Preload without monopolizing the main actor during screen transitions.
    func preloadLazily(language: GameLanguage? = nil) async {
        for asset in preloadAssets(language: language) {
            guard !Task.isCancelled else { return }
            preloadSound(filename: asset.filename, type: asset.type)
            await Task.yield()
        }

        debugAudioLog("🎵 Preloaded \(playerCache.count) audio players")
    }

    private func preloadAssets(language: GameLanguage?) -> [(filename: String, type: String)] {
        var assets = sfxFiles.map { (filename: $0, type: "mp3") }
        assets.append((filename: winnerCelebrationVoiceFile, type: "m4a"))
        if let lang = language {
            let prefix = lang.audioPrefix
            assets += lang.letters.map { (filename: "\(prefix)_\(audioKey(for: $0))", type: "m4a") }
            assets += requiredCurriculumVoiceAssets(for: lang).map { (filename: $0, type: "m4a") }
        }
        return assets
    }
    
    private func preloadSound(filename: String, type: String) {
        let key = "\(filename).\(type)"
        guard playerCache[key] == nil else { return }
        
        guard let url = resolveURL(filename: filename, type: type) else { return }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            playerCache[key] = player
        } catch {
            print("⚠️ Failed to preload \(key): \(error)")
        }
    }

    func preloadPrompt(for activity: LearningActivityKind, target: FocusTarget, language: GameLanguage) {
        switch (activity, target) {
        case (_, .letter(let letter)):
            preloadSound(filename: "\(language.audioPrefix)_\(audioKey(for: letter))", type: "m4a")
        case (.syllableBlending, .syllable(let syllable)):
            preloadSound(filename: "\(language.audioPrefix)_blend_\(audioKey(for: syllable))", type: "m4a")
        case (_, .syllable(let syllable)):
            preloadSound(filename: "\(language.audioPrefix)_syl_\(audioKey(for: syllable))", type: "m4a")
        case (.syllableSegmenting, .word(let word)), (.wordBuilding, .word(let word)):
            preloadSound(filename: "\(language.audioPrefix)_word_\(audioKey(for: word))_slabikované", type: "m4a")
        case (_, .word(let word)):
            preloadSound(filename: "\(language.audioPrefix)_word_\(audioKey(for: word))", type: "m4a")
        case (_, .number(let number)):
            preloadSound(filename: "\(language.audioPrefix)_\(number)", type: "m4a")
        }
    }
    
    // MARK: - URL Resolution (Cached)
    
    private func resolveURL(filename: String, type: String) -> URL? {
        let key = "\(filename).\(type)"
        
        if let cached = urlCache[key] {
            return cached
        }
        
        let url = resolveBundledAudioURL(
            filename: filename,
            type: type,
            usePersonalizedCzechLetters: usePersonalizedCzechLetters
        )
        
        if let url = url {
            urlCache[key] = url
        }
        
        return url
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if player === activeVoicePlayer, let completion = pendingVoiceCompletion {
                pendingVoiceCompletion = nil
                completion()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.finishSpeechFallbackIfActive(utterance)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.finishSpeechFallbackIfActive(utterance)
        }
    }

    private func finishSpeechFallbackIfActive(_ utterance: AVSpeechUtterance) {
        guard utterance === activeSpeechUtterance else { return }
        activeSpeechUtterance = nil
        let completion = pendingSpeechCompletion
        pendingSpeechCompletion = nil
        completion?()
    }
    
    // MARK: - Letter Audio
    
    /// Play letter sound for given language
    /// Format: {lang}_{letter}.m4a (e.g., en_a.m4a, cz_a.m4a)
    func playLetter(_ letter: String, language: GameLanguage) {
        debugAudioLog("🎵 playLetter called: letter=\(letter), language=\(language)")
        let lang = language.audioPrefix
        let filename = "\(lang)_\(audioKey(for: letter))"
        debugAudioLog("🎵 Will play filename: \(filename)")
        
        playSound(
            filename: filename,
            type: "m4a",
            isVoice: true,
            fallbackSpeech: spokenLetter(for: letter),
            fallbackLanguage: language
        )
    }

    /// Slowed replay for the listen-again long press. Uses AVAudioPlayer.rate
    /// with `enableRate = true`; normal playback always resets rate to 1.0.
    func playLetterSlow(_ letter: String, language: GameLanguage, rate: Float = 0.7) {
        debugAudioLog("🎵 playLetterSlow called: letter=\(letter), language=\(language), rate=\(rate)")
        let lang = language.audioPrefix
        let filename = "\(lang)_\(audioKey(for: letter))"
        playSound(
            filename: filename,
            type: "m4a",
            isVoice: true,
            fallbackSpeech: spokenLetter(for: letter),
            fallbackLanguage: language,
            rate: rate
        )
    }

    private func audioKey(for letter: String) -> String {
        let base = letter.hasSuffix("|lower")
            ? String(letter.dropLast("|lower".count))
            : letter
        return base.lowercased()
    }

    func hasSyllableAssets(_ syllable: String, language: GameLanguage) -> Bool {
        let prefix = language.audioPrefix
        return resolveURL(filename: "\(prefix)_syl_\(audioKey(for: syllable))", type: "m4a") != nil
            && resolveURL(filename: "\(prefix)_blend_\(audioKey(for: syllable))", type: "m4a") != nil
    }

    func spokenLetter(for letter: String) -> String {
        if letter.hasSuffix("|lower") {
            return String(letter.dropLast("|lower".count)).lowercased()
        }
        return letter
    }

    // MARK: - Number Audio

    /// Play the number prompt for the given language.
    /// Format: {lang}_{number}.m4a (e.g., en_26.m4a, cz_26.m4a) resolved from
    /// Sounds/Numbers. On a missing bundled clip, falls back to TTS with the
    /// full word form ("twenty-six" / "dvacet šest") — never the digit string.
    func playNumber(_ key: String, language: GameLanguage) {
        debugAudioLog("🎵 playNumber called: number=\(key), language=\(language)")
        let filename = "\(language.audioPrefix)_\(key)"
        playSound(
            filename: filename,
            type: "m4a",
            isVoice: true,
            fallbackSpeech: NumberSpokenForm.spokenForm(for: key, language: language),
            fallbackLanguage: language
        )
    }

    /// Soft diagnostic for number voice clips. Deliberately kept out of
    /// `missingAssetNames` — missing number audio degrades to the spoken-word
    /// TTS fallback rather than hard-gating launch validation.
    func missingNumberAssetNames(for languages: [GameLanguage] = [.english, .czech]) -> [String] {
        var missing: [String] = []
        for lang in languages {
            let prefix = lang.audioPrefix
            for number in NumberDifficulty.allNumbers {
                let filename = "\(prefix)_\(number)"
                if resolveURL(filename: filename, type: "m4a") == nil {
                    missing.append("\(filename).m4a")
                }
            }
        }
        return missing.sorted()
    }

    // MARK: - Syllable and Word Audio

    func playSyllable(_ syllable: String, language: GameLanguage) {
        playSound(
            filename: "\(language.audioPrefix)_syl_\(audioKey(for: syllable))",
            type: "m4a",
            isVoice: true
        )
    }

    func playSyllableBlend(_ syllable: String, language: GameLanguage) {
        playSound(
            filename: "\(language.audioPrefix)_blend_\(audioKey(for: syllable))",
            type: "m4a",
            isVoice: true
        )
    }

    func playWord(_ word: String, language: GameLanguage) {
        playSound(
            filename: "\(language.audioPrefix)_word_\(audioKey(for: word))",
            type: "m4a",
            isVoice: true
        )
    }

    func playWordSegmented(_ word: String, language: GameLanguage) {
        playSound(
            filename: "\(language.audioPrefix)_word_\(audioKey(for: word))_slabikované",
            type: "m4a",
            isVoice: true
        )
    }

    func playPrompt(for activity: LearningActivityKind, target: FocusTarget, language: GameLanguage) {
        switch (activity, target) {
        case (_, .letter(let letter)):
            playFindPrompt(letter: letter, language: language)
        case (.syllableBlending, .syllable(let syllable)):
            playSyllableBlend(syllable, language: language)
        case (.syllableCalibration, .syllable(let syllable)):
            playSyllable(syllable, language: language)
        case (_, .syllable(let syllable)):
            playSyllable(syllable, language: language)
        case (.syllableSegmenting, .word(let word)), (.wordBuilding, .word(let word)):
            playWordSegmented(word, language: language)
        case (_, .word(let word)):
            playWord(word, language: language)
        case (_, .number(let number)):
            playNumber(number, language: language)
        }
    }

    func requiredCurriculumVoiceAssets(for language: GameLanguage) -> [String] {
        _ = language
        return []
    }
    
    // MARK: - Sound Effects
    
    func playCorrect() {
        playSound(filename: "sfx_correct", type: "mp3", isVoice: false)
    }
    
    func playWrong() {
        playSound(filename: "sfx_wrong", type: "mp3", isVoice: false)
    }
    
    func playStreak5() {
        playSound(filename: "sfx_streak_5", type: "mp3", isVoice: false)
    }
    
    func playStreak10() {
        playSound(filename: "sfx_streak_10", type: "mp3", isVoice: false)
    }
    
    func playClick() {
        playSound(filename: "sfx_click", type: "mp3", isVoice: false)
    }

    func playApplause() {
        playSound(filename: "sfx_applause", type: "mp3", isVoice: false)
    }

    /// Two-clip Winner celebration: a recorded "Wow!" voice clip, then the
    /// applause clip starting partway through the voice tail so the crowd
    /// reaction feels natural. The same English "Wow!" plays for every
    /// profile language — it reads as universally celebratory.
    ///
    /// `language` is currently unused but kept on the signature so future
    /// per-language variants (e.g. "Yay!" / "Hurá!") can be reintroduced
    /// without changing call sites in `GameView`. Uses `Task.sleep` for the
    /// lead-in instead of chaining off an `AVAudioPlayerDelegate` callback
    /// because the voice clip is decoupled from the regular voice channel —
    /// the applause must start on a fixed schedule even if the voice clip
    /// is shorter or longer than expected.
    func playWinnerCelebration(language: GameLanguage = .english) {
        _ = language
        winnerApplauseTask?.cancel()

        playCelebrationVoice(filename: winnerCelebrationVoiceFile)

        let leadIn = winnerApplauseLeadInSeconds
        winnerApplauseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(leadIn * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.playApplause()
            }
        }
    }

    private func playCelebrationVoice(filename: String) {
        ensureAudioSessionActive()
        let key = "\(filename).m4a"

        if let cachedPlayer = playerCache[key] {
            cachedPlayer.currentTime = 0
            cachedPlayer.enableRate = true
            cachedPlayer.rate = 1.0
            cachedPlayer.delegate = nil
            if cachedPlayer.play() {
                activeCelebrationVoicePlayer = cachedPlayer
                lastPlaybackFailed = false
                return
            }
            cachedPlayer.stop()
            playerCache[key] = nil
            isSessionActive = false
            ensureAudioSessionActive()
        }

        guard let url = resolveURL(filename: filename, type: "m4a") else {
            print("❌ Celebration voice file missing: \(key)")
            lastPlaybackFailed = true
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = 1.0
            player.prepareToPlay()
            playerCache[key] = player
            if player.play() {
                activeCelebrationVoicePlayer = player
                lastPlaybackFailed = false
            } else {
                lastPlaybackFailed = true
            }
        } catch {
            print("❌ Celebration voice playback failed: \(error)")
            lastPlaybackFailed = true
        }
    }
    
    // MARK: - Playback (Optimized with Cache)
    
    private func playSound(
        filename: String,
        type: String,
        isVoice: Bool,
        completion: (() -> Void)? = nil,
        fallbackSpeech: String? = nil,
        fallbackLanguage: GameLanguage? = nil,
        rate: Float = 1.0
    ) {
        debugAudioLog("🔊 Attempting to play: \(filename).\(type)")
        ensureAudioSessionActive()
        
        // Cancel any pending completion if starting new voice audio
        if isVoice {
            pendingVoiceCompletion = nil
            pendingSpeechCompletion = nil
            activeSpeechUtterance = nil
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let key = "\(filename).\(type)"
        
        // Try to use cached player
        if let cachedPlayer = playerCache[key] {
            cachedPlayer.currentTime = 0 // Reset to beginning
            cachedPlayer.enableRate = true
            cachedPlayer.rate = rate
            cachedPlayer.delegate = self
            let success = cachedPlayer.play()
            debugAudioLog("▶️ Playing from cache, success: \(success), duration: \(cachedPlayer.duration)s")

            if success {
                if isVoice {
                    activeVoicePlayer = cachedPlayer
                    pendingVoiceCompletion = completion
                } else {
                    activeSfxPlayer = cachedPlayer
                }

                lastPlaybackFailed = false
                return
            }

            cachedPlayer.stop()
            cachedPlayer.delegate = nil
            playerCache[key] = nil
            isSessionActive = false
            ensureAudioSessionActive()
        }
        
        // No cached player - resolve URL and create new player
        guard let url = resolveURL(filename: filename, type: type) else {
            print("❌ Audio file not found in bundle: \(filename).\(type)")
            if isVoice, let fallbackSpeech, let fallbackLanguage {
                speakFallback(fallbackSpeech, language: fallbackLanguage, rate: rate, completion: completion)
                lastPlaybackFailed = false
                return
            }
            lastPlaybackFailed = true
            completion?()
            return
        }
        
        debugAudioLog("✅ Found file at: \(url.path)")
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            
            // Cache the player for future use
            playerCache[key] = player
            
            let success = player.play()
            debugAudioLog("▶️ Play called, success: \(success), duration: \(player.duration)s")
            
            if isVoice {
                activeVoicePlayer = player
                pendingVoiceCompletion = completion
            } else {
                activeSfxPlayer = player
            }
            
            lastPlaybackFailed = !success
            if !success { completion?() }
        } catch {
            print("❌ Audio playback failed: \(error)")
            lastPlaybackFailed = true
            completion?()
        }
    }
    
    // MARK: - Voice Prompt
    
    /// Play the letter prompt (previously played "Find..." prefix but removed due to choppy audio)
    func playFindPrompt(letter: String, language: GameLanguage) {
        debugAudioLog("🎵 playFindPrompt called: letter=\(letter), language=\(language)")
        // Just play the letter directly - "Find..." prefix removed
        playLetter(letter, language: language)
    }
    
    func stop() {
        pendingVoiceCompletion = nil
        pendingSpeechCompletion = nil
        activeSpeechUtterance = nil
        winnerApplauseTask?.cancel()
        winnerApplauseTask = nil
        activeVoicePlayer?.stop()
        activeSfxPlayer?.stop()
        activeCelebrationVoicePlayer?.stop()
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    private func resetPlaybackObjects() {
        pendingVoiceCompletion = nil
        pendingSpeechCompletion = nil
        activeSpeechUtterance = nil
        winnerApplauseTask?.cancel()
        winnerApplauseTask = nil
        activeVoicePlayer?.stop()
        activeSfxPlayer?.stop()
        activeCelebrationVoicePlayer?.stop()
        for player in playerCache.values {
            player.stop()
            player.delegate = nil
        }
        playerCache.removeAll()
        activeVoicePlayer = nil
        activeSfxPlayer = nil
        activeCelebrationVoicePlayer = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.delegate = nil
        speechSynthesizer = AVSpeechSynthesizer()
        speechSynthesizer.delegate = self
    }

    private func speakFallback(_ text: String, language: GameLanguage, rate: Float, completion: (() -> Void)?) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: speechLanguageCode(for: language))
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * rate, 0.1), 0.6)
        activeSpeechUtterance = utterance
        pendingSpeechCompletion = completion
        speechSynthesizer.speak(utterance)
        debugAudioLog("🗣️ Falling back to system speech for: \(text)")
    }

    private func speechLanguageCode(for language: GameLanguage) -> String {
        switch language.resolvedLanguage {
        case .english:
            return "en-US"
        case .czech:
            return "cs-CZ"
        case .system:
            return "en-US"
        }
    }

    private func ensureAudioSessionActive() {
        guard !isSessionActive else { return }
        do {
            setupAudioSession()
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            isSessionActive = true
        } catch {
            isSessionActive = false
            print("Audio session activation failed: \(error)")
        }
    }

    private func debugAudioLog(_ message: String) {
        #if DEBUG_AUDIO_LOGS
        print(message)
        #endif
    }
}

extension AudioService: CurriculumAudioAvailability {
    nonisolated func hasSyllableAudio(_ key: String, language: GameLanguage) -> Bool {
        let audioKey = key.folding(options: .diacriticInsensitive, locale: Locale(identifier: "cs_CZ")).lowercased()
        let prefix = language.audioPrefix
        func resolve(_ filename: String) -> URL? { resolveBundledAudioURL(filename: filename, type: "m4a") }
        return resolve("\(prefix)_syl_\(audioKey)") != nil
            && resolve("\(prefix)_blend_\(audioKey)") != nil
    }

    nonisolated func hasWordAudio(_ key: String, language: GameLanguage) -> Bool {
        let base = key.hasSuffix("|lower")
            ? String(key.dropLast("|lower".count))
            : key
        let audioKey = base.lowercased()
        let prefix = language.audioPrefix
        func resolve(_ filename: String) -> URL? { resolveBundledAudioURL(filename: filename, type: "m4a") }
        return resolve("\(prefix)_word_\(audioKey)") != nil
            && resolve("\(prefix)_word_\(audioKey)_slabikované") != nil
    }
}

// MARK: - Audio File Naming Convention
/*
 Voice files (m4a):
 - en_a.m4a through en_z.m4a
 - cz_a.m4a through cz_z.m4a
 - en_0.m4a through en_100.m4a and cz_0.m4a through cz_100.m4a (Sounds/Numbers)
 - sfx_wow_en.m4a (Winner-celebration voice clip, played for every language)

 SFX files (mp3):
 - sfx_correct.mp3
 - sfx_wrong.mp3
 - sfx_streak_5.mp3
 - sfx_streak_10.mp3
 - sfx_click.mp3
 - sfx_applause.mp3
 */
