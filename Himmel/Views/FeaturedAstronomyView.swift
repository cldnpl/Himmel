//
//  FeaturedAstronomyView.swift
//  Himmel
//
//  "Today in the Sky" — a sheet showing what's happening above the observer:
//  the live Moon phase, which planets are up right now, tonight's headline
//  events (meteor showers, seasons, eclipses) and a seasonal deep-sky spotlight.
//

import SwiftUI

struct FeaturedAstronomyView: View {

    let date: Date
    let moon: MoonPhase.Snapshot
    /// Resolved planet positions for the current instant (type == .planet).
    var planets: [ResolvedSkyObject] = []

    private var events: [AstronomicalEvent] {
        EventsCatalog.events(for: date)
    }

    /// Headline events (everything except the Moon, which gets the hero card,
    /// and deep-sky, which gets its own section).
    private var highlights: [AstronomicalEvent] {
        events.filter {
            $0.category != .moonPhase && $0.category != .deepSky
        }
    }

    private var deepSky: [AstronomicalEvent] {
        events.filter { $0.category == .deepSky }
    }

    /// Planets currently above the horizon, brightest viewing first (highest up).
    private var planetsUp: [ResolvedSkyObject] {
        planets
            .filter { $0.horizontal.altitudeDegrees > 0 }
            .sorted { $0.horizontal.altitudeDegrees > $1.horizontal.altitudeDegrees }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                MoonHeroCard(moon: moon)

                if !planetsUp.isEmpty {
                    section(title: "Planets Up Now", count: planetsUp.count) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(planetsUp) { PlanetChip(planet: $0) }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.horizontal, -20)
                    }
                }

                if !highlights.isEmpty {
                    section(title: "Tonight's Highlights", count: highlights.count) {
                        VStack(spacing: 12) {
                            ForEach(highlights) { EventCard(event: $0) }
                        }
                    }
                }

                if !deepSky.isEmpty {
                    section(title: "Deep-Sky Spotlight", count: deepSky.count) {
                        VStack(spacing: 12) {
                            ForEach(deepSky) { EventCard(event: $0) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today in the Sky")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text(date.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.4)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .padding(.top)
    }

    // MARK: - Section scaffold

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.1)))
                Spacer()
            }
            content()
        }
    }
}

// MARK: - Moon hero card

private struct MoonHeroCard: View {
    let moon: MoonPhase.Snapshot

    private var illuminationPct: Int { Int((moon.illumination * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                moonGlyph

                VStack(alignment: .leading, spacing: 5) {
                    Text("MOON PHASE")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(moon.name.rawValue)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    illuminationBar
                }
            }

            Text(EventsCatalog.moonPhaseSummary(moon.name))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            Label {
                Text(EventsCatalog.moonPhaseVisibility(moon.name))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "eye")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.18, blue: 0.32),
                            Color(red: 0.07, green: 0.08, blue: 0.16)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var moonGlyph: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 78, height: 78)
                .blur(radius: 14)
            Image(systemName: moon.name.sfSymbol)
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .frame(width: 78, height: 78)
    }

    private var illuminationBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(illuminationPct)% illuminated")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: max(4, geo.size.width * moon.illumination))
                }
            }
            .frame(width: 130, height: 5)
        }
    }
}

// MARK: - Planet chip

private struct PlanetChip: View {
    let planet: ResolvedSkyObject

    private var altitude: Int { Int(planet.horizontal.altitudeDegrees.rounded()) }
    private var compass: String { compassPoint(planet.horizontal.azimuthDegrees) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(planetTint(planet.object.name))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
                Text(planet.object.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                Text("\(altitude)°")
                Text("·")
                Text(compass)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 104, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

// MARK: - Event card

private struct EventCard: View {
    let event: AstronomicalEvent

    private var tint: Color { categoryTint(event.category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                Image(systemName: event.category.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(0.16))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.category.displayName.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(tint.opacity(0.9))
                    Text(event.window)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
            }

            Text(event.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(event.summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Label {
                Text(event.visibility)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "eye")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 0.5)
        )
    }
}

// MARK: - Helpers

private func categoryTint(_ category: AstronomicalEventCategory) -> Color {
    switch category {
    case .meteorShower:       return .orange
    case .planetaryAlignment: return .teal
    case .moonPhase:          return Color(red: 0.6, green: 0.7, blue: 1.0)
    case .eclipse:            return .red
    case .season:             return .green
    case .deepSky:            return Color(red: 0.72, green: 0.5, blue: 1.0)
    case .other:              return .yellow
    }
}

private func planetTint(_ name: String) -> Color {
    switch name {
    case "Mercury": return Color(red: 0.72, green: 0.70, blue: 0.66)
    case "Venus":   return Color(red: 0.98, green: 0.93, blue: 0.78)
    case "Mars":    return Color(red: 0.86, green: 0.40, blue: 0.27)
    case "Jupiter": return Color(red: 0.85, green: 0.72, blue: 0.55)
    case "Saturn":  return Color(red: 0.90, green: 0.80, blue: 0.55)
    case "Uranus":  return Color(red: 0.65, green: 0.86, blue: 0.90)
    case "Neptune": return Color(red: 0.45, green: 0.55, blue: 0.95)
    default:        return .white
    }
}

private func compassPoint(_ azimuth: Double) -> String {
    let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    let normalized = azimuth.truncatingRemainder(dividingBy: 360) + (azimuth < 0 ? 360 : 0)
    let idx = Int((normalized + 22.5) / 45.0) % 8
    return dirs[idx]
}

#Preview {
    FeaturedAstronomyView(
        date: Date(),
        moon: MoonPhase.phase(at: Date())
    )
    .preferredColorScheme(.dark)
    .background(.black)
}
