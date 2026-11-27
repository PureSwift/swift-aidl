# swift-aidl

A Swift package for parsing AIDL and generating Swift Binder bindings.

The package currently provides an initial lexer and parser alongside scaffolding:

- `AIDLCore`: the parser, type resolver, and initial integer expression evaluator.
- `aidl-swift`: a command-line frontend with `parse` and `check` commands.
- `AIDLPlugin`: the future SwiftPM build tool plugin.

Run `aidl-swift check -I <include-directory> <source.aidl>` to parse a source and its imports and resolve their type references. This check does not evaluate constants or verify wire compatibility. The integer expression evaluator is available separately through `AIDLCore`.

The parser covers core declarations, but complete AIDL syntax and semantic validation, code generation, Java parcelable extraction, and plugin integration are not implemented yet.

## AOSP parser corpus

Run these commands from the repository root:

```sh
./Scripts/fetch-aosp-aidl.sh
swift test --filter parsesAOSPCorpus
```

The script refreshes sparse checkouts from AOSP `main` and prints each project's
commit. The corpus lives under the ignored `.build/aosp-aidl` directory and
covers the framework's `core/java`, Wi-Fi's `framework/java` and `aidl`, and
Bluetooth's app, exported framework, and service AIDL roots.

The corpus test also runs with `swift test` whenever the corpus directory
exists. A fresh checkout without a corpus skips this test. Each source file is
parsed independently, and failures include the source path and parser diagnostic.
Use `aidl-swift check` for import and type resolution.
