import AppKit
import SwiftUI

private enum Constants {
    static let radius: CGFloat = 24
    static let inset: CGFloat = 4
    static let menuRadius = radius - inset
    static let activationSize = 2 * radius
}

@main
struct CornerPreviewApp: App {
    var body: some Scene {
        WindowGroup("Agent Corner — Preview") {
            PreviewScreen()
                .frame(minWidth: 760, minHeight: 460)
        }
        .defaultSize(width: 920, height: 560)
    }
}

private struct PreviewScreen: View {
    @State private var visible = false
    @State private var showMenu = false
    @State private var delayedClose: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: .bottomTrailing) {
            Color.black
            DesktopBackground()
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: Constants.radius,
                    topTrailingRadius: 0
                ))

            if visible || showMenu {
                SessionMenu()
                    .padding(Constants.inset)
            }

            Circle()
                .fill(.orange)
                .frame(width: 5, height: 5)
                .padding(.trailing, 2)
                .padding(.bottom, 2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            Toggle("Показать меню", isOn: $showMenu)
                .toggleStyle(.checkbox)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(20)
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let corner = CGRect(x: geometry.size.width - Constants.activationSize,
                                    y: geometry.size.height - Constants.activationSize,
                                    width: Constants.activationSize, height: Constants.activationSize)
                let menu = CGRect(x: geometry.size.width - 306 - Constants.inset,
                                  y: geometry.size.height - 114 - Constants.inset,
                                  width: 306, height: 114)
                updateHover(corner.contains(location) || (visible && menu.contains(location)))
            case .ended:
                updateHover(false)
            }
        }
        }
    }

    private func updateHover(_ hovering: Bool) {
        delayedClose?.cancel()
        if hovering {
            visible = true
        } else {
            delayedClose = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                visible = false
            }
        }
    }
}

private struct DesktopBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.73, green: 0.85, blue: 1),
                             Color(red: 0.62, green: 0.66, blue: 0.92),
                             Color(red: 0.47, green: 0.39, blue: 0.69)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * 0.68))
                    path.addCurve(
                        to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.06),
                        control1: CGPoint(x: geometry.size.width * 0.35, y: geometry.size.height * 0.56),
                        control2: CGPoint(x: geometry.size.width * 0.57, y: geometry.size.height * 0.08)
                    )
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.16))
                    path.addCurve(
                        to: CGPoint(x: 0, y: geometry.size.height * 0.72),
                        control1: CGPoint(x: geometry.size.width * 0.56, y: geometry.size.height * 0.18),
                        control2: CGPoint(x: geometry.size.width * 0.34, y: geometry.size.height * 0.64)
                    )
                    path.closeSubpath()
                }
                .fill(.white.opacity(0.22))
            }
        }
    }
}

private struct SessionMenu: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SessionRow(project: "SessionMonitor", provider: "Claude Code", status: "Ждёт разрешения", waiting: true)
            Divider()
                .padding(.leading, 34)
            SessionRow(project: "DisplayCorners", provider: "Codex", status: "Выполняет тесты", waiting: false)
        }
        .frame(width: 306, height: 114)
        .glassEffect(.regular, in: UnevenRoundedRectangle(
            topLeadingRadius: Constants.menuRadius,
            bottomLeadingRadius: Constants.menuRadius,
            bottomTrailingRadius: Constants.menuRadius,
            topTrailingRadius: Constants.menuRadius
        ))
    }
}

private struct SessionRow: View {
    let project: String
    let provider: String
    let status: String
    let waiting: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(waiting ? Color.orange : Color.blue)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(verbatim: project)
                        .fontWeight(.semibold)
                    Spacer(minLength: 8)
                    if let url = Bundle.main.url(forResource: provider == "Codex" ? "codex" : "claudecode", withExtension: "png"),
                       let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 17, height: 17)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text(verbatim: provider))
                    }
                }
                Text(verbatim: status)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}
