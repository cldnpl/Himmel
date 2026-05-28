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

    private var bottomControls: some View {
        HStack(spacing: 14) {
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
            Spacer()
        }
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
                    Text(label).font(.subheadline.weight(.medium))
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
