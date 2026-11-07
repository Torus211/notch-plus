//
//  InlineHUDs.swift
//  boringNotch
//
//  Created by Richard Kunkli on 14/09/2024.
//

import SwiftUI
import Defaults

struct InlineHUD: View {
    @Default(.systemEventIndicatorUseAccent) private var useAccent
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    var body: some View {
        if type == .volume {
            islandVolume
        } else {
        HStack {
            HStack(spacing: 5) {
                Group {
                    switch (type) {
                        case .volume:
                            if icon.isEmpty {
                                Image(systemName: SpeakerSymbol(value))
                                    .contentTransition(.interpolate)
                                    .symbolVariant(value > 0 ? .none : .slash)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            } else {
                                Image(systemName: icon)
                                    .contentTransition(.interpolate)
                                    .opacity(value.isZero ? 0.6 : 1)
                                    .scaleEffect(value.isZero ? 0.85 : 1)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            }
                        case .brightness:
                            Image(systemName: BrightnessSymbol(value))
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .backlight:
                            Image(systemName: value > 0.5 ? "light.max" : "light.min")
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .mic:
                            Image(systemName: "mic")
                                .symbolRenderingMode(.hierarchical)
                                .symbolVariant(value > 0 ? .none : .slash)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        default:
                            EmptyView()
                    }
                }
                .foregroundStyle(.white)
                .symbolVariant(.fill)
                
                Text(Type2Name(type))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
            }
            .frame(width: 100 - (hoverAnimation ? 0 : 12) + gestureProgress / 2, height: vm.notchSize.height - (hoverAnimation ? 0 : 12), alignment: .leading)
            
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)
            
            HStack {
                if (type == .mic) {
                    Text(value.isZero ? "muted" : "unmuted")
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentTransition(.interpolate)
                } else {
                        HStack {
                        DraggableProgressBar(value: $value, onChange: { v in
                            if type == .volume {
                                VolumeManager.shared.setAbsolute(Float32(v))
                            } else if type == .brightness {
                                BrightnessManager.shared.setAbsolute(value: Float32(v))
                            }
                        })
                        if (type == .volume && value.isZero) {
                            Text("muted")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .padding(.trailing, 4)
            .frame(width: 100 - (hoverAnimation ? 0 : 12) + gestureProgress / 2, height: vm.closedNotchSize.height - (hoverAnimation ? 0 : 12), alignment: .center)
        }
        .frame(height: vm.closedNotchSize.height + (hoverAnimation ? 8 : 0), alignment: .center)
    }
    
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAdjustingVolume = false
    private var volumeLevel: CGFloat { min(1, max(0, value)) }

    private var islandVolume: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon.isEmpty
                    ? (volumeLevel == 0 ? "speaker.slash.fill" : SpeakerSymbol(volumeLevel) + ".fill")
                    : icon)
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22)
                Text(volumeLevel == 0 ? "Muted" : "Volume")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.opacity)
            }
            .frame(width: 104, alignment: .leading)

            // Keep all controls clear of the physical camera cutout.
            Color.clear.frame(width: vm.closedNotchSize.width - 20)

            HStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule()
                            .fill(LinearGradient(colors: [(useAccent ? Color.accentColor : .white).opacity(0.75), useAccent ? Color.accentColor : .white],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * volumeLevel)
                    }
                    .frame(height: isAdjustingVolume ? 7 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isAdjustingVolume = true
                            setVolume(gesture.location.x / max(1, geometry.size.width), duration: 60)
                        }
                        .onEnded { _ in
                            isAdjustingVolume = false
                            setVolume(volumeLevel, duration: 1.8)
                        })
                }
                .frame(height: 24)
                Text("\(Int((volumeLevel * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .frame(width: 25, alignment: .trailing)
            }
            .frame(width: 104)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int((volumeLevel * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: setVolume(volumeLevel + 0.05, duration: 1.8)
                case .decrement: setVolume(volumeLevel - 0.05, duration: 1.8)
                @unknown default: break
                }
            }
        }
        .foregroundStyle(.white)
        .frame(height: vm.effectiveClosedNotchHeight)
        .animation(reduceMotion || isAdjustingVolume ? nil : .smooth(duration: 0.18), value: value)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: isAdjustingVolume)
    }

    private func setVolume(_ level: CGFloat, duration: TimeInterval) {
        let level = min(1, max(0, level))
        value = level
        VolumeManager.shared.setAbsolute(Float32(level))
        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume,
            duration: duration, value: level)
    }

    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker"
            case 0...0.3:
                return "speaker.wave.1"
            case 0.3...0.8:
                return "speaker.wave.2"
            case 0.8...1:
                return "speaker.wave.3"
            default:
                return "speaker.wave.2"
        }
    }
    
    func BrightnessSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0...0.6:
                return "sun.min"
            case 0.6...1:
                return "sun.max"
            default:
                return "sun.min"
        }
    }
    
    func Type2Name(_ type: SneakContentType) -> String {
        switch(type) {
            case .volume:
                return "Volume"
            case .brightness:
                return "Brightness"
            case .backlight:
                return "Backlight"
            case .mic:
                return "Mic"
            default:
                return ""
        }
    }
}

#Preview {
    InlineHUD(type: .constant(.brightness), value: .constant(0.4), icon: .constant(""), hoverAnimation: .constant(false), gestureProgress: .constant(0))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(BoringViewModel())
}
