//
//  NumberDifficulty.swift
//  Pismenka
//
//  Pedagogical number ordering (0…100), digit-overlap confusion policies, and
//  early-recognition calibration pool for the numbers learning layer.
//

import Foundation

enum NumberDifficulty {

    /// Full curriculum: 0 through 100 inclusive.
    static let allNumbers: [String] = (0...100).map(String.init)

    static let allNumberSet: Set<String> = Set(allNumbers)

    /// How many brand-new numbers an introduction-day session may add.
    /// Kids burn through 0…10 quickly; two per day keeps the pool stimulating.
    static let maxNewNumbersPerDay = 2

    /// Calibration / first-band pool: 0…20.
    static let earlyRecognitionNumbers: [String] = (0...20).map(String.init)

    /// Pedagogical introduction order.
    /// Digits 1…10, then 0, then 11…20, then decade fill from 21…, then 100.
    static let introductionOrder: [String] = {
        var order: [String] = (1...10).map(String.init)
        order.append("0")
        order.append(contentsOf: (11...20).map(String.init))
        // 20 is already in the early band; decade 2 continues at 21…29.
        for ones in 1...9 {
            order.append(String(20 + ones))
        }
        for decade in 3...9 {
            let anchor = String(decade * 10)
            order.append(anchor)
            for ones in 1...9 {
                order.append(String(decade * 10 + ones))
            }
        }
        order.append("100")
        return order
    }()

    /// Calibration / first-band pool: 0…20.
    ///
    /// Optional `ageNumber` mirrors the letter name-seed: when the child's age
    /// is known and falls in 0…20, that digit is ensured in the schedule
    /// (personally meaningful, same idea as `LetterDifficulty.calibrationPool(nameLetter:)`).
    /// Not wired from `CalibrationView` today because `Profile` has no age field;
    /// keep the hook ready for when age is collected.
    static func calibrationPool(ageNumber: Int? = nil) -> [String] {
        var pool = earlyRecognitionNumbers
        if let age = ageNumber, (0...20).contains(age) {
            let key = String(age)
            if !pool.contains(key) {
                pool.append(key)
            }
        }
        return pool
    }

    static func isEligibleTarget(_ key: String) -> Bool {
        allNumberSet.contains(key)
    }

    // MARK: - Digit features

    struct Digits: Equatable {
        /// Tens place; `nil` for single-digit 0…9. For 100, uses a dedicated bucket (10).
        var tens: Int?
        var ones: Int
        var value: Int
        var isHundred: Bool { value == 100 }
    }

    static func digits(for key: String) -> Digits? {
        guard let value = Int(key), (0...100).contains(value) else { return nil }
        if value == 100 {
            return Digits(tens: 10, ones: 0, value: 100)
        }
        if value < 10 {
            return Digits(tens: nil, ones: value, value: value)
        }
        return Digits(tens: value / 10, ones: value % 10, value: value)
    }

    /// True when `a` and `b` are digit transposes of each other (26 ↔ 62).
    static func isDigitTranspose(_ a: String, _ b: String) -> Bool {
        guard let da = digits(for: a), let db = digits(for: b) else { return false }
        guard let at = da.tens, let bt = db.tens else { return false }
        guard !da.isHundred, !db.isHundred else { return false }
        return at == db.ones && da.ones == bt && a != b
    }

    /// Cross-length containment: 1 vs 10, 2 vs 12/20, etc.
    static func isDigitContainment(_ a: String, _ b: String) -> Bool {
        guard let da = digits(for: a), let db = digits(for: b) else { return false }
        if da.value == db.value { return false }

        func containsDigit(_ haystack: Digits, digit: Int) -> Bool {
            if haystack.ones == digit { return true }
            if let t = haystack.tens, t == digit { return true }
            if haystack.isHundred && digit == 1 { return true }
            return false
        }

        let aLen = da.value < 10 ? 1 : (da.value < 100 ? 2 : 3)
        let bLen = db.value < 10 ? 1 : (db.value < 100 ? 2 : 3)
        guard aLen != bLen else { return false }

        if aLen < bLen {
            if aLen == 1 {
                return containsDigit(db, digit: da.ones)
            }
        } else {
            if bLen == 1 {
                return containsDigit(da, digit: db.ones)
            }
        }
        return false
    }

    static let lookalikePairs: [String: Set<String>] = {
        var map: [String: Set<String>] = [:]
        func connect(_ a: String, _ b: String) {
            map[a, default: []].insert(b)
            map[b, default: []].insert(a)
        }
        connect("6", "9")
        connect("0", "8")
        connect("1", "7")
        return map
    }()

    static func areLookalikes(_ a: String, _ b: String) -> Bool {
        if lookalikePairs[a]?.contains(b) == true { return true }
        if isDigitContainment(a, b) { return true }
        return false
    }

    // MARK: - Confusion policy

    enum ConfusionPolicy {
        case avoid
        case allowSameOnes
        case allowSameTens
        case intentionallyPractice
    }

    /// Whether `distractor` is allowed next to `target` under `policy`.
    static func isAllowedDistractor(
        _ distractor: String,
        for target: String,
        policy: ConfusionPolicy
    ) -> Bool {
        guard distractor != target else { return false }
        guard isEligibleTarget(distractor), isEligibleTarget(target) else { return false }
        guard let dt = digits(for: target), let dd = digits(for: distractor) else { return false }

        let isTranspose = isDigitTranspose(target, distractor)
        let isLookalike = areLookalikes(target, distractor)

        switch policy {
        case .avoid:
            if isTranspose || isLookalike { return false }
            return !sharesTens(dt, dd) && !sharesOnes(dt, dd)

        case .allowSameOnes:
            if isTranspose || isLookalike { return false }
            return !sharesTens(dt, dd)

        case .allowSameTens:
            if isTranspose { return false }
            return true

        case .intentionallyPractice:
            return true
        }
    }

    static func isHardConfusable(_ a: String, _ b: String) -> Bool {
        isDigitTranspose(a, b) || areLookalikes(a, b) || sharesTens(digits(for: a), digits(for: b))
    }

    private static func sharesTens(_ a: Digits?, _ b: Digits?) -> Bool {
        guard let a, let b, let at = a.tens, let bt = b.tens else { return false }
        return at == bt
    }

    private static func sharesOnes(_ a: Digits?, _ b: Digits?) -> Bool {
        guard let a, let b else { return false }
        // Single-digit vs single-digit: same value already excluded.
        if a.tens == nil && b.tens == nil { return false }
        return a.ones == b.ones
    }

    /// Pick distractors from `pool` under the given policy.
    static func pickDistractors(
        target: String,
        count: Int,
        from pool: [String],
        policy: ConfusionPolicy,
        preferHard: Bool = false
    ) -> [String] {
        let candidates = pool.filter { isAllowedDistractor($0, for: target, policy: policy) }
        guard count > 0 else { return [] }

        if preferHard || policy == .intentionallyPractice {
            let hard = candidates.filter { isHardConfusable(target, $0) }.shuffled()
            let soft = candidates.filter { !isHardConfusable(target, $0) }.shuffled()
            return Array((hard + soft).prefix(count))
        }

        // Prefer distant decades under avoid.
        if policy == .avoid, let td = digits(for: target) {
            let ranked = candidates.sorted { a, b in
                decadeDistance(td, digits(for: a)) > decadeDistance(td, digits(for: b))
            }
            return Array(ranked.prefix(count))
        }

        return Array(candidates.shuffled().prefix(count))
    }

    private static func decadeDistance(_ target: Digits, _ other: Digits?) -> Int {
        guard let other else { return 0 }
        let at = target.tens ?? -1
        let bt = other.tens ?? -1
        if at < 0 || bt < 0 {
            return abs(target.value - other.value)
        }
        return abs(at - bt)
    }

    // MARK: - Unlock / readiness

    /// Numbers that may appear as targets given introduced + known evidence.
    static func playablePool(introduced: Set<String>) -> [String] {
        introductionOrder.filter { introduced.contains($0) }
    }

    /// Minimum distinct pool size needed to build a distant 4-option grid.
    static let minimumPoolForDistantGrid = 4

    static func nextFocusCandidate(
        introduced: Set<String>,
        known: Set<String>,
        blocked: Set<String> = []
    ) -> String? {
        for key in introductionOrder {
            if introduced.contains(key) { continue }
            if blocked.contains(key) { continue }
            if !isReadyToIntroduce(key, introduced: introduced, known: known) { continue }
            let pool = Set(playablePool(introduced: introduced.union([key])))
            if pool.count < minimumPoolForDistantGrid { continue }
            // Ensure at least 3 distant distractors exist under avoid.
            let distractors = pickDistractors(
                target: key,
                count: 3,
                from: Array(pool.subtracting([key])),
                policy: .avoid
            )
            if distractors.count < 3 { continue }
            return key
        }
        return nil
    }

    static func isReadyToIntroduce(
        _ key: String,
        introduced: Set<String>,
        known: Set<String>
    ) -> Bool {
        guard let value = Int(key) else { return false }

        // Early band 0…20 is freely introducible (two-per-day pacing is the
        // only throttle). Later decades still require prior footholds.
        if (0...20).contains(value) {
            return true
        }
        if value == 100 {
            let anchorsKnown = [20, 30, 40, 50, 60, 70, 80, 90]
                .map(String.init)
                .filter { known.contains($0) }
                .count
            return anchorsKnown >= 3 || introduced.contains("90")
        }
        if value % 10 == 0, (30...90).contains(value) {
            let teensKnown = (11...19).map(String.init).filter { known.contains($0) }.count
            return teensKnown >= 3 || introduced.contains("15")
        }
        // Within-decade fill: require the decade anchor known (or introduced).
        let anchor = String((value / 10) * 10)
        return known.contains(anchor) || introduced.contains(anchor)
    }
}
