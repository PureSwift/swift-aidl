import Testing
import AIDLCore

@Test func parsesInterfaceAndPreservesTransactionOrder() throws {
    var parser = try AIDLParser(source: """
        package android.example;
        import android.os.SomeType;
        oneway interface IExample {
            const int MASK = 1 << 2;
            @UnsupportedAppUsage void hidden();
            @nullable String get(in @nullable List<String> names);
            void assigned(out int[] result) = 0x2a;
        }
        """, sourcePath: "IExample.aidl")
    let file = try parser.parse()
    #expect(file.packageName == ["android", "example"])
    #expect(file.imports == [["android", "os", "SomeType"]])
    guard case let .interface(interface) = try #require(file.declarations.first) else {
        Issue.record("Expected interface")
        return
    }
    #expect(interface.descriptor == "android.example.IExample")
    #expect(interface.isOneway)
    #expect(interface.methods.map(\.computedTransactionCode) == [1, 2, 43])
    #expect(interface.methods[0].annotations.first?.name == "UnsupportedAppUsage")
    #expect(interface.methods[1].parameters[0].type.annotations.first?.name == "nullable")
    #expect(interface.methods[2].parameters[0].direction == .out)
    #expect(interface.constants[0].value.map(\.text) == ["1", "<<", "2"])
}

@Test func parsesParcelableUnionEnumAndNestedGenerics() throws {
    var parser = try AIDLParser(source: """
        @JavaOnlyStableParcelable parcelable Opaque;
        parcelable Empty {}
        parcelable Record {
            @nullable Map<String, List<int>> values;
            int count = (1 + 2);
            enum Mode { FIRST = 1, SECOND, }
        }
        union Choice { int number; String text; }
        """)
    let file = try parser.parse()
    guard case let .parcelable(opaque) = file.declarations[0],
          case let .parcelable(empty) = file.declarations[1],
          case let .parcelable(record) = file.declarations[2],
          case let .union(choice) = file.declarations[3] else {
        Issue.record("Expected declarations")
        return
    }
    #expect(opaque.isOpaqueForwardDecl)
    #expect(!empty.isOpaqueForwardDecl)
    #expect(record.fields[0].type.typeArguments[1].typeArguments[0].name == "int")
    #expect(record.nestedDeclarations.count == 1)
    #expect(choice.fields.count == 2)
}

@Test func parserReportsIncompleteDeclaration() throws {
    var parser = try AIDLParser(source: "interface Broken { void call(")
    #expect(throws: AIDLParserError.self) { try parser.parse() }
}

@Test func parsesQualifiedImportsAndOpaqueParcelableMetadata() throws {
    var parser = try AIDLParser(source: """
        package example;
        import android.os.ParcelFileDescriptor;
        parcelable Container.Entry<T, U> cpp_header "entry.h" ndk_header "ndk/entry.h" rust_type "example::Entry";
        """)
    let file = try parser.parse()
    #expect(file.imports == [["android", "os", "ParcelFileDescriptor"]])
    guard case let .parcelable(parcelable) = try #require(file.declarations.first) else {
        Issue.record("Expected parcelable")
        return
    }
    #expect(parcelable.name == "Container.Entry")
    #expect(parcelable.isOpaqueForwardDecl)
    #expect(parcelable.typeParameters == ["T", "U"])
    #expect(parcelable.backendNames.mapValues(\.text) == [
        "cpp_header": #""entry.h""#,
        "ndk_header": #""ndk/entry.h""#,
        "rust_type": #""example::Entry""#,
    ])
}
