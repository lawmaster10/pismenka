//
//  ProfileExportService.swift
//  Pismenka
//
//  Versioned JSON import/export envelope for local backups.
//

import Foundation

struct ProfileExportEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int = ProfileExportEnvelope.currentSchemaVersion
    var exportedAt: Date = Date()
    var appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    var profiles: [Profile]
}

enum ProfileImportMode {
    case replaceAll
    case merge
}

enum ProfileExportError: LocalizedError {
    case tooManyProfiles
    case payloadTooLarge
    case unsupportedSchema

    var errorDescription: String? {
        switch self {
        case .tooManyProfiles:
            return "The file contains more profiles than Písmenka supports."
        case .payloadTooLarge:
            return "The backup file is too large."
        case .unsupportedSchema:
            return "This backup was made by an unsupported version."
        }
    }
}

enum ProfileExportService {
    static let maxProfiles = 4
    static let maxImportBytes = 1_000_000

    static func exportData(profiles: [Profile]) throws -> Data {
        let envelope = ProfileExportEnvelope(profiles: profiles)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    static func decodeImport(_ data: Data) throws -> ProfileExportEnvelope {
        guard data.count <= maxImportBytes else { throw ProfileExportError.payloadTooLarge }
        let envelope = try JSONDecoder().decode(ProfileExportEnvelope.self, from: data)
        guard envelope.schemaVersion == ProfileExportEnvelope.currentSchemaVersion else {
            throw ProfileExportError.unsupportedSchema
        }
        guard envelope.profiles.count <= maxProfiles else { throw ProfileExportError.tooManyProfiles }
        return envelope
    }

    static func merged(existing: [Profile], imported: [Profile], mode: ProfileImportMode) throws -> [Profile] {
        switch mode {
        case .replaceAll:
            guard imported.count <= maxProfiles else { throw ProfileExportError.tooManyProfiles }
            return Array(imported.prefix(maxProfiles))
        case .merge:
            var result = existing
            for profile in imported {
                if let idx = result.firstIndex(where: { $0.id == profile.id }) {
                    result[idx] = profile
                } else if result.count < maxProfiles {
                    result.append(profile)
                }
            }
            guard result.count <= maxProfiles else { throw ProfileExportError.tooManyProfiles }
            return result
        }
    }
}
