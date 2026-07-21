//
//  SessionCheckpointStore.swift
//  Pismenka
//
//  Small UserDefaults-backed store for resume checkpoints, one slot per
//  learning layer (letters / numbers) so switching the home-screen layer
//  never discards the other layer's in-flight session.
//

import Foundation

@MainActor
final class SessionCheckpointStore: ObservableObject {
    /// Slots keyed by `LearningLayer.rawValue` ("letters" / "numbers").
    @Published private(set) var checkpoints: [String: SessionCheckpointEnvelope]

    private static let storageKey = "pismenka_session_checkpoint_v2"
    private static let legacyStorageKey = "pismenka_session_checkpoint_v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.checkpoints = Self.load(from: defaults)
    }

    /// Convenience for callers that only care about one layer's slot.
    func checkpoint(for layer: LearningLayer) -> SessionCheckpointEnvelope? {
        checkpoints[layer.rawValue]
    }

    func save(_ checkpoint: SessionCheckpointEnvelope, layer: LearningLayer) {
        guard checkpoint.schemaVersion == SessionCheckpointEnvelope.currentSchemaVersion else { return }
        guard checkpoint.learningLayer == layer else {
            assertionFailure(
                "Checkpoint layer \(checkpoint.learningLayer) does not match slot \(layer); discarding."
            )
            return
        }
        var updated = checkpoints
        updated[layer.rawValue] = checkpoint
        persist(updated)
    }

    func checkpoint(for profileId: UUID, layer: LearningLayer) -> SessionCheckpointEnvelope? {
        guard let envelope = checkpoints[layer.rawValue], envelope.profileId == profileId else { return nil }
        return envelope
    }

    /// Clears checkpoint slots. `profileId == nil` matches any profile;
    /// `layer == nil` clears every layer's slot.
    func clear(profileId: UUID? = nil, layer: LearningLayer? = nil) {
        var updated = checkpoints
        for (slot, envelope) in checkpoints {
            if let layer, slot != layer.rawValue { continue }
            if let profileId, envelope.profileId != profileId { continue }
            updated[slot] = nil
        }
        guard updated.count != checkpoints.count else { return }
        persist(updated)
    }

    private func persist(_ updated: [String: SessionCheckpointEnvelope]) {
        do {
            let data = try JSONEncoder().encode(updated)
            defaults.set(data, forKey: Self.storageKey)
            checkpoints = updated
        } catch {
            print("Failed to save session checkpoints: \(error)")
        }
    }

    private static func load(from defaults: UserDefaults) -> [String: SessionCheckpointEnvelope] {
        if let data = defaults.data(forKey: storageKey) {
            do {
                let map = try JSONDecoder().decode([String: SessionCheckpointEnvelope].self, from: data)
                return map.filter { $0.value.schemaVersion == SessionCheckpointEnvelope.currentSchemaVersion }
            } catch {
                print("Failed to load session checkpoints: \(error)")
                return [:]
            }
        }
        return migrateLegacySingleSlot(from: defaults)
    }

    /// v1 stored one bare envelope; those predate the numbers layer, so the
    /// envelope moves into the letters slot and the old key is removed.
    private static func migrateLegacySingleSlot(from defaults: UserDefaults) -> [String: SessionCheckpointEnvelope] {
        guard let data = defaults.data(forKey: legacyStorageKey) else { return [:] }
        defaults.removeObject(forKey: legacyStorageKey)
        do {
            var envelope = try JSONDecoder().decode(SessionCheckpointEnvelope.self, from: data)
            guard envelope.schemaVersion == SessionCheckpointEnvelope.currentSchemaVersion else { return [:] }
            envelope.learningLayer = .letters
            let migrated = [LearningLayer.letters.rawValue: envelope]
            if let encoded = try? JSONEncoder().encode(migrated) {
                defaults.set(encoded, forKey: storageKey)
            }
            return migrated
        } catch {
            print("Failed to migrate legacy session checkpoint: \(error)")
            return [:]
        }
    }
}
