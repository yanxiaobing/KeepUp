import SwiftUI

struct RunningSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Default(.runningSettings) private var settings
    private var kind: RunningKind { model.running.session?.kind ?? model.running.selectedKind }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("runningSettings.prepare", isOn: $settings.confirmBeforeStart)
                        .accessibilityIdentifier("runningSettings.prepare")
                } footer: { Text("runningSettings.prepareHint") }
                if kind != .cycling {
                    Section("runningSettings.defaultKind") {
                        ForEach([RunningKind.outdoor, .indoor], id: \.self) { value in
                            choice(LocalizedStringKey(value.titleKey), selected: settings.defaultRunningKind == value) {
                                settings.defaultKind = value
                            }.accessibilityIdentifier("runningSettings.kind.\(value.rawValue)")
                        }
                    }
                }
                Section {
                    Toggle("runningSettings.countdown", isOn: $settings.countdown).accessibilityIdentifier("runningSettings.countdown")
                    Toggle("runningSettings.voice", isOn: $settings.voice).accessibilityIdentifier("runningSettings.voice")
                    Toggle("runningSettings.autoPause", isOn: $settings.autoPause).accessibilityIdentifier("runningSettings.autoPause")
                    Toggle("runningSettings.autoLock", isOn: $settings.autoLock).accessibilityIdentifier("runningSettings.autoLock")
                    Toggle("runningSettings.keepScreenOn", isOn: $settings.keepScreenOn).accessibilityIdentifier("runningSettings.keepScreenOn")
                    NavigationLink {
                        intervalPicker
                    } label: {
                        settingRow("runningSettings.interval", image: "setting_icon_voice", value: intervalLabel(settings.effectiveVoiceInterval))
                    }.accessibilityIdentifier("runningSettings.interval")
                    NavigationLink {
                        voicePicker
                    } label: {
                        settingRow("runningSettings.voiceStyle", image: "setting_icon_sound", value: localized(settings.voiceStyle.titleKey, locale))
                    }.accessibilityIdentifier("runningSettings.voiceStyle")
                    if kind.usesGPS {
                        NavigationLink {
                            mapPicker
                        } label: {
                            settingRow("runningSettings.map", image: "setting_icon_map", value: localized(settings.satelliteMap ? "runningSettings.satellite" : "runningSettings.standard", locale))
                        }.accessibilityIdentifier("runningSettings.map")
                    }
                } header: { Text("runningSettings.duringActivity") }
                  footer: { Text("runningSettings.autoPauseHint") }
            }.listStyle(.grouped).scrollContentBackground(.hidden)
                .background(Color(hex: 0xF6F6F6))
                .environment(\.defaultMinListRowHeight, 56)
                .navigationTitle("runningSettings.title").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("action.close") { dismiss() }.accessibilityIdentifier("runningSettings.close")
                    }
                }
        }.tint(Color(hex: 0xD5A900))
            .onChange(of: settings) { _, _ in model.refreshRunningSettings() }
            .onDisappear { model.runningVoice.stopPreview() }
    }

    private var intervalPicker: some View {
        List {
            ForEach(RunningSettings.voiceIntervals, id: \.self) { distance in
                choice(LocalizedStringKey(intervalLabel(distance)), selected: settings.effectiveVoiceInterval == distance) {
                    settings.voiceIntervalMeters = distance
                }.accessibilityIdentifier("runningSettings.interval.\(distance)")
            }
        }.listStyle(.grouped).navigationTitle("runningSettings.interval").navigationBarTitleDisplayMode(.inline)
    }

    private var voicePicker: some View {
        List {
            Section {
                ForEach(RunningVoiceStyle.allCases, id: \.self) { style in
                    HStack {
                        choice(LocalizedStringKey(style.titleKey), selected: settings.voiceStyle == style) { settings.voiceStyle = style }
                            .accessibilityIdentifier("runningSettings.voice.\(style.rawValue)")
                        Button {
                            var preview = settings
                            preview.voiceStyle = style
                            model.runningVoice.preview(settings: preview, locale: locale)
                        } label: {
                            Image(systemName: "play.circle").font(.system(size: 26)).frame(width: 44, height: 44)
                        }.buttonStyle(.borderless).accessibilityLabel(Text("runningSettings.preview"))
                            .accessibilityIdentifier("runningSettings.preview.\(style.rawValue)")
                    }
                }
            } footer: { Text("runningSettings.previewHint") }
        }.listStyle(.grouped).navigationTitle("runningSettings.voiceStyle").navigationBarTitleDisplayMode(.inline)
            .onDisappear { model.runningVoice.stopPreview() }
    }

    private var mapPicker: some View {
        List {
            choice("runningSettings.standard", selected: !settings.satelliteMap) { settings.satelliteMap = false }
                .accessibilityIdentifier("runningSettings.map.standard")
            choice("runningSettings.satellite", selected: settings.satelliteMap) { settings.satelliteMap = true }
                .accessibilityIdentifier("runningSettings.map.satellite")
        }.listStyle(.grouped).navigationTitle("runningSettings.map").navigationBarTitleDisplayMode(.inline)
    }

    private func settingRow(_ title: LocalizedStringKey, image: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(image).resizable().scaledToFit().frame(width: 22, height: 22).accessibilityHidden(true)
            Text(title).foregroundStyle(Color.primary)
            Spacer()
            Text(verbatim: value).foregroundStyle(.secondary).font(.system(size: 13))
        }
    }

    private func choice(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Color.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color(hex: 0xD5A900)) }
            }.frame(minHeight: 40).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func intervalLabel(_ meters: Int) -> String {
        (Double(meters) / 1_000).formatted(.number.locale(locale)) + " " + localized("running.kilometers", locale)
    }
}
