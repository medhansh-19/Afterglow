import AfterglowCore
import SwiftUI

struct ClockSettings: View {
  let lyricColor: Color
  @Environment(\.dismiss) private var dismiss
  @AppStorage("afterglow.clock") private var enabled = true
  @AppStorage("afterglow.clockStyle") private var style = "Minimal"
  @AppStorage("afterglow.clockColor") private var colorName = "Off-white"
  @AppStorage("afterglow.clockFollowLyrics") private var followsLyrics = false
  @AppStorage("afterglow.clockFormat") private var format = "System"
  @AppStorage("afterglow.clockSeconds") private var seconds = false
  @AppStorage("afterglow.clockDate") private var showDate = true
  @AppStorage("afterglow.clockSize") private var size = 1.0
  @State private var showWheel = false
  @State private var colorLabel = ""
  private var clockColor: Color { followsLyrics ? lyricColor : Tint.resolve(colorName) }
  private var customColor: Binding<Color> {
    Binding(get: { Tint.resolve(colorName) }, set: { value in
      if let hex = GlowColorLibrary.hex(from: value) { colorName = hex }
    })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Your clock").font(.system(size: 20, weight: .semibold))
        Spacer()
        Toggle("Show clock", isOn: $enabled).toggleStyle(.switch).controlSize(.small)
      }
      Group {
        LiveClockDisplay(lyricColor: lyricColor)
          .frame(maxWidth: .infinity).frame(height: 156)
          .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 14))
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Style").font(.headline)
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(ClockStyle.allCases) { item in
              Button { style = item.rawValue; enabled = true } label: {
                VStack(spacing: 4) {
                  ClockFace(date: Date(), style: item, color: clockColor, format: format,
                            seconds: false, showDate: false, scale: 0.45)
                    .frame(height: 44)
                  Text(item.rawValue).font(.system(size: 11, weight: .medium))
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
                  .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                  .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(style == item.rawValue ? clockColor : .white.opacity(0.1), lineWidth: style == item.rawValue ? 1.5 : 1))
              }.buttonStyle(.plain).accessibilityLabel("\(item.rawValue) clock")
                .accessibilityValue(style == item.rawValue ? "Selected" : "")
            }
          }
          Divider()
          HStack {
            Text("Size")
            Slider(value: $size, in: 0.7...1.4) { Text("Clock size") }.labelsHidden()
            Text("\(Int(size * 100))%").monospacedDigit().frame(width: 38)
          }
          Picker("Time format", selection: $format) {
            ForEach(["System", "12-hour", "24-hour"], id: \.self) { Text($0).tag($0) }
          }
          Toggle("Show date", isOn: $showDate)
          Toggle("Show seconds", isOn: $seconds)
          Divider()
          Toggle("Match lyric color", isOn: $followsLyrics)
          if !followsLyrics {
            GlowColorMenuPicker(selection: $colorName)
            Button("Custom clock color…") { showWheel = true }
              .popover(isPresented: $showWheel) { colorEditor }
          }
          Text("Saved automatically. Use Save song scene to keep this clock for a particular song.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.trailing, 4)
      }
      HStack {
        Button("Reset clock") { ClockPreferences.write(ClockAppearance()) }
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 400, height: 680)
      .background(AppearanceNightSky(tint: clockColor)).preferredColorScheme(.dark)
      .font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
      .onExitCommand { dismiss() }
  }

  private var colorEditor: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Clock color").font(.headline)
      GlowColorWheel(color: customColor)
      Text(GlowColorLibrary.hex(from: Tint.resolve(colorName)) ?? "").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
      TextField("Color name (optional)", text: $colorLabel).textFieldStyle(.roundedBorder)
        .accessibilityLabel("Name for saved clock color")
      HStack {
        Button("Done") { showWheel = false }
        Spacer()
        Button("Save color") {
          _ = GlowColorLibrary.shared.save(hex: colorName, name: colorLabel)
          colorLabel = ""; showWheel = false
        }
      }
    }.padding(20).frame(width: 280).background(AppearanceNightSky(tint: Tint.resolve(colorName)))
  }
}
