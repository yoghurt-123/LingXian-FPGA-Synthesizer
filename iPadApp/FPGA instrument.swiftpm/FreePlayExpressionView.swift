import SwiftUI

struct FreePlayExpressionPanel: View {
    @ObservedObject var router: FreePlayEventRouter

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("表情面板")
                    .font(.system(size: 11, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Text(router.protocolLabel)
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.accentDark)
                Spacer(minLength: 4)
                Text("App目标 · 共享FX未确认")
                    .font(.system(size: 8, weight: .semibold, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
            }

            if !router.isHardwareMode {
                notice("切换到 FPGA音箱后才能发送表情；iPad本地声音不伪装硬件表情。")
            } else if router.capabilities?.isV1 == true {
                notice("协议 v1 只支持钢琴/九鼓/六弦基础事件；表情、品位、和弦、八度和踏板未声明。")
            } else if router.capabilities == nil {
                notice("尚未收到有效能力回复；不开放表情。")
            } else {
                HStack(spacing: 5) {
                    guitarControls
                    Spacer(minLength: 2)
                }
                HStack(spacing: 5) {
                    pianoControls
                    Spacer(minLength: 2)
                    Text("CAPS 不回报效果当前值；不自动重发共享过载/混响")
                        .font(.system(size: 7, weight: .medium, design: .serif))
                        .foregroundStyle(PixelPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(7)
        .background(PixelPanelBackground(fill: PixelPalette.card, cut: 7))
        .overlay(PixelPanelShape(cut: 7).stroke(PixelPalette.accent.opacity(0.65), lineWidth: 1.2))
        .onDisappear {
            if router.isHardwareMode {
                if router.bend != .center {
                    router.setBend(.center)
                }
                if router.pedalDown {
                    _ = router.setPedal(false)
                }
            }
        }
    }

    @ViewBuilder
    private var guitarControls: some View {
        if router.supports(.guitarPalm) {
            CompactToggleChip(title: "掌根", isOn: router.palmMuted) { router.setPalm($0) }
        }
        if router.supports(.bendVibrato) {
            compactBend
            CompactToggleChip(title: "颤音", isOn: router.vibrato) { router.setVibrato($0) }
        }
        if router.supports(.glideSlide) {
            CompactToggleChip(title: "滑音", isOn: router.glide) { router.setGlide($0) }
            slideStepControl
        }
        if router.supports(.overdrive) {
            CompactTargetPair(title: "过载", target: router.overdriveTarget) { router.setOverdrive($0) }
        }
        if router.supports(.reverb) {
            CompactTargetPair(title: "混响", target: router.reverbTarget) { router.setReverb($0) }
        }
    }

    private var compactBend: some View {
        HStack(spacing: 2) {
            Text("弯音")
                .font(.system(size: 9, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            FreeBendHoldButton(title: "左-2", isActive: router.bend == .left) {
                router.setBend(.left)
            } onRelease: {
                router.setBend(.center)
            }
            Button("中") { router.setBend(.center) }
                .font(.system(size: 9, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.ink)
                .frame(width: 36, height: 30)
                .background(PixelPalette.secondary)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 1))
                .buttonStyle(.plain)
            FreeBendHoldButton(title: "右+2", isActive: router.bend == .right) {
                router.setBend(.right)
            } onRelease: {
                router.setBend(.center)
            }
        }
    }

    private var slideStepControl: some View {
        HStack(spacing: 2) {
            Text("滑时")
                .font(.system(size: 9, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            Button("-") { router.setSlideStep(router.slideStep - 1) }
                .compactStepButton()
            Text("\(router.slideStep)档 \(router.slideMilliseconds)ms")
                .font(.system(size: 8, weight: .bold, design: .serif))
                .foregroundStyle(PixelPalette.accentDark)
                .frame(minWidth: 66)
            Button("+") { router.setSlideStep(router.slideStep + 1) }
                .compactStepButton()
        }
    }

    @ViewBuilder
    private var pianoControls: some View {
        if router.supports(.dampingPedal) {
            HStack(spacing: 3) {
                Text("钢琴")
                    .font(.system(size: 9, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                CompactToggleChip(title: "阻尼", isOn: router.damping) { router.setDamping($0) }
                FreePedalHoldButton(
                    isActive: router.pedalDown,
                    isEnabled: router.damping
                ) {
                    _ = router.setPedal(true)
                } onRelease: {
                    _ = router.setPedal(false)
                }
                Button("释放踏板音") { router.releasePendingPedal() }
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                    .padding(.horizontal, 5)
                    .frame(height: 30)
                    .background(PixelPalette.secondary)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 1))
                    .buttonStyle(.plain)
                    .disabled(!router.damping)
                    .opacity(router.damping ? 1 : 0.42)
            }
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .serif))
            .foregroundStyle(PixelPalette.miss)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactToggleChip: View {
    let title: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 9, weight: .heavy, design: .serif))
                Text(isOn ? "开" : "关")
                    .font(.system(size: 8, weight: .bold, design: .serif))
            }
            .foregroundStyle(isOn ? PixelPalette.card : PixelPalette.ink)
            .padding(.horizontal, 5)
            .frame(height: 30)
            .background(isOn ? PixelPalette.accent : PixelPalette.secondary)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct CompactTargetPair: View {
    let title: String
    let target: Bool?
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 9, weight: .heavy, design: .serif))
                    .foregroundStyle(PixelPalette.ink)
                Text(target.map { $0 ? "App:开" : "App:关" } ?? "未确认")
                    .font(.system(size: 7, weight: .bold, design: .serif))
                    .foregroundStyle(target == nil ? PixelPalette.miss : PixelPalette.muted)
            }
            Button("0") { onChange(false) }
                .font(.system(size: 9, weight: .heavy, design: .serif))
                .foregroundStyle(target == false ? PixelPalette.card : PixelPalette.ink)
                .frame(width: 25, height: 30)
                .background(target == false ? PixelPalette.accentDark : PixelPalette.secondary)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 1))
                .buttonStyle(.plain)
            Button("1") { onChange(true) }
                .font(.system(size: 9, weight: .heavy, design: .serif))
                .foregroundStyle(target == true ? PixelPalette.card : PixelPalette.ink)
                .frame(width: 25, height: 30)
                .background(target == true ? PixelPalette.accentDark : PixelPalette.secondary)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 1))
                .buttonStyle(.plain)
        }
    }
}

struct FreeBendHoldButton: View {
    let title: String
    let isActive: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var held = false

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy, design: .serif))
            .foregroundStyle(isActive ? PixelPalette.card : PixelPalette.ink)
            .frame(width: 42, height: 30)
            .background(isActive ? PixelPalette.accentDark : PixelPalette.secondary)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(isActive ? PixelPalette.accentDark : PixelPalette.line, lineWidth: isActive ? 2 : 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !held else { return }
                        held = true
                        onPress()
                    }
                    .onEnded { _ in
                        held = false
                        onRelease()
                    }
            )
            .onDisappear {
                if held {
                    held = false
                    onRelease()
                }
            }
    }
}

struct FreePedalHoldButton: View {
    let isActive: Bool
    let isEnabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var held = false

    var body: some View {
        Text("踏板")
            .font(.system(size: 9, weight: .heavy, design: .serif))
            .foregroundStyle(isActive ? PixelPalette.card : PixelPalette.ink)
            .frame(width: 48, height: 30)
            .background(isActive ? PixelPalette.accentDark : PixelPalette.secondary)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !held else { return }
                        held = true
                        onPress()
                    }
                    .onEnded { _ in
                        guard isEnabled else { return }
                        held = false
                        onRelease()
                    }
            )
            .onDisappear {
                if held {
                    held = false
                    onRelease()
                }
            }
    }
}

private struct CompactStepButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .heavy, design: .serif))
            .foregroundStyle(PixelPalette.ink)
            .frame(width: 25, height: 30)
            .background(PixelPalette.secondary)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(PixelPalette.line, lineWidth: 1))
    }
}

private extension View {
    func compactStepButton() -> some View {
        modifier(CompactStepButtonModifier())
    }
}
