import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
            NavigationStack { ConnectionView() }
                .tabItem {
                    Label("Connect", systemImage: "wifi")
                }

            NavigationStack { DashboardView() }
                .tabItem {
                    Label("Live", systemImage: "gauge.with.dots.needle.50percent")
                }

            NavigationStack { LiveChartView() }
                .tabItem {
                    Label("Charts", systemImage: "chart.xyaxis.line")
                }

            NavigationStack { DiagnosticsView() }
                .tabItem {
                    Label("DTCs", systemImage: "wrench.and.screwdriver")
                }

            NavigationStack { LogsView() }
                .tabItem {
                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                }

            NavigationStack { SettingsView() }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .environmentObject(environment.obdService)
        .environmentObject(environment.logStore)
    }
}
