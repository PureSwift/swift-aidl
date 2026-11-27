import Testing
import AIDLCore

@Test func compilerReportsUnimplemented() {
    #expect(throws: AIDLCoreError.self) {
        try AIDLCompiler().compile(sourcePath: "Example.aidl")
    }
}
