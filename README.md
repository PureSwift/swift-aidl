# swift-aidl

A Swift package for parsing AIDL and generating Swift Binder bindings.

The package currently provides an initial lexer and parser alongside scaffolding:

- `AIDLCore`: the parser, type resolver, and initial integer expression evaluator.
- `aidl-swift`: a command-line frontend with `parse`, `check`, and `generate` commands.
- `AIDLPlugin`: a SwiftPM build tool plugin for generating bindings.

Run `aidl-swift check -I <include-directory> <source.aidl>` to parse a source
and its imports, resolve type references, and evaluate scalar `byte`, `int`,
and `long` constants and enum values. Evaluated values are available as
`AIDLSourceGraph.integerConstants` through `AIDLCore`.

For code generation preflight, pass `manualParcelables` to
`AIDLCompiler.analyze` as a set of fully qualified names. References to opaque
parcelables then require either a structured declaration in the include roots
or a registered manual implementation.

## Swift bindings

```sh
swift run aidl-swift generate -o IEcho.swift IEcho.aidl
```

The generator emits a Swift protocol, proxy, stub, and transaction codes for
each interface. It supports scalar input parameters and return values
(`byte`, `int`, `long`, `boolean`, `char`, `float`, and `double`), `void`
methods, and one-way calls. Interface methods also support `String` and
`@nullable String` inputs and results using Binder's UTF-16 string encoding.
`byte[]` and `@nullable byte[]` map to `[UInt8]` and `[UInt8]?`.
The generator emits `BinderParcelable` structs for
structured parcelables with scalar fields and implicit defaults. For a method
that takes or returns a parcelable, generate the interface and the parcelable
separately, passing the import root with `-I`. Use `@nullable` on a parcelable
input or result to generate an optional Swift value. Compile both outputs in a target
that depends on `Binder` 0.2.1.

AIDL enums generate `RawRepresentable` Swift structs with named static values.
Their `byte`, `int`, or `long` backing determines the wire encoding, and unknown
raw values can round-trip through generated methods. Generate imported enums
separately alongside their interfaces.

AIDL unions with scalar fields generate Swift enums with associated values.
The wire tag follows declaration order and only the active value is encoded.
Generate imported unions separately alongside their interfaces.

Generated proxies accept the `RemoteProxy` returned by Binder service lookup.
For example, if a service implements the generated `IEcho` interface:

```swift
import Binder

let connection = try BinderConnection(path: "/dev/binder")
if let service = try await connection.checkService(named: "echo") {
    let echo = IEchoProxy(remote: service)
    print(try await echo.echo(42))
}
```

### SwiftPM build tool plugin

Add the `AIDLPlugin` plugin and the `Binder` product to the target that uses
the generated bindings. Put `aidl-config.json` in that target's source directory.
For example:

```json
{
  "sources": ["AIDL/demo/IEcho.aidl", "AIDL/demo/Chunk.aidl"],
  "includePaths": ["AIDL"]
}
```

Paths are relative to the target's source directory. Use `preprocessedPaths`
for optional SDK declaration files. List each declaration you want emitted
under `sources` and use distinct filenames. Add `aidl-config.json` and `AIDL`
to the target's `exclude` list so SwiftPM leaves them to the plugin. The plugin
generates and compiles the Swift bindings during the build.

Callback generation remains pending.

## AOSP parser corpus

Run these commands from the repository root:

```sh
./Scripts/fetch-aosp-aidl.sh
swift test --filter parsesAOSPCorpus
swift test --filter resolvesAOSPInterfaces
```

The script refreshes sparse checkouts from AOSP `main` and prints each project's
commit. The corpus lives under the ignored `.build/aosp-aidl` directory. It
includes framework, Wi-Fi, and Bluetooth sources, exported Connectivity and
modules-utils dependencies, and the public SDK's preprocessed `framework.aidl`.

Both tests run with `swift test` whenever the corpus directory exists. The
parser test checks each file independently. The resolution test checks
`IWifiManager`, `IBluetoothManager`, and `IBluetooth` with their include roots
and SDK declarations. To pass preprocessed SDK declarations to the CLI, use
`aidl-swift check -p <framework.aidl> -I <include-directory> <source.aidl>`.
