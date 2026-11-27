import AIDLCore
import Binder
import Foundation
import Testing

@Test func roundTripsGeneratedAIDLMethodsThroughBinder() async throws {
    let source = """
        package demo;
        import demo.Chunk;
        import demo.Mode;
        interface IEcho {
            int echo(int value);
            oneway void notify(long value);
            double scale(float factor, double value);
            boolean matches(byte value, char marker);
            Chunk roundTrip(in Chunk sample);
            @nullable Chunk roundTripOptional(in @nullable Chunk sample);
            String echoText(String value);
            @nullable String echoOptionalText(in @nullable String value);
            byte[] echoBytes(in byte[] value);
            @nullable byte[] echoOptionalBytes(in @nullable byte[] value);
            Mode echoMode(Mode value);
        }
        """
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let package = directory.appendingPathComponent("demo")
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = package.appendingPathComponent("IEcho.aidl")
    try source.write(to: input, atomically: true, encoding: .utf8)
    let chunk = package.appendingPathComponent("Chunk.aidl")
    try """
        package demo;
        parcelable Chunk {
            int id;
            long count;
            boolean complete;
        }
        """.write(to: chunk, atomically: true, encoding: .utf8)
    let mode = package.appendingPathComponent("Mode.aidl")
    try """
        package demo;
        @Backing(type="int")
        enum Mode { IDLE, RUNNING = 4, STOPPING }
        """.write(to: mode, atomically: true, encoding: .utf8)

    // Compile a checked-in copy of the generated source as part of this test target.
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let compiler = AIDLCompiler()
    for (source, fixtureName) in [
        (input, "GeneratedEcho.swift"),
        (chunk, "GeneratedChunk.swift"),
        (mode, "GeneratedMode.swift"),
    ] {
        let emitted = try compiler.compile(sourcePath: source.path, includePaths: [directory.path])
        let fixture = fixtures.appendingPathComponent(fixtureName)
        #expect(emitted == (try String(contentsOf: fixture, encoding: .utf8)))
    }

    let stub = EchoService()
    let proxy = IEchoProxy(remote: stub.asBinder())
    #expect(IEchoTransactionCode.echo == 1)
    #expect(IEchoTransactionCode.notify == 2)
    #expect(IEchoTransactionCode.scale == 3)
    #expect(IEchoTransactionCode.matches == 4)
    #expect(IEchoTransactionCode.roundTrip == 5)

    #expect(try await proxy.echo(-42) == -42)
    try await proxy.notify(.min)
    #expect(await stub.events.lastValue == Int64.min)
    #expect(try await proxy.scale(2.5, 4.0) == 10.0)
    #expect(try await proxy.matches(-7, 0xD800))
    let result = try await proxy.roundTrip(Chunk(id: 1, count: .min, complete: true))
    #expect(result.id == 2)
    #expect(result.count == Int64.min)
    #expect(result.complete)
    #expect(try await proxy.roundTripOptional(nil) == nil)
    let optionalResult = try await proxy.roundTripOptional(Chunk(id: 10, count: 20, complete: true))
    #expect(optionalResult?.id == 10)
    #expect(optionalResult?.count == 20)
    #expect(optionalResult?.complete == true)

    #expect(try await proxy.echoText("A😀") == "A😀")
    #expect(try await proxy.echoOptionalText("") == "")
    #expect(try await proxy.echoOptionalText(nil) == nil)
    #expect(try await proxy.echoBytes([0, 128, 255]) == [0, 128, 255])
    #expect(try await proxy.echoOptionalBytes([]) == [])
    #expect(try await proxy.echoOptionalBytes(nil) == nil)
    #expect(Mode.IDLE.rawValue == 0)
    #expect(Mode.RUNNING.rawValue == 4)
    #expect(Mode.STOPPING.rawValue == 5)
    #expect(try await proxy.echoMode(.RUNNING) == .RUNNING)
    #expect(try await proxy.echoMode(Mode(rawValue: .min)).rawValue == Int32.min)

    var invalidRequest = Parcel()
    invalidRequest.appendInterfaceToken(IEchoProxy.descriptor)
    invalidRequest.appendNullString()
    await #expect(throws: ParcelError.invalidLength(-1)) {
        try await stub.transact(code: IEchoTransactionCode.echoText, data: invalidRequest, flags: [])
    }

    let invalidReplyProxy = IEchoProxy(remote: NullStringEndpoint())
    await #expect(throws: ParcelError.invalidLength(-1)) {
        try await invalidReplyProxy.echoText("value")
    }
    await #expect(throws: ParcelError.invalidLength(-1)) {
        try await invalidReplyProxy.echoBytes([255])
    }

    var byteRequest = Parcel()
    byteRequest.appendInterfaceToken(IEchoProxy.descriptor)
    byteRequest.appendNullBytes()
    await #expect(throws: ParcelError.invalidLength(-1)) {
        try await stub.transact(code: IEchoTransactionCode.echoBytes, data: byteRequest, flags: [])
    }
}

private final class NullStringEndpoint: IBinder {
    func transact(code: UInt32, data: Parcel, flags: TransactionFlags) async throws -> Parcel {
        var reply = Parcel()
        reply.writeNoException()
        reply.appendNullString()
        return reply
    }
}

@Test func generatedParcelableRespectsFrameBounds() throws {
    var null = Parcel()
    null.append(Int32(0))
    null.append(Int32(42))
    var nullReader = null.reader()
    #expect(try Chunk.readNullableTypedObject(from: &nullReader) == nil)
    #expect(try nullReader.readInt32() == 42)
    var requiredReader = null.reader()
    #expect(throws: BinderError.failedTransaction) {
        try Chunk.readTypedObject(from: &requiredReader)
    }

    var parcel = Parcel()
    try Chunk(id: 7, count: 10, complete: true).writeTypedObject(to: &parcel)
    #expect(parcel.bytes == [
        1, 0, 0, 0,
        20, 0, 0, 0,
        7, 0, 0, 0,
        10, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0,
    ])

    var older = Parcel()
    older.append(Int32(8))
    older.append(Int32(7))
    older.append(Int32(42))
    var oldReader = older.reader()
    let old = try Chunk(from: &oldReader)
    #expect(old.id == 7 && old.count == 0 && !old.complete)
    #expect(try oldReader.readInt32() == 42)

    var newer = Parcel()
    newer.append(Int32(24))
    newer.append(Int32(7))
    newer.append(Int64(10))
    newer.append(true)
    newer.append(Int32(99))
    newer.append(Int32(42))
    var newReader = newer.reader()
    let new = try Chunk(from: &newReader)
    #expect(new.id == 7 && new.count == 10 && new.complete)
    #expect(try newReader.readInt32() == 42)

    var malformed = Parcel()
    malformed.append(Int32(12))
    malformed.append(Int32(7))
    malformed.append(Int32(0)) // Only half of the long fits in the frame.
    malformed.append(Int32(42))
    var malformedReader = malformed.reader()
    #expect(throws: ParcelError.endOfParcel) { try Chunk(from: &malformedReader) }
    #expect(try malformedReader.readInt32() == 42)
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

    override func roundTrip(_ sample: Chunk) async throws -> Chunk {
        Chunk(id: sample.id + 1, count: sample.count, complete: sample.complete)
    }

    override func roundTripOptional(_ sample: Chunk?) async throws -> Chunk? { sample }

    override func echoText(_ value: String) async throws -> String { value }

    override func echoOptionalText(_ value: String?) async throws -> String? { value }

    override func echoBytes(_ value: [UInt8]) async throws -> [UInt8] { value }

    override func echoOptionalBytes(_ value: [UInt8]?) async throws -> [UInt8]? { value }

    override func echoMode(_ value: Mode) async throws -> Mode { value }
}
