//
//  ShiftWorkView.swift
//  sleep
//
//

import SwiftUI

// MARK: - Schedule Mode

enum ScheduleMode: String, CaseIterable, Identifiable {
    case regular = "Regular"
    case shiftWork = "Shift Work"
    case custom = "Custom"

    var id: String { rawValue }
}

// MARK: - Shift Pattern

struct ShiftPattern: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var bedtime: Date
    var wakeTime: Date
}

struct ShiftWorkView: View {

    @Environment(SleepSettings.self) private var settings

    @State private var scheduleMode: ScheduleMode = .regular
    @State private var shiftPatterns: [ShiftPattern] = []
    @State private var vacationMode = false
    @State private var vacationEndDate = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var perDaySchedule: [DaySchedule] = DaySchedule.defaultWeek

    private let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        Form {
            // MARK: Schedule Mode
            Section("Schedule Mode") {
                Picker("Mode", selection: $scheduleMode) {
                    ForEach(ScheduleMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: Shift Patterns
            if scheduleMode == .shiftWork {
                Section {
                    ForEach($shiftPatterns) { $pattern in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Shift Name", text: $pattern.name)
                                .font(.headline)
                            DatePicker("Bedtime", selection: $pattern.bedtime, displayedComponents: .hourAndMinute)
                            DatePicker("Wake Time", selection: $pattern.wakeTime, displayedComponents: .hourAndMinute)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteShift)

                    Button {
                        addDefaultShift()
                    } label: {
                        Label("Add Shift", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Shift Patterns")
                } footer: {
                    Text("Define your rotating shift schedule. Each pattern has its own bedtime and wake time.")
                }
            }

            // MARK: Vacation Mode
            Section {
                Toggle("Vacation Mode", isOn: $vacationMode)

                if vacationMode {
                    Text("Reminders and alarms are paused")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    DatePicker("Vacation Ends", selection: $vacationEndDate, displayedComponents: .date)
                }
            } header: {
                Text("Vacation Mode")
            } footer: {
                if vacationMode {
                    Text("All sleep reminders and alarms are disabled until your vacation ends.")
                }
            }

            // MARK: Per-Day Schedule
            if scheduleMode == .custom {
                Section {
                    ForEach(0..<7) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(weekdays[index])
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            DatePicker("Bedtime", selection: $perDaySchedule[index].bedtime, displayedComponents: .hourAndMinute)
                            DatePicker("Wake Time", selection: $perDaySchedule[index].wakeTime, displayedComponents: .hourAndMinute)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Per-Day Schedule")
                } footer: {
                    Text("Set individual bedtime and wake times for each day of the week.")
                }
            }
        }
        .navigationTitle("Shift Work & Vacation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadShiftPatterns() }
        .onChange(of: shiftPatterns) { _, _ in saveShiftPatterns() }
        .onChange(of: perDaySchedule) { _, _ in savePerDaySchedule() }
    }

    // MARK: - Shift Helpers

    private func addDefaultShift() {
        let calendar = Calendar.current
        let bedtime = calendar.date(from: DateComponents(hour: 23, minute: 0)) ?? .now
        let wakeTime = calendar.date(from: DateComponents(hour: 7, minute: 0)) ?? .now
        let newPattern = ShiftPattern(name: "New Shift", bedtime: bedtime, wakeTime: wakeTime)
        shiftPatterns.append(newPattern)
    }

    private func deleteShift(at offsets: IndexSet) {
        shiftPatterns.remove(atOffsets: offsets)
    }

    private func loadShiftPatterns() {
        if let data = UserDefaults.standard.data(forKey: "sleep_shiftPatterns"),
           let decoded = try? JSONDecoder().decode([ShiftPattern].self, from: data) {
            shiftPatterns = decoded
        }

        if let data = UserDefaults.standard.data(forKey: "sleep_perDaySchedule"),
           let decoded = try? JSONDecoder().decode([DaySchedule].self, from: data) {
            perDaySchedule = decoded
        }
    }

    private func saveShiftPatterns() {
        if let encoded = try? JSONEncoder().encode(shiftPatterns) {
            UserDefaults.standard.set(encoded, forKey: "sleep_shiftPatterns")
        }
    }

    private func savePerDaySchedule() {
        if let encoded = try? JSONEncoder().encode(perDaySchedule) {
            UserDefaults.standard.set(encoded, forKey: "sleep_perDaySchedule")
        }
    }
}

// MARK: - Day Schedule

struct DaySchedule: Identifiable, Codable, Equatable {
    var id = UUID()
    var bedtime: Date
    var wakeTime: Date

    static var defaultWeek: [DaySchedule] {
        let calendar = Calendar.current
        let bedtime = calendar.date(from: DateComponents(hour: 23, minute: 0)) ?? .now
        let wakeTime = calendar.date(from: DateComponents(hour: 7, minute: 0)) ?? .now
        return (0..<7).map { _ in DaySchedule(bedtime: bedtime, wakeTime: wakeTime) }
    }
}
