import SwiftUI

struct WakeUpIntroView: View {
    let onClose: () -> Void
    let onConfirm: (Bool) -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.6).onTapGesture(perform: onClose)
                VStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        Image("early_card_pop_pic").resizable().frame(height: 110)
                        Text("wake.introTitle").font(.system(size: 18, weight: .bold)).foregroundStyle(.white).padding(.leading, 35)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        Text("wake.rule").font(.system(size: 15)).lineSpacing(7)
                        Text("wake.alarmHint").font(.system(size: 13)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    Divider()
                    HStack(spacing: 0) {
                        Button("action.ok") { onConfirm(false) }.foregroundStyle(.secondary).accessibilityIdentifier("wake.activate")
                            .frame(maxWidth: .infinity)
                        Divider()
                        Button("wake.setAlarm") { onConfirm(true) }.foregroundStyle(Color(hex: 0xF5D039)).accessibilityIdentifier("wake.setAlarm")
                            .frame(maxWidth: .infinity)
                    }.font(.system(size: 15)).frame(height: 60)
                }.frame(width: geometry.size.width-40, height: 330).background(.white)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.ignoresSafeArea()
    }
}

struct WakeUpClock: View {
    let time: Date
    let timeZoneID: String
    var compact = false
    var body: some View {
        GeometryReader { geometry in
            let prefix = compact ? "home_wake_up_clock_" : "card_detail_wake_up_clock_"
            let angles = angles
            ZStack {
                Image(prefix + "bg").resizable().scaledToFit()
                Image(prefix + "shi_zhen").resizable().scaledToFit().rotationEffect(.degrees(angles.0))
                Image(prefix + "fen_zhen").resizable().scaledToFit().rotationEffect(.degrees(angles.1))
                Image(prefix + "miao_zhen").resizable().scaledToFit().rotationEffect(.degrees(angles.2))
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityHidden(true)
    }
    private var angles: (Double, Double, Double) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
        let h = Double(calendar.component(.hour, from: time)), m = Double(calendar.component(.minute, from: time)), s = Double(calendar.component(.second, from: time))
        return ((h.truncatingRemainder(dividingBy: 12)+m/60+s/3600)*30, (m+s/60)*6, s*6)
    }
}

struct WakeUpPoster: View {
    let entry: CheckInEntry
    let record: WakeUpRecord
    let entries: [CheckInEntry]
    let wakes: [String: WakeUpRecord]
    let locale: Locale
    private var timeText: String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = TimeZone(identifier: record.timeZoneID)
        formatter.dateFormat = entry.day == LocalDay(date: .now) ? "HH:mm:ss" : "yyyy.MM.dd HH:mm:ss"
        return formatter.string(from: record.time)
    }
    private var actualTimeText: String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = TimeZone(identifier: record.timeZoneID); formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: record.recordedAt)
    }
    private var streak: Int {
        RecordStatistics.streak(entries: entries.filter { $0.day <= entry.day && wakes[$0.id]?.isEarly == true }, today: entry.day, timeZone: TimeZone(identifier: record.timeZoneID) ?? .gmt)
    }
    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width / 375
            ZStack(alignment: .top) {
                Color.white
                KeepUpStyle.theme.opacity(0.8)
                Text(timeText).font(.system(size: 15*s)).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 15*s).padding(.top, 20*s)
                WakeUpClock(time: record.time, timeZoneID: record.timeZoneID).frame(width: 200*s, height: 200*s).padding(.top, 54*s)
                VStack(spacing: 12*s) {
                    if record.isEarly { Text(verbatim: String(format: localized("wake.streak %lld", locale), Int64(streak))).font(.system(size: 24*s)) }
                    else { Text("wake.missed").font(.system(size: 24*s)) }
                    if record.isEarly { Text("wake.encouragement").font(.system(size: 14*s)) }
                    else { Text(String(format: localized("wake.actualTime %@", locale), actualTimeText)).font(.system(size: 14*s)) }
                }.padding(.top, 274*s).padding(.horizontal, 20*s).multilineTextAlignment(.center)
                VStack { Spacer(); Image("card_details_eary").resizable().scaledToFit().padding(.bottom, 34*s) }
            }.foregroundStyle(.white).clipped()
        }
    }
}

/// Original three-column wheel, including its 60pt columns and 50pt rows.
struct WakeUpTimePicker: UIViewRepresentable {
    @Binding var selection: Date
    let scale: CGFloat
    let upperBound: Date
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView(); picker.delegate = context.coordinator; picker.dataSource = context.coordinator
        picker.accessibilityIdentifier = "wake.time"
        picker.selectRow(Calendar.current.component(.hour, from: selection), inComponent: 0, animated: false)
        picker.selectRow(Calendar.current.component(.minute, from: selection), inComponent: 2, animated: false)
        return picker
    }
    func updateUIView(_ view: UIPickerView, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        var parent: WakeUpTimePicker
        init(_ parent: WakeUpTimePicker) { self.parent = parent }
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 3 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            if component == 1 { return 1 }
            if component == 0 { return Calendar.current.component(.hour, from: parent.upperBound)+1 }
            let hour = Calendar.current.component(.hour, from: parent.selection)
            return hour == Calendar.current.component(.hour, from: parent.upperBound) ? Calendar.current.component(.minute, from: parent.upperBound)+1 : 60
        }
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { 60*parent.scale }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 50*parent.scale }
        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { component == 1 ? ":" : String(format: "%02d", row) }
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = view as? UILabel ?? UILabel(); label.textAlignment = .center
            label.text = component == 1 ? ":" : String(format: "%02d", row)
            let current = component == 1 || row == Calendar.current.component(component == 0 ? .hour : .minute, from: parent.selection)
            label.font = current ? .boldSystemFont(ofSize: 40*parent.scale) : .systemFont(ofSize: 30)
            label.textColor = current ? UIColor(white: 72/255, alpha: 1) : UIColor(white: 196/255, alpha: 1)
            return label
        }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let calendar = Calendar.current
            let hour = pickerView.selectedRow(inComponent: 0)
            let maxMinute = hour == calendar.component(.hour, from: parent.upperBound) ? calendar.component(.minute, from: parent.upperBound) : 59
            let minute = min(pickerView.selectedRow(inComponent: 2), maxMinute)
            parent.selection = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: parent.upperBound)!
            pickerView.reloadAllComponents(); pickerView.selectRow(minute, inComponent: 2, animated: false)
        }
    }
}
