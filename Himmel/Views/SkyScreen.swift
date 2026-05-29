//
//  SkyScreen.swift
//  Himmel
//
//  Top-level virtual-sky experience: full-screen SceneKit map driven by
//  CoreMotion, thin floating controls, detail + featured sheets.
//

import SwiftUI

struct SkyScreen: View {

    @State private var viewModel = SkyViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            if viewModel.locationService.status == .denied
                || viewModel.locationService.status == .restricted {
                PermissionGateView(status: viewModel.locationService.status)
            } else {
                skyExperience
            }
        }
        .background(Color.black)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.navigationAcquisitionToken) { _, _ in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .sheet(item: selectedObjectBinding) { obj in
            ObjectDetailSheet(object: obj)
                .presentationDetents([.fraction(0.45), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: featuredSheetBinding) {
            FeaturedAstronomyView(date: viewModel.currentDate)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Bindings

    private var selectedObjectBinding: Binding<CelestialObject?> {
        Binding(
            get: { viewModel.selectedObject },
            set: { newValue in if newValue == nil { viewModel.dismissSelection() } }
        )
    }

    private var featuredSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isFeaturedSheetPresented },
            set: { newValue in if !newValue { viewModel.dismissFeatured() } }
        )
    }

    // MARK: - Layers

    private var skyLayer: some View {
        SkySceneView(viewModel: viewModel) { id in
            viewModel.select(objectID: id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .ignoresSafeArea()
    }

    /// Immersive sky filling the WHOLE screen (ignores safe area), with the
    /// floating controls pinned INSIDE the safe area via `safeAreaInset`, so the
    /// search bar always lands below the status bar / Dynamic Island and stays
    /// tappable — while the starfield still bleeds edge-to-edge behind it.
    private var skyExperience: some View {
        Color.clear
            // Full-screen guidance arrows (non-interactive).
            .overlay {
                SkyGuidanceArrowOverlay(guidance: viewModel.navigationGuidance)
            }
            // Live AR onboarding hint — shown until the phone is aimed at the sky.
            .overlay {
                if viewModel.isLiveARMode && !viewModel.liveARPointingAtSky {
                    liveAROnboarding
                }
            }
            // Search bar docked in the TOP safe area.
            .safeAreaInset(edge: .top) {
                SkyNavigationSearchBar(
                    text: $viewModel.navigationSearchText,
                    errorMessage: viewModel.navigationSearchError,
                    hasActiveTarget: viewModel.navigationTarget != nil,
                    isFocused: $isSearchFocused,
                    onSubmit: viewModel.submitNavigationSearch,
                    onClear: {
                        isSearchFocused = false
                        viewModel.clearNavigationTarget()
                    }
                )
                .padding(.top, 6)
            }
            // Controls docked in the BOTTOM safe area.
            .safeAreaInset(edge: .bottom) {
                bottomControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
            // The starfield sits BEHIND everything and ignores the safe area.
            .background {
                skyLayer
            }
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        if value.translation.height > 80 && abs(value.translation.width) < 80 {
                            viewModel.presentFeatured()
                        }
                    }
            )
    }

    /// Full-screen onboarding shown when Live AR Mode is active but the phone is
    /// not yet aimed at the open sky. English copy only.
    private var liveAROnboarding: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.stars")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.white)
            Text("Point at the Sky")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Step outside and raise your phone toward the open sky. The stars, planets and constellations above you will appear in their real positions.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .padding(32)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private var bottomControls: some View {
        // Horizontally scrollable so the pills never wrap or clip, even on narrow
        // devices.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if viewModel.isLiveARMode {
                    liveARControls
                } else {
                    starMapControls
                }
            }
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding(.bottom, 12)
    }

    /// Star-map (non-AR) controls.
    @ViewBuilder
    private var starMapControls: some View {
        controlButton(
            systemImage: viewModel.showConstellations
                ? "point.3.connected.trianglepath.dotted"
                : "point.3.filled.connected.trianglepath.dotted",
            isActive: viewModel.showConstellations,
            action: viewModel.toggleConstellations
        )
        controlButton(
            systemImage: "sparkles",
            label: "Today",
            isActive: false,
            action: viewModel.presentFeatured
        )
        // Enter Live AR Mode — camera passthrough of the real sky.
        controlButton(
            systemImage: "arkit",
            label: "Live AR",
            isActive: false,
            action: viewModel.toggleLiveARMode
        )
    }

    /// Live AR controls: just BACK (to the star map) and the Real Sky / AR Sky
    /// backdrop toggle — nothing else.
    @ViewBuilder
    private var liveARControls: some View {
        controlButton(
            systemImage: "chevron.left",
            label: "Back",
            isActive: false,
            action: viewModel.toggleLiveARMode
        )
        controlButton(
            systemImage: viewModel.arShowVirtualSky ? "globe" : "moon.stars",
            label: viewModel.arShowVirtualSky ? "AR Sky" : "Real Sky",
            isActive: viewModel.arShowVirtualSky,
            action: viewModel.toggleARSky
        )
    }

    @ViewBuilder
    private func controlButton(
        systemImage: String,
        label: String? = nil,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                if let label {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)   // never wrap ("Liv e AR")
                }
            }
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.white.opacity(0.35) : Color.clear, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SkyScreen()
}
