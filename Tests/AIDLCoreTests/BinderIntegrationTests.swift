import AIDLCore
import Binder
import Foundation
import Testing

@Test func roundTripsGeneratedAIDLMethodsThroughBinder() async throws {
    let source = """
        package demo;
        import demo.Chunk;
        import demo.Choice;
        import demo.Mode;
        interface IEcho {
            const String LABEL = "swift " + (WORD + "!");
            const String WORD = "binder";
            const byte LOW = -7;
            const int MASK = (1 << 31) | 5;
            const long WIDE = (1L << 40) | LOW & 0xff;
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
            Choice echoChoice(in Choice value);
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
    let choice = package.appendingPathComponent("Choice.aidl")
    try """
        package demo;
        union Choice {
            int number;
            long big;
        }
        """.write(to: choice, atomically: true, encoding: .utf8)

    // Compile a checked-in copy of the generated source as part of this test target.
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let compiler = AIDLCompiler()
    for (source, fixtureName) in [
        (input, "GeneratedEcho.swift"),
        (chunk, "GeneratedChunk.swift"),
        (mode, "GeneratedMode.swift"),
        (choice, "GeneratedChoice.swift"),
    ] {
        let emitted = try compiler.compile(
            sourcePath: source.path, includePaths: [directory.path],
            interfaceVersion: source == input ? 3 : nil,
            interfaceHash: source == input ? "notfrozen" : nil
        )
        let fixture = fixtures.appendingPathComponent(fixtureName)
        #expect(emitted == (try String(contentsOf: fixture, encoding: .utf8)))
    }

    let stub = EchoService()
    let _: (RemoteProxy) -> IEchoProxy = IEchoProxy.init(remote:)
    let proxy = IEchoProxy(remote: stub.asBinder())
    #expect(IEchoProxy.LOW == -7)
    #expect(IEchoProxy.MASK == -2_147_483_643)
    #expect(IEchoProxy.WIDE == 1_099_511_628_025)
    #expect(IEchoProxy.LABEL == "swift binder!")
    #expect(IEchoProxy.WORD == "binder")
    #expect(IEchoTransactionCode.echo == 1)
    #expect(IEchoTransactionCode.notify == 2)
    #expect(IEchoTransactionCode.scale == 3)
    #expect(IEchoTransactionCode.matches == 4)
    #expect(IEchoTransactionCode.roundTrip == 5)
    #expect(IEchoTransactionCode.getInterfaceVersion == 0x00ff_ffff)
    #expect(IEchoTransactionCode.getInterfaceHash == 0x00ff_fffe)
    #expect(try await proxy.getInterfaceVersion() == 3)
    #expect(try await proxy.getInterfaceHash() == "notfrozen")

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
    guard case let .big(big) = try await proxy.echoChoice(.big(.min)),
          case let .number(number) = try await proxy.echoChoice(.number(-7)) else {
        Issue.record("Expected the original union variants")
        return
    }
    #expect(big == Int64.min)
    #expect(number == -7)

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

@Test func generatedUnionUsesDeclaredTagAndActivePayload() throws {
    var parcel = Parcel()
    try Choice.big(42).writeTypedObject(to: &parcel)
    #expect(parcel.bytes == [1, 0, 0, 0, 1, 0, 0, 0, 42, 0, 0, 0, 0, 0, 0, 0])

    var invalid = Parcel()
    invalid.append(Int32(2))
    var reader = invalid.reader()
    #expect(throws: BinderError.failedTransaction) {
        try Choice(from: &reader)
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

@Test func generatedParcelableSizesVariableLengthFields() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aidl")
    try """
        package demo;
        parcelable Payload {
            int id;
            String name;
            @nullable byte[] data;
            @nullable String note;
            byte[] trailer;
        }
        """.write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("GeneratedPayload.swift")
    #expect(try AIDLCompiler().compile(sourcePath: path.path) == String(contentsOf: fixture, encoding: .utf8))

    var parcel = Parcel()
    try Payload(id: 7, name: "A😀", data: [128, 255, 7]).write(to: &parcel)
    #expect(parcel.bytes.count == 36)
    var sizeReader = parcel.reader()
    #expect(try sizeReader.readInt32() == 36)
    parcel.append(Int32(42))
    var reader = parcel.reader()
    let value = try Payload(from: &reader)
    #expect(value.id == 7 && value.name == "A😀")
    #expect(value.data == [128, 255, 7])
    #expect(value.note == nil && value.trailer.isEmpty)
    #expect(try reader.readInt32() == 42)

    var optional = Parcel()
    try Payload(name: "", note: "x", trailer: [1]).write(to: &optional)
    var optionalReader = optional.reader()
    let other = try Payload(from: &optionalReader)
    #expect(other.data == nil && other.note == "x" && other.trailer == [1])
    #expect(optionalReader.isAtEnd)

    var older = Parcel()
    older.append(Int32(8))
    older.append(Int32(7))
    var oldReader = older.reader()
    let old = try Payload(from: &oldReader)
    #expect(old.name.isEmpty && old.data == nil && old.note == nil && old.trailer.isEmpty)

    var malformed = Parcel()
    malformed.append(Int32(12))
    malformed.append(Int32(7))
    malformed.appendNullString()
    var malformedReader = malformed.reader()
    #expect(throws: ParcelError.invalidLength(-1)) { try Payload(from: &malformedReader) }
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

    override func echoChoice(_ value: Choice) async throws -> Choice { value }
}
