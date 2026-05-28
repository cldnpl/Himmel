//
//  ContentView.swift
//  Himmel
//
//  Root container — immediately launches the AR sky experience.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        SkyScreen()
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
