//
//  FeaturedAstronomyView.swift
//  Himmel
//
//  "Today in the Sky" — a sheet showing astronomical events relevant to the
//  current date plus the live moon phase.
//

import SwiftUI

struct FeaturedAstronomyView: View {

    let date: Date

    private var events: [AstronomicalEvent] {
        EventsCatalog.events(for: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(events) { event in
                        EventCard(event: event)
                    }
                    if events.isEmpty {
                        VStack(spacing: 6) {
                            Text("Nothing major tonight")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Check back closer to a meteor shower, equinox or new moon.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.65))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today in the Sky")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(date.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct EventCard: View {
    let event: AstronomicalEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: event.category.symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(event.category.displayName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(event.window)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(event.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text(event.summary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "eye")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(event.visibility)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

#Preview {
    FeaturedAstronomyView(date: Date())
        .preferredColorScheme(.dark)
}
