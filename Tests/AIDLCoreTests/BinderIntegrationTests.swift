import AIDLCore
import Binder
import Foundation
import Testing

@Test func roundTripsGeneratedAIDLMethodsThroughBinder() async throws {
    let source = """
        package demo;
        interface IEcho {
            int echo(int value);
            oneway void notify(long value);
            double scale(float factor, double value);
            boolean matches(byte value, char marker);
        }
        """
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("IEcho.aidl")
    try source.write(to: input, atomically: true, encoding: .utf8)

    // Compile a checked-in copy of the generated source as part of this test target.
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("GeneratedEcho.swift")
    let emitted = try AIDLCompiler().compile(sourcePath: input.path)
    #expect(emitted == (try String(contentsOf: fixture, encoding: .utf8)))

    let stub = EchoService()
    let proxy = IEchoProxy(remote: stub.asBinder())
    #expect(IEchoTransactionCode.echo == 1)
    #expect(IEchoTransactionCode.notify == 2)
    #expect(IEchoTransactionCode.scale == 3)
    #expect(IEchoTransactionCode.matches == 4)

    #expect(try await proxy.echo(-42) == -42)
    try await proxy.notify(.min)
    #expect(await stub.events.lastValue == Int64.min)
    #expect(try await proxy.scale(2.5, 4.0) == 10.0)
    #expect(try await proxy.matches(-7, 0xD800))
}

private actor EchoEvents {
    private(set) var lastValue: Int64?

    func record(_ value: Int64) {
        lastValue = value
    }
}

private final class EchoService: IEchoStub, @unchecked Sendable {
    let events = EchoEvents()

    override func echo(_ value: Int32) async throws -> Int32 { value }

    override func notify(_ value: Int64) async throws {
        await events.record(value)
    }

    override func scale(_ factor: Float, _ value: Double) async throws -> Double {
        Double(factor) * value
    }

    override func matches(_ value: Int8, _ marker: UInt16) async throws -> Bool {
        value == -7 && marker == 0xD800
    }
}
