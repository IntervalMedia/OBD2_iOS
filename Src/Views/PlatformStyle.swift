import SwiftUI

extension Color {
    static var appActionForeground: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
        })
        #else
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
        #endif
    }

    static var appAccent: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.36, green: 0.82, blue: 0.75, alpha: 1)
                : NSColor(red: 0.05, green: 0.37, blue: 0.34, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.36, green: 0.82, blue: 0.75, alpha: 1)
                : UIColor(red: 0.05, green: 0.37, blue: 0.34, alpha: 1)
        })
        #endif
    }

    static var appGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var appCardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

/// Solid content surfaces keep scrolling readings legible. Glass is reserved for chrome.
struct AppCardStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            configuration.label
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.secondary)
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct AppSectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.title2, design: .rounded, weight: .semibold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SessionStatusView: View {
    let title: String
    let detail: String
    let active: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: active ? "checkmark" : "link")
                .font(.headline)
                .foregroundStyle(active ? Color.appAccent : Color.secondary)
                .frame(width: 24, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func appScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.appGroupedBackground)
            .formStyle(.grouped)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    /// Only use outside scrolling content, such as a safe-area action bar.
    @ViewBuilder
    func appChromeButton(prominent: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, *) {
            if prominent {
                self.controlSize(.large).buttonStyle(.glassProminent).buttonBorderShape(.capsule).foregroundStyle(Color.appActionForeground)
            } else {
                self.controlSize(.large).buttonStyle(.glass).buttonBorderShape(.capsule)
            }
        } else if prominent {
            self.controlSize(.large).buttonStyle(.borderedProminent).buttonBorderShape(.capsule).foregroundStyle(Color.appActionForeground)
        } else {
            self.controlSize(.large).buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder
    func appBottomBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.safeAreaBar(edge: .bottom) {
                GlassEffectContainer(spacing: 16) {
                    content().padding(.horizontal, 20).padding(.vertical, 12)
                }
            }
        } else {
            self.safeAreaInset(edge: .bottom, spacing: 0) {
                content().padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.appCardBackground)
            }
        }
    }

    @ViewBuilder
    func adapterHostInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).keyboardType(.URL)
        #else
        self
        #endif
    }

    @ViewBuilder
    func adapterPortInput() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
