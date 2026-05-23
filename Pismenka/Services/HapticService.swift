//
//  HapticService.swift
//  Pismenka
//
//  Haptic feedback service
//

import Foundation
import UIKit

class HapticService {
    static let shared = HapticService()
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    
    private init() {
        // Prepare generators
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
        selection.prepare()
    }
    
    // MARK: - Feedback Types
    
    /// Light tap for button presses
    func tap() {
        impactLight.impactOccurred()
    }
    
    /// Selection change feedback
    func select() {
        selection.selectionChanged()
    }
    
    /// Success feedback for correct answers
    func success() {
        notification.notificationOccurred(.success)
    }
    
    /// Error feedback for wrong answers
    func error() {
        notification.notificationOccurred(.error)
    }
    
    /// Warning feedback
    func warning() {
        notification.notificationOccurred(.warning)
    }
    
    /// Double tap pattern for streak milestones
    func streakMilestone() {
        impactHeavy.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.impactHeavy.impactOccurred()
        }
    }
    
    /// Shake pattern for wrong answer
    func wrongAnswer() {
        error()
        // Add a secondary vibration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.impactMedium.impactOccurred()
        }
    }
    
    /// Prepare all generators (call before game starts)
    func prepareAll() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notification.prepare()
        selection.prepare()
    }
}
