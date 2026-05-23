//
//  ParentGateView.swift
//  Pismenka
//
//  Parent gate - simple gesture to verify adult
//

import SwiftUI

struct ParentGateView: View {
    var method: ParentGateMethod = .swipe
    let onSuccess: () -> Void
    let onCancel: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isComplete = false
    
    private let requiredDistance: CGFloat = 200
    
    var body: some View {
        ZStack {
            Color.ink.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            if method == .holdButtons {
                HoldButtonsParentGate(onSuccess: onSuccess, onCancel: onCancel)
            } else {
                VStack(spacing: 24) {
                    lockBadge

                    VStack(spacing: 6) {
                        Text("Parents only".uppercased())
                            .brandEyebrowStyle()
                        Text("Swipe up to continue")
                            .font(.brandTitleL(28))
                            .tracking(-0.8)
                            .foregroundColor(.ink)
                            .multilineTextAlignment(.center)
                        Text("This keeps kids inside their game.")
                            .font(.brandBody(16))
                            .foregroundColor(.slate500)
                            .multilineTextAlignment(.center)
                    }

                    swipeTrack

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.brandBody(16, weight: .black))
                            .foregroundColor(.slate500)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.75)))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.creamDeep, lineWidth: 1)
                            )
                    }
                }
                .padding(28)
                .frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.96), Color.amberMist.opacity(0.96)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                )
                .shadow(color: Color.ink.opacity(0.18), radius: 28, x: 0, y: 18)
                .padding(.horizontal, 24)
            }
        }
        .presentationBackground(.clear)
        .accessibilityLabel(method == .holdButtons ? "Parent gate hold buttons" : "Parent gate swipe up")
    }

    private var lockBadge: some View {
        ZStack {
            Circle()
                .fill(isComplete ? Color.leaf : Color.sun)
                .frame(width: 90, height: 90)
                .shadow(color: (isComplete ? Color.leaf : Color.sun).opacity(0.35), radius: 16, x: 0, y: 8)

            Image(systemName: isComplete ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 38, weight: .black))
                .foregroundColor(.white)
        }
    }

    private var swipeTrack: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.amberTint.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                )
                .frame(width: 86, height: 240)

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.leaf, .sky],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 86, height: max(52, min(dragOffset + 52, 240)))
                .opacity(0.95)

            VStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 20, weight: .black))
                Text("Swipe")
                    .font(.brandEyebrow(10))
                    .tracking(1.2)
            }
            .foregroundColor(Color.slate500.opacity(0.65))
            .offset(y: -128)

            Circle()
                .fill(Color.white)
                .frame(width: 64, height: 64)
                .shadow(color: Color.ink.opacity(0.14), radius: 12, x: 0, y: 6)
                .overlay(
                    Image(systemName: "chevron.up")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(.leaf)
                )
                .offset(y: -dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newOffset = -value.translation.height
                            if newOffset > 0 {
                                dragOffset = min(newOffset, requiredDistance)
                            }
                        }
                        .onEnded { _ in
                            if dragOffset >= requiredDistance * 0.9 {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    isComplete = true
                                    dragOffset = requiredDistance
                                }
                                HapticService.shared.success()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onSuccess()
                                }
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .padding(.bottom, 10)
        }
    }
}

struct HoldButtonsParentGate: View {
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var leftPressed = false
    @State private var rightPressed = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(leftPressed && rightPressed ? Color.leaf : Color.sun)
                    .frame(width: 90, height: 90)
                    .shadow(color: Color.sun.opacity(0.35), radius: 16, x: 0, y: 8)
                Image(systemName: leftPressed && rightPressed ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 38, weight: .black))
                    .foregroundColor(.white)
            }
            VStack(spacing: 6) {
                Text("Parents only".uppercased())
                    .brandEyebrowStyle()
                Text("Hold both buttons")
                    .font(.brandTitleL(28))
                    .tracking(-0.8)
                    .foregroundColor(.ink)
                    .multilineTextAlignment(.center)
                Text("Keep holding for 3 seconds.")
                    .font(.brandBody(16))
                    .foregroundColor(.slate500)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 32) {
                holdButton(title: "Hold", isPressed: $leftPressed)
                holdButton(title: "Hold", isPressed: $rightPressed)
            }
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.brandBody(16, weight: .black))
                    .foregroundColor(.slate500)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.75)))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.creamDeep, lineWidth: 1)
                    )
            }
        }
        .padding(28)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.96), Color.amberMist.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: Color.ink.opacity(0.18), radius: 28, x: 0, y: 18)
        .padding(.horizontal, 24)
        .onChange(of: leftPressed) { _, _ in updateHoldState() }
        .onChange(of: rightPressed) { _, _ in updateHoldState() }
    }

    private func holdButton(title: String, isPressed: Binding<Bool>) -> some View {
        Text(title)
            .font(.brandTitleM(18))
            .foregroundColor(isPressed.wrappedValue ? .white : .ink)
            .frame(width: 110, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isPressed.wrappedValue ? Color.leaf : Color.amberTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: Color.ink.opacity(0.08), radius: 10, x: 0, y: 5)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed.wrappedValue = true }
                    .onEnded { _ in isPressed.wrappedValue = false }
            )
            .accessibilityLabel(title)
    }

    private func updateHoldState() {
        holdTask?.cancel()
        guard leftPressed && rightPressed else { return }
        holdTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                HapticService.shared.success()
                onSuccess()
            }
        }
    }
}

#Preview {
    ParentGateView(onSuccess: {}, onCancel: {})
}
