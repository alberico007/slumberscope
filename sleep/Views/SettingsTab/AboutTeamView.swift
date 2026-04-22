//
//  AboutTeamView.swift
//  sleep
//
//

import SwiftUI

struct AboutTeamView: View {

    @State private var headerVisible = false
    @State private var visibleCards: Int = 0

    private let team: [TeamMember] = [
        TeamMember(
            name: "Simon Alberico",
            role: "Cyber Security",
            initials: "SA",
            gradient: [Color.cyan, Color.blue],
            imageName: "Simon",
            linkedInURL: URL(string: "https://www.linkedin.com/in/simon-alberico-0b2769329/")
        ),
        TeamMember(
            name: "Aia Ahmed",
            role: "Computer Science",
            initials: "AA",
            gradient: [Color.purple, Color.pink],
            imageName: "Aia",
            linkedInURL: URL(string: "https://www.linkedin.com/in/aia-ahmed/")
        ),
        TeamMember(
            name: "Ananjin Batdelger",
            role: "Software Engineering",
            initials: "AB",
            gradient: [Color.green, Color.teal],
            imageName: "Ana",
            linkedInURL: URL(string: "https://www.linkedin.com/in/anabatdelger/")
        )
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {

                // App header
                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
                        )

                    Text("Slumberscope")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Built with care to help you sleep better.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : 20)

                // Team section
                VStack(alignment: .leading, spacing: 16) {
                    Text("The Team")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)

                    ForEach(Array(team.enumerated()), id: \.offset) { index, member in
                        TeamMemberCard(member: member)
                            .padding(.horizontal, 20)
                            .opacity(visibleCards > index ? 1 : 0)
                            .offset(y: visibleCards > index ? 0 : 24)
                            .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.12), value: visibleCards)
                    }
                }

                // Version info
                VStack(spacing: 6) {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("© 2026 Slumberscope. All rights reserved.")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                headerVisible = true
            }
            withAnimation(.easeOut(duration: 0.1).delay(0.3)) {
                visibleCards = team.count
            }
        }
    }
}

// MARK: - TeamMember

struct TeamMember {
    let name: String
    let role: String
    let initials: String
    let gradient: [Color]
    /// Asset-catalog image name. When set, the card shows the photo instead
    /// of the initials/gradient avatar.
    let imageName: String?
    /// LinkedIn profile URL. When set, the card renders an "in" badge and
    /// becomes tappable, opening the profile in Safari / LinkedIn app.
    let linkedInURL: URL?
}

// MARK: - TeamMemberCard

private struct TeamMemberCard: View {

    let member: TeamMember
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = member.linkedInURL { openURL(url) }
        } label: {
            HStack(spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(member.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if member.linkedInURL != nil {
                    linkedInBadge
                }
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(member.linkedInURL == nil)
    }

    @ViewBuilder private var avatar: some View {
        if let imageName = member.imageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: member.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 56, height: 56)
                Text(member.initials)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
        }
    }

    private var linkedInBadge: some View {
        // LinkedIn brand "in" mark — small filled square with rounded corners
        // and the lowercase "in" centered. Visual cue that the row is tappable.
        Text("in")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color(red: 0.04, green: 0.40, blue: 0.71))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Open LinkedIn profile")
    }
}
