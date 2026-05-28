//
//  SkyNavigationOverlay.swift
//  Himmel
//
//  SwiftUI search and edge-arrow guidance controls for the sky screen.
//

import SwiftUI

struct SkyNavigationSearchBar: View {
    @Binding var text: String
    let errorMessage: String?
    let hasActiveTarget: Bool
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Bool
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))

                TextField("Search the sky", text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused(isFocused)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .onSubmit {
                        if onSubmit() {
                            isFocused.wrappedValue = false
                        }
                    }

                if hasActiveTarget || !text.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420)
            .frame(height: 48)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(hasActiveTarget ? 0.34 : 0.18), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.red.opacity(0.45), lineWidth: 0.7))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 70)
        .animation(.easeInOut(duration: 0.18), value: errorMessage)
        .animation(.easeInOut(duration: 0.18), value: hasActiveTarget)
    }
}

struct SkyGuidanceArrowOverlay: View {
    let guidance: SkyNavigationGuidance

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                ZStack {
                    if guidance.shouldShowArrows, let direction = guidance.direction {
                        // A SINGLE precise 8-way arrow — no multi-arrow confusion.
                        SkyGuidanceArrow(
                            direction: direction,
                            guidance: guidance,
                            date: timeline.date
                        )
                        .position(position(for: direction, in: proxy))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.16), value: guidance.shouldShowArrows)
        .animation(.easeInOut(duration: 0.16), value: guidance.direction)
    }

    /// Place the single arrow along the screen edge / corner matching its
    /// 8-way direction (its unit vector mapped to the viewport boundary).
    private func position(for direction: SkyNavigationDirection, in proxy: GeometryProxy) -> CGPoint {
        let safe = proxy.safeAreaInsets
        let size = proxy.size
        let topMargin = safe.top + 96
        let bottomMargin = size.height - safe.bottom - 108
        let leftX = safe.leading + 40
        let rightX = size.width - safe.trailing - 40
        let centerX = size.width * 0.5
        let centerY = size.height * 0.5

        let v = direction.screenVector
        let x: CGFloat = v.dx > 0 ? rightX : (v.dx < 0 ? leftX : centerX)
        let y: CGFloat = v.dy > 0 ? bottomMargin : (v.dy < 0 ? topMargin : centerY)
        return CGPoint(x: x, y: y)
    }
}

private struct SkyGuidanceArrow: View {
    let direction: SkyNavigationDirection
    let guidance: SkyNavigationGuidance
    let date: Date

    var body: some View {
        let pulse = pulseValue
        Image(systemName: direction.symbolName)
            .font(.system(size: 34, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 66, height: 66)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.38 + 0.28 * pulse), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.42), radius: 16, x: 0, y: 8)
            .opacity(0.48 + guidance.intensity * 0.32 + pulse * 0.20)
            .scaleEffect(0.94 + pulse * (0.07 + guidance.intensity * 0.08))
    }

    private var pulseValue: Double {
        let frequency = 0.85 + guidance.intensity * 2.15
        let phase = date.timeIntervalSinceReferenceDate * frequency * 2.0 * .pi
        return (sin(phase) + 1.0) * 0.5
    }
}
