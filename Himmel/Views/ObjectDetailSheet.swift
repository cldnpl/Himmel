//
//  ObjectDetailSheet.swift
//  Himmel
//
//  Bottom-sheet detail view shown when the user taps a celestial object.
//

import SwiftUI

struct ObjectDetailSheet: View {

    let object: CelestialObject

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(object.summary)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    if !object.facts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(object.facts, id: \.self) { fact in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Image(systemName: "sparkle")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                    Text(fact)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: object.type.symbolName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(object.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                if let designation = object.designation {
                    Text("\(object.type.displayName) · \(designation)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Text(object.type.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(object.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ObjectDetailSheet(object: CelestialObject(
        id: "preview",
        name: "Vega",
        type: .star,
        equatorial: EquatorialCoordinate(rightAscensionHours: 18.6, declinationDegrees: 38.78),
        magnitude: 0.03,
        designation: "α Lyr",
        subtitle: "The harp star",
        summary: "One of the nearest naked-eye stars (25 light-years).",
        facts: ["Magnitude: 0.03", "Designation: α Lyr"]
    ))
    .preferredColorScheme(.dark)
}
