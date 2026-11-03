import SwiftUI

/// The floating header: a glass progress orb, a headline, and morphing glass actions.
struct HeroHeader: View {
    @Environment(UpdateCenter.self) private var center
    @Namespace private var glass

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ProgressOrb()

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(subheadline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 12)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 10) {
                    if center.isBusy {
                        Label {
                            Text(center.phase == .scanning ? "Scanning…" : "Checking \(center.checkedCount) of \(center.apps.count)")
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        } icon: {
                            ProgressView().controlSize(.small)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("status", in: glass)
                    } else {
                        // Full labels when there's room, icons when the inspector squeezes the header.
                        ViewThatFits(in: .horizontal) {
                            actions(labelStyle: .titleAndIcon)
                            actions(labelStyle: .iconOnly)
                        }
                    }
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .animation(.bouncy, value: center.isBusy)
        .animation(.snappy, value: center.checkedCount)
    }

    private func actions(labelStyle: some LabelStyle) -> some View {
        HStack(spacing: 10) {
            let brewCount = center.brewUpgradeable.count
            if brewCount > 0 {
                Button {
                    center.upgradeAllWithHomebrew()
                } label: {
                    Label("Upgrade \(brewCount) with Homebrew", systemImage: "mug.fill")
                }
                .buttonStyle(.glassProminent)
                .glassEffectID("brew", in: glass)
                .help("Run brew upgrade for all \(brewCount) Homebrew-managed apps with updates")
            }
            Button {
                Task { await center.refresh(forceCatalogue: true) }
            } label: {
                Label("Check Now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .glassEffectID("status", in: glass)
            .help("Check every app for updates (⌘R)")
        }
        .labelStyle(labelStyle)
        .fixedSize()
    }

    private var headline: String {
        switch center.phase {
        case .scanning: return "Looking around…"
        case .checking: return "Checking for updates"
        case .idle:
            let count = center.updates.count
            if center.lastChecked == nil { return "Welcome to Freshly" }
            return count == 0 ? "Everything's fresh" : "\(count) update\(count == 1 ? "" : "s") available"
        }
    }

    private var subheadline: String {
        if center.isBusy { return "Asking the App Store, Sparkle feeds, Electron feeds and Homebrew." }
        guard let last = center.lastChecked else { return "Press Check Now to scan your Applications folder." }
        let unknown = center.apps(matching: .unknown).count
        return "\(center.apps.count) apps · \(unknown) without an update feed · checked \(last.formatted(.relative(presentation: .named)))"
    }
}

/// A glass orb with a gradient ring that fills as apps are checked.
struct ProgressOrb: View {
    @Environment(UpdateCenter.self) private var center

    var body: some View {
        let count = center.updates.count
        let allFresh = !center.isBusy && count == 0 && center.lastChecked != nil

        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 7)
            Circle()
                .trim(from: 0, to: center.isBusy ? max(center.progress, 0.02) : 1)
                .stroke(
                    AngularGradient(colors: [.mint, .cyan, .blue, .purple, .mint], center: .center),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: center.progress)

            Group {
                if center.isBusy {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: true)
                } else if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText(value: Double(count)))
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.green.gradient)
                        .symbolEffect(.bounce, value: center.lastChecked)
                }
            }
            .transition(.blurReplace)
        }
        .frame(width: 64, height: 64)
        .padding(8)
        .glassEffect(.regular.interactive(), in: .circle)
        .overlay { SparkleBurst(trigger: center.lastChecked, active: allFresh) }
        .animation(.bouncy, value: center.isBusy)
    }
}

/// A little confetti of sparkles that pops when a check finishes with nothing to update.
struct SparkleBurst: View {
    let trigger: Date?
    let active: Bool

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Angle.degrees(Double(index) / 8 * 360)
                Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                    .font(.system(size: index.isMultiple(of: 2) ? 12 : 7))
                    .foregroundStyle(index.isMultiple(of: 3) ? Color.mint : index.isMultiple(of: 2) ? .cyan : .yellow)
                    .phaseAnimator([0.0, 1.0, 1.6], trigger: trigger) { content, phase in
                        content
                            .offset(x: cos(angle.radians) * 34 * phase, y: sin(angle.radians) * 34 * phase)
                            .scaleEffect(phase == 1 ? 1.2 : 0.4)
                            .opacity(active && phase == 1 ? 1 : 0)
                    } animation: { phase in
                        phase == 1 ? .spring(duration: 0.45, bounce: 0.5) : .easeOut(duration: 0.5)
                    }
            }
        }
        .allowsHitTesting(false)
    }
}
