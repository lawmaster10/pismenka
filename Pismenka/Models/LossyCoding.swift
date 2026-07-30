//
//  LossyCoding.swift
//  Pismenka
//
//  Forward-compatible Codable helpers. Unknown future enum cases and
//  undecodable array elements must not wipe an entire profile store —
//  that is exactly how sideloading an older build over 1.5 emptied
//  kids' progress and then clobbered the cloud backup.
//

import Foundation

enum LossyCoding {
    /// Minimal JSON tree used only to advance past a bad unkeyed element.
    enum JSONValue: Decodable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported JSON value"
                )
            }
        }
    }
}

extension KeyedDecodingContainer {
    /// Like `decodeIfPresent` for String-raw enums, but unknown raw values
    /// become `nil` instead of failing the whole decode.
    func decodeLossyIfPresent<T>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T? where T: RawRepresentable, T.RawValue == String {
        guard contains(key), try decodeNil(forKey: key) == false else {
            return nil
        }
        let raw = try decode(String.self, forKey: key)
        return T(rawValue: raw)
    }

    /// Decodes `T` when present; any decode failure yields `nil` so a
    /// nested future-shaped payload cannot poison the parent object.
    func decodeLossyDecodableIfPresent<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> T? {
        guard contains(key), try decodeNil(forKey: key) == false else {
            return nil
        }
        return try? decode(T.self, forKey: key)
    }

    /// Decodes an array, skipping elements that fail. Used for
    /// `recentRoundEvents` so one future RoundEvent case cannot empty
    /// the whole profile.
    func decodeLossyArray<T: Decodable>(
        _ type: T.Type,
        forKey key: Key
    ) throws -> [T] {
        guard contains(key), try decodeNil(forKey: key) == false else {
            return []
        }
        var container = try nestedUnkeyedContainer(forKey: key)
        var result: [T] = []
        while !container.isAtEnd {
            do {
                result.append(try container.decode(T.self))
            } catch {
                // Advance past the bad element; bail if we cannot, to
                // avoid an infinite loop on a corrupt stream.
                if (try? container.decode(LossyCoding.JSONValue.self)) == nil {
                    break
                }
            }
        }
        return result
    }
}

/// Compares CFBundleShortVersionString-style values (`"1.4"`, `"1.5.0"`).
enum AppVersion {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { part in
                let digits = part.prefix(while: { $0.isNumber })
                return Int(digits) ?? 0
            }
    }
}
