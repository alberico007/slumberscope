//
//  GlassCard.swift
//  sleep
//
//

import SwiftUI

// MARK: - GlassCard

struct GlassCard<Content: View>: View {

    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

// MARK: - StatRow

struct StatRow: View {

    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - GlassButton

struct GlassButton: View {

    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
