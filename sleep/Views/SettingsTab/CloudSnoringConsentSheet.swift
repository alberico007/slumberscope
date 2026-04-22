//
//  CloudSnoringConsentSheet.swift
//  sleep
//

import SwiftUI

struct CloudSnoringConsentSheet: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("Cloud Snoring Classifier")
                        .font(.title2.bold())

                    Text("Enabling this sends short audio clips of detected snoring events to an Azure-hosted TensorFlow (YAMNet) model for a more accurate classification. This is off by default.")

                    bullet("Only ~15-second clips of *detected* events are uploaded. The mic stream itself never leaves your device.")
                    bullet("The server discards clip bytes immediately after inference. Nothing is written to disk.")
                    bullet("Requests are signed with a per-device HMAC key stored in your Keychain.")
                    bullet("You can turn this off at any time in Settings → Sleep Audio.")
                    bullet("Events you already recorded are not re-uploaded.")
                }
                .padding()
            }
            .navigationTitle("Heads-up")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        onAccept()
                        dismiss()
                    } label: {
                        Text("Enable")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .cancel) {
                        onDecline()
                        dismiss()
                    } label: {
                        Text("Not Now")
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(.thinMaterial)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 7)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
