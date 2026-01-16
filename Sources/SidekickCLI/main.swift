import ArgumentParser

@main
struct Sidekick: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "sidekick",
    abstract: "A quirky CLI for building, running, and testing iOS/macOS apps",
    version: "0.1.0",
    subcommands: [Build.self, Archive.self, Config.self, Configure.self, Setup.self, Run.self, Sim.self, Devices.self]
  )
}
