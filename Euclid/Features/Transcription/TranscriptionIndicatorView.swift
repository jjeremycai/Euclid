//
//  EuclidCapsuleView.swift
//  Euclid
//
//  Created by Kit Langton on 1/25/25.

import Inject
import Pow
import SwiftUI

struct TranscriptionIndicatorView: View {
  @ObserveInjection var inject

  enum Status {
    case hidden
    case optionKeyPressed
    case recording
    case transcribing
    case prewarming
  }

  var status: Status
  var meter: Meter
  var style: RecordingIndicatorStyle = .notch
  var placement: RecordingIndicatorPlacement = .top

  private let transcribeBaseColor: Color = .blue

  @State private var transcribeEffect = 0

  private var isHidden: Bool {
    status == .hidden
  }

  private var shouldAnimateWaveform: Bool {
    status == .transcribing || status == .prewarming
  }

  private var accentColor: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed:
      .white.opacity(0.88)
    case .recording:
      .red.mix(with: .white, by: 0.12)
    case .transcribing:
      transcribeBaseColor.mix(with: .white, by: 0.2)
    case .prewarming:
      transcribeBaseColor.mix(with: .white, by: 0.32)
    }
  }

  private var circleBackgroundColor: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed:
      .black
    case .recording:
      .red.mix(with: .black, by: 0.5).mix(with: .red, by: meter.averagePower * 3)
    case .transcribing, .prewarming:
      transcribeBaseColor.mix(with: .black, by: 0.5)
    }
  }

  private var circleStrokeColor: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed:
      .black
    case .recording:
      Color.red.mix(with: .white, by: 0.1).opacity(0.6)
    case .transcribing, .prewarming:
      transcribeBaseColor.mix(with: .white, by: 0.1).opacity(0.6)
    }
  }

  private var circleInnerShadowColor: Color {
    switch status {
    case .hidden, .optionKeyPressed:
      .clear
    case .recording:
      .red
    case .transcribing, .prewarming:
      transcribeBaseColor
    }
  }

  private var panelBackgroundColor: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed:
      Color.white.opacity(0.94)
    case .recording:
      Color.white.opacity(0.96)
    case .transcribing, .prewarming:
      Color.white.opacity(0.95)
    }
  }

  private var panelBorderColor: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed:
      Color.black.opacity(0.08)
    case .recording:
      accentColor.opacity(0.2)
    case .transcribing, .prewarming:
      accentColor.opacity(0.16)
    }
  }

  private var panelShadowColor: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed:
      Color.black.opacity(0.08)
    case .recording:
      accentColor.opacity(0.16)
    case .transcribing, .prewarming:
      accentColor.opacity(0.12)
    }
  }

  private var panelIconBackgroundColor: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed:
      Color.black.opacity(0.06)
    case .recording:
      accentColor.opacity(0.14)
    case .transcribing, .prewarming:
      accentColor.opacity(0.12)
    }
  }

  private var notchBackgroundColor: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed, .recording, .transcribing, .prewarming:
      Color.black.opacity(0.98)
    }
  }

  private var notchBorderColor: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed:
      Color.white.opacity(0.08)
    case .recording:
      accentColor.opacity(0.28)
    case .transcribing, .prewarming:
      accentColor.opacity(0.2)
    }
  }

  var body: some View {
    ZStack {
      indicatorShape

      if status == .prewarming {
        Text("Model prewarming...")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(Color.black.opacity(0.8))
          )
          .offset(y: tooltipOffset)
          .transition(.opacity)
          .zIndex(2)
      }
    }
    .enableInjection()
  }

  @ViewBuilder
  private var indicatorShape: some View {
    switch style {
    case .circle:
      circleIndicator
    case .panel:
      panelIndicator
    case .notch:
      notchIndicator
    }
  }

  private var circleIndicator: some View {
    Circle()
      .fill(circleBackgroundColor.shadow(.inner(color: circleInnerShadowColor, radius: 5)))
      .overlay {
        Circle()
          .stroke(circleStrokeColor, lineWidth: 1)
          .blendMode(.screen)
      }
      .overlay(alignment: .center) {
        Circle()
          .fill(Color.red.opacity(status == .recording ? max(0.2, normalizedAveragePower) : 0))
          .blur(radius: 2)
          .blendMode(.screen)
          .padding(2)
      }
      .overlay(alignment: .center) {
        Circle()
          .fill(Color.white.opacity(status == .recording ? max(0.18, normalizedAveragePower * 0.5) : 0))
          .blur(radius: 1)
          .blendMode(.screen)
          .padding(3)
      }
      .overlay(alignment: .center) {
        GeometryReader { proxy in
          Circle()
            .fill(Color.red.opacity(status == .recording ? max(0.2, normalizedPeakPower * 0.5) : 0))
            .frame(width: max(proxy.size.width * (normalizedPeakPower + 0.5), 0), height: proxy.size.height, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
            .blur(radius: 3)
            .blendMode(.screen)
        }
        .padding(2)
      }
      .frame(
        width: status == .recording ? 34 : 28,
        height: status == .recording ? 34 : 28
      )
      .shadow(color: status == .recording ? .red.opacity(normalizedAveragePower) : .red.opacity(0), radius: 6)
      .shadow(color: status == .recording ? .red.opacity(normalizedAveragePower * 0.5) : .red.opacity(0), radius: 12)
      .modifier(IndicatorVisibility(status: status))
      .changeEffect(.glow(color: .red.opacity(0.5), radius: 8), value: status)
      .changeEffect(.shine(angle: .degrees(0), duration: 0.6), value: transcribeEffect)
      .compositingGroup()
      .task(id: animatedWaveformTaskKey) {
        await animateWaveformIfNeeded()
      }
  }

  private var panelIndicator: some View {
    RoundedRectangle(cornerRadius: 19, style: .continuous)
      .fill(panelBackgroundColor)
      .overlay {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
          .stroke(panelBorderColor, lineWidth: 1)
      }
      .overlay {
        HStack(spacing: 11) {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(panelIconBackgroundColor)
            .frame(width: 28, height: 28)
            .overlay {
              Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor.opacity(status == .optionKeyPressed ? 0.6 : 0.94))
            }

          waveformRow(
            tint: accentColor,
            track: Color.black.opacity(0.1),
            minHeight: 6,
            maxHeight: 18,
            barWidth: 3.75,
            barSpacing: 3.25
          )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
      }
      .frame(width: 230, height: 58)
      .shadow(color: Color.black.opacity(0.1), radius: 18, y: 8)
      .shadow(color: panelShadowColor, radius: 11)
      .modifier(IndicatorVisibility(status: status))
      .changeEffect(.shine(angle: .degrees(0), duration: 0.7), value: transcribeEffect)
      .compositingGroup()
      .task(id: animatedWaveformTaskKey) {
        await animateWaveformIfNeeded()
      }
  }

  private var notchIndicator: some View {
    Group {
      if placement == .top {
        UnevenRoundedRectangle(
          cornerRadii: .init(topLeading: 0, bottomLeading: 11, bottomTrailing: 11, topTrailing: 0),
          style: .continuous
        )
        .fill(notchBackgroundColor)
        .overlay {
          UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 0, bottomLeading: 11, bottomTrailing: 11, topTrailing: 0),
            style: .continuous
          )
          .stroke(notchBorderColor, lineWidth: 1)
        }
      } else {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(notchBackgroundColor)
          .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .stroke(notchBorderColor, lineWidth: 1)
          }
      }
    }
    .overlay {
      HStack(spacing: 9) {
        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
          .fill(Color.white.opacity(0.08))
          .frame(width: 16, height: 12)
          .overlay {
            Image(systemName: iconName)
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(Color.white.opacity(0.92))
          }

        waveformRow(
          tint: accentColorForNotch,
          track: Color.white.opacity(0.08),
          minHeight: 3.5,
          maxHeight: 10,
          barWidth: notchWaveformBarWidth,
          barSpacing: notchWaveformBarSpacing,
          barCount: notchWaveformBarCount
        )
        .frame(width: notchWaveformWidth)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .offset(x: -2)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    }
    .frame(width: 148, height: 30)
    .shadow(color: Color.black.opacity(0.15), radius: 9, y: 3)
    .modifier(IndicatorVisibility(status: status))
    .changeEffect(.shine(angle: .degrees(0), duration: 0.7), value: transcribeEffect)
    .compositingGroup()
    .task(id: animatedWaveformTaskKey) {
      await animateWaveformIfNeeded()
    }
  }

  private var accentColorForNotch: Color {
    switch status {
    case .hidden:
      .clear
    case .optionKeyPressed:
      .white.opacity(0.9)
    case .recording:
      accentColor
    case .transcribing, .prewarming:
      accentColor.mix(with: .white, by: 0.25)
    }
  }

  private var normalizedAveragePower: CGFloat {
    min(1, meter.averagePower * 3)
  }

  private var normalizedPeakPower: CGFloat {
    min(1, meter.peakPower * 3)
  }

  private var iconName: String {
    switch status {
    case .prewarming:
      "bolt.fill"
    case .transcribing:
      "waveform"
    case .recording:
      "mic.fill"
    case .optionKeyPressed:
      "keyboard"
    case .hidden:
      "waveform"
    }
  }

  private var animatedWaveformTaskKey: String {
    "\(status)-\(style)"
  }

  private var tooltipOffset: CGFloat {
    switch style {
    case .circle:
      -34
    case .panel:
      -48
    case .notch:
      -36
    }
  }

  private let notchWaveformBarCount = 14
  private let notchWaveformBarWidth: CGFloat = 2.5
  private let notchWaveformBarSpacing: CGFloat = 2

  private var notchWaveformWidth: CGFloat {
    (CGFloat(notchWaveformBarCount) * notchWaveformBarWidth)
      + (CGFloat(max(notchWaveformBarCount - 1, 0)) * notchWaveformBarSpacing)
  }

  @ViewBuilder
  private func waveformRow(
    tint: Color,
    track: Color,
    minHeight: CGFloat,
    maxHeight: CGFloat,
    barWidth: CGFloat,
    barSpacing: CGFloat,
    barCount: Int = 18
  ) -> some View {
    HStack(alignment: .center, spacing: barSpacing) {
      ForEach(0..<barCount, id: \.self) { index in
        Capsule()
          .fill(track)
          .overlay {
            Capsule()
              .fill(tint.opacity(isHidden ? 0 : 0.95))
              .frame(height: waveformBarHeight(index: index, minHeight: minHeight, maxHeight: maxHeight))
          }
          .frame(width: barWidth, height: maxHeight)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: meter)
    .animation(.linear(duration: 0.22), value: transcribeEffect)
  }

  private func waveformBarHeight(index: Int, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
    let phase = Double(index) * 0.7 + Double(transcribeEffect) * 0.55
    let animatedLevel = 0.5 + (sin(phase) * 0.5)
    let offsetLevel = 0.5 + (sin(Double(index) * 1.35 + Double(transcribeEffect) * 0.2) * 0.5)

    let level: CGFloat
    switch status {
    case .hidden:
      level = 0
    case .optionKeyPressed:
      level = CGFloat(0.16 + offsetLevel * 0.12)
    case .recording:
      let liveLevel = min(1, (normalizedAveragePower * 0.7) + (normalizedPeakPower * 0.3))
      level = CGFloat(max(0.18, min(1, liveLevel * CGFloat(0.55 + animatedLevel * 0.7))))
    case .transcribing:
      level = CGFloat(0.28 + animatedLevel * 0.58)
    case .prewarming:
      level = CGFloat(0.18 + animatedLevel * 0.42)
    }

    return minHeight + ((maxHeight - minHeight) * level)
  }

  @MainActor
  private func animateWaveformIfNeeded() async {
    guard shouldAnimateWaveform else { return }

    while shouldAnimateWaveform, !Task.isCancelled {
      transcribeEffect += 1
      try? await Task.sleep(for: .seconds(0.22))
    }
  }
}

private struct IndicatorVisibility: ViewModifier {
  let status: TranscriptionIndicatorView.Status

  func body(content: Content) -> some View {
    content
      .opacity(status == .hidden ? 0 : 1)
      .scaleEffect(status == .hidden ? 0.88 : 1)
      .blur(radius: status == .hidden ? 6 : 0)
      .animation(.bouncy(duration: 0.3), value: status)
  }
}

#Preview("Indicators") {
  VStack(spacing: 20) {
    TranscriptionIndicatorView(
      status: .recording,
      meter: .init(averagePower: 0.45, peakPower: 0.8),
      style: .panel
    )
    TranscriptionIndicatorView(
      status: .transcribing,
      meter: .init(averagePower: 0, peakPower: 0),
      style: .notch
    )
    TranscriptionIndicatorView(
      status: .recording,
      meter: .init(averagePower: 0.4, peakPower: 0.7),
      style: .circle
    )
  }
  .padding(40)
  .background(Color.black.opacity(0.06))
}
