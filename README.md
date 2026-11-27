# swift-aidl

A Swift package for parsing AIDL and generating Swift Binder bindings.

The package currently provides an initial lexer and parser alongside scaffolding:

- `AIDLCore`: the parser, type resolver, and initial integer expression evaluator.
- `aidl-swift`: a command-line frontend with a `check` command.
- `AIDLPlugin`: the future SwiftPM build tool plugin.

Run `aidl-swift check -I <include-directory> <source.aidl>` to parse a source and its imports and resolve their type references. This check does not evaluate constants or verify wire compatibility. The integer expression evaluator is available separately through `AIDLCore`.

The parser covers core declarations, but complete AIDL syntax and semantic validation, code generation, Java parcelable extraction, and plugin integration are not implemented yet.
