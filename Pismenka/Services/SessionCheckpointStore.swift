//
//  SessionCheckpointStore.swift
//  Pismenka
//
//  Small UserDefaults-backed store for one active resume checkpoint.
//

import Foundation

@MainActor
final class SessionCheckpointStore: ObservableObject {
    @Published private(set) var checkpoint: SessionCheckpointEnvelope?

    private let storageKey = "pismenka_session_checkpoint_v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.checkpoint = Self.load(from: defaults, key: storageKey)
    }

    func save(_ checkpoint: SessionCheckpointEnvelope) {
        guard checkpoint.schemaVersion == SessionCheckpointEnvelope.currentSchemaVersion else { return }
        do {
            let data = try JSONEncoder().encode(checkpoint)
            defaults.set(data, forKey: storageKey)
            self.checkpoint = checkpoint
        } catch {
            print("Failed to save session checkpoint: \(error)")
        }
    }

    func checkpoint(for profileId: UUID) -> SessionCheckpointEnvelope? {
        guard checkpoint?.profileId == profileId else { return nil }
        return checkpoint
    }

    func clear(profileId: UUID? = nil) {
        if let profileId, checkpoint?.profileId != profileId { return }
        defaults.removeObject(forKey: storageKey)
        checkpoint = nil
    }

    private static func load(from defaults: UserDefaults, key: String) -> SessionCheckpointEnvelope? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            let checkpoint = try JSONDecoder().decode(SessionCheckpointEnvelope.self, from: data)
            guard checkpoint.schemaVersion == SessionCheckpointEnvelope.currentSchemaVersion else { return nil }
            return checkpoint
        } catch {
            print("Failed to load session checkpoint: \(error)")
            return nil
        }
    }
}
