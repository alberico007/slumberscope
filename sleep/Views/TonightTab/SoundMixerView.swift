//
//  SoundMixerView.swift
//  sleep
//
//

import SwiftData
import SwiftUI

struct SoundMixerView: View {

    @Environment(SleepSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SoundPreset.createdAt, order: .reverse) private var presets: [SoundPreset]

    @Environment(SoundService.self) private var soundService
    @State private var selectedCategory: SoundItem.SoundCategory? = nil
    @State private var showingSavePreset = false
    @State private var presetName = ""

    private var filteredSounds: [SoundItem] {
        guard let cat = selectedCategory else { return SoundLibrary.all }
        return SoundLibrary.all.filter { $0.category == cat }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Saved Presets
                if !presets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets) { preset in
                                Button {
                                    soundService.loadPreset(preset)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.title3)
                                            .foregroundStyle(.cyan)
                                        Text(preset.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }

                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryPill(name: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(SoundItem.SoundCategory.allCases) { cat in
                            CategoryPill(name: cat.rawValue, isSelected: selectedCategory == cat) {
                                selectedCategory = cat
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // Sound grid
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                        ForEach(filteredSounds) { sound in
                            SoundTile(
                                sound: sound,
                                isActive: soundService.activeSlots.contains { $0.sound.id == sound.id }
                            ) {
                                if soundService.activeSlots.contains(where: { $0.sound.id == sound.id }) {
                                    soundService.removeSound(id: sound.id)
                                } else {
                                    soundService.addSound(sound)
                                }
                            }
                        }
                    }
                    .padding()
                }

                // Active mixer panel
                if !soundService.activeSlots.isEmpty {
                    VStack(spacing: 12) {
                        Divider()

                        ForEach(soundService.activeSlots) { slot in
                            HStack(spacing: 10) {
                                Image(systemName: slot.sound.icon)
                                    .foregroundStyle(.cyan)
                                    .frame(width: 24)

                                Text(slot.sound.name)
                                    .font(.caption)
                                    .frame(width: 60, alignment: .leading)

                                Slider(value: Binding(
                                    get: { Double(slot.volume) },
                                    set: { soundService.updateVolume(id: slot.id, volume: Float($0)) }
                                ), in: 0...1)
                                .tint(.cyan)

                                Button {
                                    soundService.removeSound(id: slot.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Timer picker
                        HStack {
                            Image(systemName: "timer")
                                .foregroundStyle(.secondary)
                            Picker("Timer", selection: Binding(
                                get: { settings.soundTimerMinutes },
                                set: { settings.soundTimerMinutes = $0 }
                            )) {
                                Text("15 min").tag(15)
                                Text("30 min").tag(30)
                                Text("45 min").tag(45)
                                Text("60 min").tag(60)
                                Text("All Night").tag(0)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal)

                        // Play / Stop
                        HStack(spacing: 16) {
                            Button {
                                if soundService.isPlaying {
                                    soundService.pause()
                                } else {
                                    soundService.play(timerMinutes: settings.soundTimerMinutes)
                                }
                            } label: {
                                Label(
                                    soundService.isPlaying ? "Pause" : "Play",
                                    systemImage: soundService.isPlaying ? "pause.fill" : "play.fill"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.cyan.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            Button {
                                soundService.stopAndClear()
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.headline)
                                    .padding()
                                    .background(.red.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Sound Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !soundService.activeSlots.isEmpty {
                        Button("Save") { showingSavePreset = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Save Preset", isPresented: $showingSavePreset) {
                TextField("Preset name", text: $presetName)
                Button("Save") {
                    if !presetName.isEmpty {
                        soundService.saveCurrentAsPreset(name: presetName, modelContext: modelContext)
                        presetName = ""
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Give your sound mix a name")
            }
        }
    }
}

// MARK: - CategoryPill

private struct CategoryPill: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.cyan.opacity(0.2) : Color.clear)
                .overlay(
                    Capsule().stroke(isSelected ? Color.cyan : Color.gray.opacity(0.3), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SoundTile

private struct SoundTile: View {
    let sound: SoundItem
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: sound.icon)
                    .font(.title2)
                    .foregroundStyle(isActive ? .cyan : .secondary)
                    .frame(width: 52, height: 52)
                    .background(isActive ? Color.cyan.opacity(0.12) : Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Text(sound.name)
                    .font(.caption2)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)

            }
        }
        .buttonStyle(.plain)
    }
}
