# swift-aidl

A Swift package for parsing AIDL and generating Swift Binder bindings.

The package currently provides an initial lexer and parser alongside scaffolding:

- `AIDLCore`: the parser, type resolver, and initial integer expression evaluator.
- `aidl-swift`: a command-line frontend with `parse`, `check`, and `generate` commands.
- `AIDLPlugin`: the future SwiftPM build tool plugin.

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
methods, and one-way calls. It also emits `BinderParcelable` structs for
structured parcelables with scalar fields and implicit defaults. For a method
that takes or returns a parcelable, generate the interface and the parcelable
separately, passing the import root with `-I`. Compile both outputs in a target
that depends on `Binder` 0.2.1.

Callbacks and SwiftPM plugin integration are pending.

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
