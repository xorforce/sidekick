import ProjectDescription

private struct ModuleSpec {
    let name: String
    let moduleDependencies: [String]
    let externalDependencies: [String]
    let sourcePath: String
}

private struct AppSpec {
    let name: String
    let moduleDependencies: [String]
}

private let moduleSpecs: [ModuleSpec] = [
    .init(name: "AppCore", moduleDependencies: [], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "DesignSystem", moduleDependencies: [], externalDependencies: ["Kingfisher", "SnapKit"], sourcePath: "Templates/Modules/DesignSystem/DesignSystemModule.swift"),
    .init(name: "NetworkingKit", moduleDependencies: [], externalDependencies: [], sourcePath: "Templates/Modules/Networking/NetworkingModule.swift"),
    .init(name: "AnalyticsKit", moduleDependencies: ["NetworkingKit"], externalDependencies: [], sourcePath: "Templates/Modules/Analytics/AnalyticsModule.swift"),
    .init(name: "AuthFeature", moduleDependencies: ["AppCore", "NetworkingKit"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "CatalogFeature", moduleDependencies: ["AppCore", "NetworkingKit", "DesignSystem"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "CartFeature", moduleDependencies: ["AppCore", "DesignSystem"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "CheckoutFeature", moduleDependencies: ["CartFeature", "DesignSystem", "NetworkingKit", "PaymentsFeature"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "OrdersFeature", moduleDependencies: ["AnalyticsKit", "AppCore", "NetworkingKit"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "ProfileFeature", moduleDependencies: ["AuthFeature", "DesignSystem"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "SearchFeature", moduleDependencies: ["AnalyticsKit", "CatalogFeature"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "InventoryFeature", moduleDependencies: ["AnalyticsKit", "AppCore", "NetworkingKit"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "PaymentsFeature", moduleDependencies: ["AnalyticsKit", "NetworkingKit"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "MapsFeature", moduleDependencies: ["AppCore"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "NotificationsFeature", moduleDependencies: ["AnalyticsKit", "AppCore"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "SupportFeature", moduleDependencies: ["AppCore", "DesignSystem", "NetworkingKit"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "ExperimentationKit", moduleDependencies: ["AnalyticsKit"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
    .init(name: "SharedMocks", moduleDependencies: ["AppCore", "DesignSystem"], externalDependencies: [], sourcePath: "Templates/Modules/Generic/GenericModule.swift"),
]

private let appSpecs: [AppSpec] = [
    .init(name: "ShopperApp", moduleDependencies: ["AppCore", "CatalogFeature", "CartFeature", "CheckoutFeature", "DesignSystem", "OrdersFeature", "PaymentsFeature", "ProfileFeature", "SearchFeature", "SupportFeature"]),
    .init(name: "CourierApp", moduleDependencies: ["AppCore", "CatalogFeature", "DesignSystem", "MapsFeature", "NotificationsFeature", "OrdersFeature", "ProfileFeature", "SupportFeature"]),
    .init(name: "BackofficeApp", moduleDependencies: ["AnalyticsKit", "AppCore", "CatalogFeature", "DesignSystem", "ExperimentationKit", "InventoryFeature", "OrdersFeature", "SearchFeature", "SupportFeature"]),
    .init(name: "OpsConsoleApp", moduleDependencies: ["AnalyticsKit", "AppCore", "DesignSystem", "ExperimentationKit", "InventoryFeature", "NotificationsFeature", "OrdersFeature", "SupportFeature"]),
    .init(name: "PreviewApp", moduleDependencies: ["AppCore", "CatalogFeature", "DesignSystem", "OrdersFeature", "SearchFeature", "SharedMocks", "SupportFeature"]),
]

private let buildConfigurations: [Configuration] = [
    .debug(name: "Debug"),
    .debug(name: "Staging"),
    .release(name: "Release"),
    .release(name: "Benchmark"),
]

let project = Project(
    name: "SidekickMegaWorkspace",
    settings: .settings(
        configurations: buildConfigurations,
        defaultSettings: .recommended
    ),
    targets: makeTargets()
)

private func makeTargets() -> [Target] {
    let moduleTargets = moduleSpecs.map(makeModuleTarget)
    let appTargets = appSpecs.flatMap(makeAppTargets)
    return moduleTargets + appTargets
}

private func makeModuleTarget(spec: ModuleSpec) -> Target {
    Target.target(
        name: spec.name,
        destinations: .iOS,
        product: .framework,
        bundleId: "dev.sidekick.fixture.\(spec.name)",
        infoPlist: .default,
        sources: .paths([Path(stringLiteral: spec.sourcePath)]),
        resources: [],
        dependencies: makeDependencies(
            modules: spec.moduleDependencies,
            externals: spec.externalDependencies
        )
    )
}

private func makeAppTargets(spec: AppSpec) -> [Target] {
    [
        .target(
            name: spec.name,
            destinations: .iOS,
            product: .app,
            bundleId: "dev.sidekick.fixture.\(spec.name)",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: .paths([Path("Templates/App/Sources/AppMain.swift")]),
            resources: [],
            dependencies: makeDependencies(
                modules: spec.moduleDependencies,
                externals: []
            )
        ),
        .target(
            name: "\(spec.name)Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.sidekick.fixture.\(spec.name)Tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: .paths([Path("Templates/Tests/FixtureTests.swift")]),
            resources: [],
            dependencies: [.target(name: spec.name)]
        ),
    ]
}

private func makeDependencies(
    modules: [String],
    externals: [String]
) -> [TargetDependency] {
    let targetDependencies = modules.map { TargetDependency.target(name: $0) }
    let externalDependencies = externals.map { TargetDependency.external(name: $0) }
    return targetDependencies + externalDependencies
}
