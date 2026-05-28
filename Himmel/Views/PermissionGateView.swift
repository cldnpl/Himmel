//
//  PermissionGateView.swift
//  Himmel
//
//  Fallback view shown when the user has denied or restricted location access.
//

import SwiftUI

struct PermissionGateView: View {

    let status: LocationService.Status

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "location.slash.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail)
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 40)
            Spacer()
            Button {
                openSettings()
            } label: {
                Text("Open Settings")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var title: String {
        switch status {
        case .denied:     return "Location access required"
        case .restricted: return "Location access restricted"
        default:          return "Location access required"
        }
    }

    private var detail: String {
        switch status {
        case .denied:
            return "Himmel needs your location to compute the position of stars and planets above you. Enable Location for Himmel in Settings to begin observing."
        case .restricted:
            return "Location services are restricted on this device. Adjust the device's restrictions to use Himmel."
        default:
            return "Himmel needs your location to compute the position of celestial objects above you."
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    PermissionGateView(status: .denied)
        .preferredColorScheme(.dark)
}
