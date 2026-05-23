//
//  CurriculumAudioAvailability.swift
//  Pismenka
//
//  Small model-layer protocol for curriculum gates that need to know whether
//  a unit is actually playable without depending on the concrete AudioService.
//

protocol CurriculumAudioAvailability {
    func hasWordAudio(_ key: String, language: GameLanguage) -> Bool
    func hasSyllableAudio(_ key: String, language: GameLanguage) -> Bool
}
