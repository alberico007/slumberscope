//
//  PremiumGate.swift
//  sleep
//
//

import SwiftUI

// MARK: - PremiumGate

struct PremiumGate<Content: View, LockedContent: View>: View {
    let isPremium: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let lockedContent: LockedContent

    var body: some View {
        if isPremium {
            content
        } else {
            lockedContent
        }
    }
}

// MARK: - Premium Lock Overlay

struct PremiumLockOverlay: View {
    let feature: String
    @State private var showingSubscription = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Premium Feature")
                .font(.headline)

            Text(feature)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingSubscription = true
            } label: {
                Label("Unlock Premium", systemImage: "crown.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingSubscription) {
            NavigationStack {
                SubscriptionView()
            }
        }
    }
}

// MARK: - Premium Badge

struct PremiumBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 8))
            Text("PRO")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.orange.opacity(0.15))
        .clipShape(Capsule())
    }
}
