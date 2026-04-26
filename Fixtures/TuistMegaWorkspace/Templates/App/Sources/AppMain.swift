import SwiftUI
import AppCore
import CatalogFeature
import DesignSystem
import OrdersFeature
import SupportFeature

@main
struct FixtureApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Sidekick Tuist Fixture")
                        .font(.title)
                    Text("Catalog, orders, support, and design modules are linked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }
}
