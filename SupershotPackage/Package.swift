// swift-tools-version: 6.2
import PackageDescription

/// Match the executable's existing language and isolation settings during extraction.
let appSwiftSettings: [SwiftSetting] = [
  .swiftLanguageMode(.v5),
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("DisableOutwardActorInference"),
  .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
  .enableUpcomingFeature("InferSendableFromCaptures"),
]

let package = Package(
  name: "SupershotPackage",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [
    .library(name: "FixtureTeamResolution", targets: ["FixtureTeamResolution"]),
    .library(name: "GameParser", targets: ["GameParser"]),
    .executable(name: "GameParserHarness", targets: ["GameParserHarness"]),
    .library(name: "TestSupport", targets: ["TestSupport"]),
    .library(name: "SharedModels", targets: ["SharedModels"]),
    .library(name: "WidgetSupport", targets: ["WidgetSupport"]),
    .library(name: "GameCore", targets: ["GameCore"]),
    .library(name: "UI", targets: ["UI"]),
    .library(name: "AppUI", targets: ["AppUI"]),
    .library(name: "Database", targets: ["Database"]),
    .library(name: "AppSettings", targets: ["AppSettings"]),
    .library(name: "PreviewSupport", targets: ["PreviewSupport"]),
    .library(name: "AlarmClient", targets: ["AlarmClient"]),
    .library(name: "SubscriptionClient", targets: ["SubscriptionClient"]),
    .library(name: "FeatureFlagsClient", targets: ["FeatureFlagsClient"]),
    .library(name: "LocationClient", targets: ["LocationClient"]),
    .library(name: "SoundEffectsClient", targets: ["SoundEffectsClient"]),
    .library(name: "GameServices", targets: ["GameServices"]),
    .library(name: "GameAnalysis", targets: ["GameAnalysis"]),
    .library(name: "TeamEditingFeature", targets: ["TeamEditingFeature"]),
    .library(name: "PermissionsFeature", targets: ["PermissionsFeature"]),
    .library(name: "PaywallFeature", targets: ["PaywallFeature"]),
    .library(name: "ScoringFeature", targets: ["ScoringFeature"]),
    .library(name: "NewGameFeature", targets: ["NewGameFeature"]),
    .library(name: "GameDetailFeature", targets: ["GameDetailFeature"]),
    .library(name: "GamesFeature", targets: ["GamesFeature"]),
    .library(name: "TeamsFeature", targets: ["TeamsFeature"]),
    .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    .library(name: "AppFeature", targets: ["AppFeature"]),
  ],
  dependencies: [
    .package(url: "https://github.com/ordo-one/FuzzyMatch.git", exact: "1.4.0"),
    .package(url: "https://github.com/apple/swift-collections", exact: "1.6.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", exact: "1.6.1"),
    .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    .package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", exact: "5.83.0"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", exact: "1.8.2"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.1"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.14.1"),
    .package(
      url: "https://github.com/tgrapperon/swift-dependencies-additions",
      revision: "0afff683710e63433847641562da5908fe01205f"
    ),
    .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.9.1"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", exact: "1.11.0"),
  ],
  targets: [
    .target(
      name: "FixtureTeamResolution",
      dependencies: ["GameParser", "GameCore", .product(name: "FuzzyMatch", package: "FuzzyMatch")],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "FixtureTeamResolutionTests",
      dependencies: ["FixtureTeamResolution", "GameParser", "GameCore"],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "GameParser",
      dependencies: [.product(name: "Dependencies", package: "swift-dependencies")],
      swiftSettings: appSwiftSettings
    ),
    .executableTarget(
      name: "GameParserHarness",
      dependencies: ["GameParser"],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "GameParserTests",
      dependencies: [
        "GameParser",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "SharedModels",
      dependencies: [],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "WidgetSupport",
      dependencies: [],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "GameCore",
      dependencies: ["SharedModels", .product(name: "SQLiteData", package: "sqlite-data")],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "UI",
      dependencies: ["SharedModels", "WidgetSupport"],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "AppUI",
      dependencies: [
        "UI", "SharedModels", "GameCore", "Database",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "Database",
      dependencies: [
        "SharedModels", "GameCore", "WidgetSupport",
        .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "AppSettings",
      dependencies: ["GameCore", .product(name: "Sharing", package: "swift-sharing")],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "PreviewSupport",
      dependencies: [
        "AppUI",
        "LocationClient", "SharedModels", "GameCore", "Database", "UI",
        .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "AlarmClient",
      dependencies: [
        "FeatureFlagsClient",
        "SharedModels", "GameCore", "Database", "SubscriptionClient",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "FeatureFlagsClient",
      dependencies: [
        "SubscriptionClient",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "FeatureFlagsClientTests",
      dependencies: [
        "FeatureFlagsClient",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "SubscriptionClient",
      dependencies: [
        .product(name: "RevenueCat", package: "purchases-ios-spm"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "LocationClient",
      dependencies: [
        "SharedModels", .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "SoundEffectsClient",
      dependencies: [.product(name: "Dependencies", package: "swift-dependencies")],
      resources: [.process("success.aif")],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "GameServices",
      dependencies: [
        "FeatureFlagsClient",
        "SharedModels", "GameCore", "Database", "AlarmClient", "SubscriptionClient",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "GameAnalysis",
      dependencies: [
        "AppUI",
        "LocationClient", "PaywallFeature", "SharedModels", "GameCore", "Database", "UI",
        "PreviewSupport",
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "TeamEditingFeature",
      dependencies: [
        "AppUI",
        "SharedModels", "GameCore", "Database", "UI", "PreviewSupport",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "PermissionsFeature",
      dependencies: [
        "FeatureFlagsClient",
        "SubscriptionClient", "AlarmClient", "UI",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "PaywallFeature",
      dependencies: [
        "SubscriptionClient", "UI",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "ScoringFeature",
      dependencies: [
        "AppUI",
        "SharedModels", "GameCore", "Database", "GameServices", "AlarmClient", "SubscriptionClient",
        "AppSettings", "SoundEffectsClient", "UI", "GameAnalysis",
        "PermissionsFeature", "PreviewSupport",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesAdditions", package: "swift-dependencies-additions"),
        .product(name: "Sharing", package: "swift-sharing"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "NewGameFeature",
      dependencies: [
        "AppUI",
        "GameAnalysis", "PermissionsFeature", "SubscriptionClient", "SharedModels", "GameCore",
        "Database", "GameServices", "AppSettings", "LocationClient", "UI",
        "TeamEditingFeature", "ScoringFeature", "PreviewSupport", "GameParser", "FixtureTeamResolution",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Sharing", package: "swift-sharing"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "GameDetailFeature",
      dependencies: [
        "AppUI",
        "SharedModels", "GameCore", "Database", "GameServices", "UI", "GameAnalysis",
        "PreviewSupport", .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "GamesFeature",
      dependencies: [
        "AppUI",
        "SharedModels", "GameCore", "Database", "GameServices", "SubscriptionClient", "UI",
        "NewGameFeature", "ScoringFeature", "GameDetailFeature", "GameAnalysis", "PaywallFeature",
        "PreviewSupport", .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "TeamsFeature",
      dependencies: [
        "AppUI",
        "SharedModels", "GameCore", "Database", "GameServices", "SubscriptionClient", "UI",
        "TeamEditingFeature", "NewGameFeature", "ScoringFeature",
        "GameDetailFeature", "GameAnalysis", "PaywallFeature", "PreviewSupport",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "SettingsFeature",
      dependencies: [
        "AppUI",
        "SharedModels", "GameCore", "Database", "AppSettings", "SubscriptionClient", "UI",
        "PaywallFeature", .product(name: "RevenueCat", package: "purchases-ios-spm"),
        .product(name: "RevenueCatUI", package: "purchases-ios-spm"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Sharing", package: "swift-sharing"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "AppFeature",
      dependencies: [
        "AppUI",
        "FeatureFlagsClient",
        "PreviewSupport",
        "SharedModels", "GameCore", "Database", "GameServices", "AlarmClient", "AppSettings",
        "SubscriptionClient", "UI", "GamesFeature", "TeamsFeature", "SettingsFeature",
        "PermissionsFeature", "PaywallFeature", "ScoringFeature",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "Sharing", package: "swift-sharing"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .target(
      name: "TestSupport",
      dependencies: [
        "SharedModels", "GameCore", .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "TeamEditingFeatureTests",
      dependencies: [
        "AppUI",
        "Database", "GameCore", "GameServices", "PreviewSupport", "SharedModels", "UI",
        "TeamEditingFeature", "TestSupport", "WidgetSupport",
        .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "DatabaseTests",
      dependencies: [
        "AppUI",
        "Database", "GameCore", "GameServices", "SharedModels", "UI", "TestSupport",
        "WidgetSupport", .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "SettingsFeatureTests",
      dependencies: [
        "AppUI",
        "NewGameFeature", "AppSettings", "Database", "GameCore", "GameServices", "PaywallFeature",
        "SettingsFeature", "SharedModels", "UI", "SubscriptionClient", "TestSupport",
        "WidgetSupport", .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "AppFeatureTests",
      dependencies: [
        "AppUI",
        "AlarmClient", "AppFeature", "AppSettings", "Database", "GameAnalysis", "GameCore",
        "GameDetailFeature", "GameServices", "GamesFeature", "LocationClient", "NewGameFeature",
        "PaywallFeature", "PermissionsFeature", "PreviewSupport", "ScoringFeature",
        "SettingsFeature", "SharedModels", "SoundEffectsClient", "UI", "SubscriptionClient",
        "TeamEditingFeature", "TeamsFeature", "TestSupport", "WidgetSupport",
        .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        .product(name: "Sharing", package: "swift-sharing"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "UITests",
      dependencies: [
        "AppUI",
        "NewGameFeature", "SettingsFeature", "Database", "GameCore", "GameServices", "SharedModels",
        "UI", "TestSupport", "WidgetSupport",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "GameServicesTests",
      dependencies: [
        "AppUI",
        "PermissionsFeature",
        "SoundEffectsClient",
        "GamesFeature", "ScoringFeature", "TeamsFeature", "AlarmClient", "Database", "GameCore",
        "GameServices", "SharedModels", "UI", "SubscriptionClient", "TestSupport",
        "WidgetSupport", .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "PaywallFeatureTests",
      dependencies: [
        "AppUI",
        "Database", "GameCore", "GameServices", "PaywallFeature", "SharedModels", "UI",
        "SubscriptionClient", "TestSupport", "WidgetSupport",
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "TeamsFeatureTests",
      dependencies: [
        "AppUI",
        "AlarmClient", "AppSettings", "Database", "GameAnalysis", "GameCore", "GameDetailFeature",
        "GameServices", "LocationClient", "NewGameFeature", "PaywallFeature", "PermissionsFeature",
        "PreviewSupport", "ScoringFeature", "SharedModels", "SoundEffectsClient", "UI",
        "SubscriptionClient", "TeamEditingFeature", "TeamsFeature", "TestSupport", "WidgetSupport",
        .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "GameCoreTests",
      dependencies: [
        "UI",
        "AlarmClient", "ScoringFeature", "WidgetSupport", "Database", "GameCore", "GameServices",
        "SharedModels", "TestSupport", .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "GamesFeatureTests",
      dependencies: [
        "AppUI",
        "AlarmClient", "AppSettings", "Database", "GameAnalysis", "GameCore", "GameDetailFeature",
        "GameServices", "GamesFeature", "LocationClient", "NewGameFeature", "PaywallFeature",
        "PermissionsFeature", "PreviewSupport", "ScoringFeature", "SharedModels",
        "SoundEffectsClient", "UI", "SubscriptionClient", "TeamEditingFeature",
        "TestSupport", "WidgetSupport", .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "NewGameFeatureTests",
      dependencies: [
        "AppUI",
        "AlarmClient", "AppSettings", "Database", "GameAnalysis", "GameCore", "GameServices",
        "LocationClient", "NewGameFeature", "PermissionsFeature", "PreviewSupport", "GameParser", "FixtureTeamResolution",
        "ScoringFeature", "SharedModels", "SoundEffectsClient", "UI", "SubscriptionClient",
        "TeamEditingFeature", "TestSupport", "WidgetSupport",
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "ScoringFeatureTests",
      dependencies: [
        "AppUI",
        "AlarmClient", "AppSettings", "Database", "GameAnalysis", "GameCore", "GameServices",
        "PermissionsFeature", "PreviewSupport", "ScoringFeature", "SharedModels",
        "SoundEffectsClient", "UI", "SubscriptionClient", "TestSupport", "WidgetSupport",
        .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        .product(name: "DependenciesAdditions", package: "swift-dependencies-additions"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "PreviewSupportTests",
      dependencies: [
        "AppUI",
        "Database", "GameCore", "GameServices", "PreviewSupport", "SharedModels", "UI",
        "TestSupport", "WidgetSupport", .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
    .testTarget(
      name: "GameDetailFeatureTests",
      dependencies: [
        "AppUI",
        "AlarmClient", "Database", "GameAnalysis", "GameCore", "GameDetailFeature", "GameServices",
        "PreviewSupport", "SharedModels", "UI", "SubscriptionClient", "TestSupport",
        "WidgetSupport", .product(name: "GRDB", package: "grdb.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: appSwiftSettings
    ),
  ]
)
