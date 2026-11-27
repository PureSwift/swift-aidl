import PackagePlugin

@main
struct AIDLPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        Diagnostics.warning("AIDLPlugin is a stub; AIDL source generation is not implemented yet.")
        return []
    }
}
