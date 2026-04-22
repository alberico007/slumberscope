//
//  SubscriptionView.swift
//  sleep
//
//

import SwiftUI

struct SubscriptionView: View {

    @State private var selectedPlan: SubscriptionPlan = .premium
    @State private var storeKitService = StoreKitService()
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Current subscription status
                if storeKitService.isPremium {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("You're a Premium member")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 12)
                }

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                        )

                    Text("Unlock Premium")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Get the most out of your sleep tracking.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, storeKitService.isPremium ? 8 : 20)

                // Plan cards
                ForEach(SubscriptionPlan.allCases) { plan in
                    PlanCard(plan: plan, isSelected: selectedPlan == plan) {
                        selectedPlan = plan
                    }
                }

                // Feature comparison
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Premium Features")
                            .font(.headline)

                        FeatureCompareRow(feature: "Sleep Tracking", free: true, premium: true)
                        FeatureCompareRow(feature: "7-Day Trends", free: true, premium: true)
                        FeatureCompareRow(feature: "Apple Health Sync", free: true, premium: true)
                        Divider()
                        FeatureCompareRow(feature: "Full Sound Library (200+)", free: false, premium: true)
                        FeatureCompareRow(feature: "Sound Mixer (4 layers)", free: false, premium: true)
                        FeatureCompareRow(feature: "AI Sleep Coach", free: false, premium: true)
                        FeatureCompareRow(feature: "Factor Analysis", free: false, premium: true)
                        FeatureCompareRow(feature: "Unlimited Recordings", free: false, premium: true)
                        FeatureCompareRow(feature: "PDF/CSV Export", free: false, premium: true)
                        FeatureCompareRow(feature: "90-Day & 1-Year Trends", free: false, premium: true)
                    }
                }

                // Subscribe button
                Button {
                    Task {
                        do {
                            switch selectedPlan {
                            case .monthly: try await storeKitService.purchaseMonthly()
                            case .yearly: try await storeKitService.purchaseYearly()
                            case .premium: try await storeKitService.purchaseLifetime()
                            }
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                } label: {
                    Group {
                        if storeKitService.purchaseInProgress {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Subscribe — \(selectedPlan.price)")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(storeKitService.purchaseInProgress)

                Button("Restore Purchases") {
                    Task { await storeKitService.restorePurchases() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Cancel anytime. Subscription auto-renews.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Purchase Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - SubscriptionPlan

enum SubscriptionPlan: String, CaseIterable, Identifiable {
    case monthly = "Monthly"
    case yearly = "Yearly"
    case premium = "Premium"

    var id: String { rawValue }

    var price: String {
        switch self {
        case .monthly: "$4.99/mo"
        case .yearly: "$29.99/yr"
        case .premium: "$49.99 lifetime"
        }
    }

    var savings: String? {
        switch self {
        case .yearly: "Save 50%"
        case .premium: "Best Value"
        default: nil
        }
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(plan.price)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let savings = plan.savings {
                    Text(savings)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.2))
                        .clipShape(Capsule())
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .orange : .secondary)
            }
            .padding()
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.orange : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FeatureCompareRow

private struct FeatureCompareRow: View {
    let feature: String
    let free: Bool
    let premium: Bool

    var body: some View {
        HStack {
            Text(feature)
                .font(.caption)
            Spacer()
            Image(systemName: free ? "checkmark" : "xmark")
                .font(.caption2)
                .foregroundStyle(free ? .green : .secondary)
                .frame(width: 40)
            Image(systemName: premium ? "checkmark" : "xmark")
                .font(.caption2)
                .foregroundStyle(premium ? .green : .secondary)
                .frame(width: 40)
        }
    }
}
