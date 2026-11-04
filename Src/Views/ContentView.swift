import SwiftUI

enum AppDestination: Hashable { case connect, live, diagnostics, nissan, tools }

@MainActor
final class AppNavigation: ObservableObject {
    @Published var destination: AppDestination = .connect
    func showConnection() { destination = .connect }
    func showLive() { destination = .live }
    func showDiagnostics() { destination = .diagnostics }
    func showNissan() { destination = .nissan }
}

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var navigation = AppNavigation()

    var body: some View {
        TabView(selection: $navigation.destination) {
            Tab("Connect", systemImage: "wifi", value: AppDestination.connect) {
                NavigationStack { ConnectionView() }
            }
            Tab("Live", systemImage: "gauge.with.dots.needle.50percent", value: AppDestination.live) {
                NavigationStack { DashboardView() }
            }
            Tab("Diagnostics", systemImage: "wrench.and.screwdriver", value: AppDestination.diagnostics) {
                NavigationStack { DiagnosticsView() }
            }
            Tab("Nissan", systemImage: "car.side", value: AppDestination.nissan) {
                NavigationStack { NissanDiagnosticsView() }
            }
            Tab("Tools", systemImage: "square.grid.2x2", value: AppDestination.tools) {
                NavigationStack { ToolsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.appAccent)
        .groupBoxStyle(AppCardStyle())
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 560)
        #endif
        .environmentObject(navigation)
        .environmentObject(environment.obdService)
        .environmentObject(environment.logStore)
    }
}

private struct ToolsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { LiveChartView() } label: {
                    tool("Charts", detail: "Explore recent live readings", icon: "chart.xyaxis.line")
                }
                NavigationLink { LogsView() } label: {
                    tool("Activity", detail: "Adapter commands and responses", icon: "text.alignleft")
                }
            }
            Section {
                NavigationLink { SettingsView() } label: {
                    tool("Settings", detail: "Timing and sample storage", icon: "slider.horizontal.3")
                }
            }
        }
        .appScreen()
        .navigationTitle("Tools")
    }

    private func tool(_ title: String, detail: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.appAccent).frame(width: 28)
        }
    }
}
