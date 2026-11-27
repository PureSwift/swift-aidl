import AIDLCore
import Binder
import Foundation
import Testing

@Test func roundTripsGeneratedAIDLMethodsThroughBinder() async throws {
    let source = """
        package demo;
        import demo.Chunk;
        import demo.ManualStamp;
        import demo.EnumFields;
        import demo.Nested;
        import demo.Choice;
        import demo.Mode;
        import demo.ByteMode;
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
            int[] echoInts(in int[] value);
            @nullable long[] echoLongs(in @nullable long[] value);
            boolean[] echoBools(in boolean[] value);
            char[] echoChars(in char[] value);
            float[] echoFloats(in float[] value);
            @nullable double[] echoDoubles(in @nullable double[] value);
            String[] echoTexts(in String[] value);
            @nullable List<String> echoOptionalTexts(in @nullable List<String> value);
            Chunk[] echoChunks(in Chunk[] value);
            @nullable List<Chunk> echoOptionalChunks(in @nullable List<Chunk> value);
            @nullable Mode[] echoModes(in @nullable Mode[] value);
            ByteMode[] echoByteModes(in ByteMode[] value);
            EnumFields echoEnumFields(in EnumFields value);
            Nested echoNested(in Nested value);
            ManualStamp echoStamp(in ManualStamp value);
            @nullable ManualStamp echoOptionalStamp(in @nullable ManualStamp value);
            ManualStamp[] echoStamps(in ManualStamp[] value);
            @nullable List<ManualStamp> echoOptionalStamps(in @nullable List<ManualStamp> value);
        }
        """
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let package = directory.appendingPathComponent("demo")
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = package.appendingPathComponent("IEcho.aidl")
    try source.write(to: input, atomically: true, encoding: .utf8)
    let manual = package.appendingPathComponent("ManualStamp.aidl")
    try "package demo; parcelable ManualStamp;".write(to: manual, atomically: true, encoding: .utf8)
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
        import demo.Mode;
        union Choice {
            int number;
            long big;
            String text;
            @nullable byte[] data;
            Mode mode;
            @nullable boolean[] flags;
            @nullable List<String> labels;
        }
        """.write(to: choice, atomically: true, encoding: .utf8)
    let containerChoice = package.appendingPathComponent("ContainerChoice.aidl")
    try """
        package demo;
        import demo.Chunk;
        import demo.Choice;
        union ContainerChoice {
            int number;
            @nullable Chunk chunk;
            Choice choice;
        }
        """.write(to: containerChoice, atomically: true, encoding: .utf8)
    let unionEnvelope = package.appendingPathComponent("UnionEnvelope.aidl")
    try """
        package demo;
        import demo.ContainerChoice;
        parcelable UnionEnvelope {
            ContainerChoice choice;
            @nullable ContainerChoice optionalChoice;
        }
        """.write(to: unionEnvelope, atomically: true, encoding: .utf8)
    let byteMode = package.appendingPathComponent("ByteMode.aidl")
    try """
        package demo;
        enum ByteMode { NONE, HIGH = -7 }
        """.write(to: byteMode, atomically: true, encoding: .utf8)
    let collectionFields = package.appendingPathComponent("CollectionFields.aidl")
    try """
        package demo;
        import demo.Chunk;
        import demo.ByteMode;
        parcelable CollectionFields {
            List<String> labels;
            @nullable List<Chunk> chunks;
            ByteMode[] modes;
        }
        """.write(to: collectionFields, atomically: true, encoding: .utf8)
    let enumFields = package.appendingPathComponent("EnumFields.aidl")
    try """
        package demo;
        import demo.Mode;
        import demo.ByteMode;
        parcelable EnumFields {
            Mode mode = Mode.RUNNING;
            ByteMode byteMode = ByteMode.HIGH;
            ByteMode implicitMode;
        }
        """.write(to: enumFields, atomically: true, encoding: .utf8)
    let payload = package.appendingPathComponent("Payload.aidl")
    try payloadAIDL.write(to: payload, atomically: true, encoding: .utf8)
    let nested = package.appendingPathComponent("Nested.aidl")
    try """
        package demo;
        import demo.Payload;
        import demo.Chunk;
        parcelable Nested {
            @nullable Payload payload;
            Chunk child;
            int tail;
        }
        """.write(to: nested, atomically: true, encoding: .utf8)

    // Compile a checked-in copy of the generated source as part of this test target.
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let compiler = AIDLCompiler()
    for (source, fixtureName) in [
        (input, "GeneratedEcho.swift"),
        (chunk, "GeneratedChunk.swift"),
        (mode, "GeneratedMode.swift"),
        (choice, "GeneratedChoice.swift"),
        (containerChoice, "GeneratedContainerChoice.swift"),
        (unionEnvelope, "GeneratedUnionEnvelope.swift"),
        (byteMode, "GeneratedByteMode.swift"),
        (collectionFields, "GeneratedCollectionFields.swift"),
        (enumFields, "GeneratedEnumFields.swift"),
        (nested, "GeneratedNested.swift"),
    ] {
        let emitted = try compiler.compile(
            sourcePath: source.path, includePaths: [directory.path],
            interfaceVersion: source == input ? 3 : nil,
            interfaceHash: source == input ? "notfrozen" : nil,
            manualParcelables: ["demo.ManualStamp"]
        )
        let fixture = fixtures.appendingPathComponent(fixtureName)
        #expect(emitted == (try String(contentsOf: fixture, encoding: .utf8)))
    }
    #expect(throws: AIDLSwiftGenerationError.self) {
        try compiler.compile(sourcePath: input.path, includePaths: [directory.path])
    }
    try FileManager.default.removeItem(at: manual)
    let framework = directory.appendingPathComponent("framework.aidl")
    try "parcelable demo.ManualStamp;".write(to: framework, atomically: true, encoding: .utf8)
    let withPreprocessed = try compiler.compile(
        sourcePath: input.path, includePaths: [directory.path], preprocessedPaths: [framework.path],
        interfaceVersion: 3, interfaceHash: "notfrozen", manualParcelables: ["demo.ManualStamp"]
    )
    #expect(withPreprocessed == (try String(contentsOf: fixtures.appendingPathComponent("GeneratedEcho.swift"), encoding: .utf8)))

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
    guard case let .text(text) = try await proxy.echoChoice(.text("A😀")),
          case let .data(bytes) = try await proxy.echoChoice(.data([128, 255])),
          case let .data(absent) = try await proxy.echoChoice(.data(nil)) else {
        Issue.record("Expected the original reference union variants")
        return
    }
    #expect(text == "A😀")
    #expect(bytes == [128, 255])
    #expect(absent == nil)
    guard case let .labels(labels) = try await proxy.echoChoice(.labels(["A😀", nil, ""])) else {
        Issue.record("Expected the list union variant")
        return
    }
    #expect(labels == ["A😀", nil, ""])
    #expect(try await proxy.echoInts([Int32.min, 0, Int32.max]) == [Int32.min, 0, Int32.max])
    #expect(try await proxy.echoInts([]).isEmpty)
    #expect(try await proxy.echoLongs([.min, .max]) == [Int64.min, Int64.max])
    #expect(try await proxy.echoLongs(nil) == nil)
    #expect(try await proxy.echoBools([false, true, false]) == [false, true, false])
    #expect(try await proxy.echoChars([0, 0xD800, 0xFFFF]) == [0, 0xD800, 0xFFFF])
    let floats: [Float] = [-0.0, Float(bitPattern: 0x7FC0_1234), .infinity]
    #expect(try await proxy.echoFloats(floats).map(\.bitPattern) == floats.map(\.bitPattern))
    let doubles: [Double] = [-0.0, Double(bitPattern: 0x7FF8_0000_0000_1234), -.infinity]
    #expect(try await proxy.echoDoubles(doubles)?.map(\.bitPattern) == doubles.map(\.bitPattern))
    #expect(try await proxy.echoDoubles(nil) == nil)
    #expect(try await proxy.echoTexts(["", "A😀", "binder"]) == ["", "A😀", "binder"])
    #expect(try await proxy.echoTexts([]).isEmpty)
    #expect(try await proxy.echoOptionalTexts(["A😀", nil, ""]) == ["A😀", nil, ""])
    #expect(try await proxy.echoOptionalTexts([]) == [])
    #expect(try await proxy.echoOptionalTexts(nil) == nil)
    let chunks = try await proxy.echoChunks([Chunk(id: 1, count: .min), Chunk(id: 2, count: .max)])
    #expect(chunks.map(\.id) == [1, 2])
    #expect(chunks.map(\.count) == [Int64.min, Int64.max])
    #expect(try await proxy.echoChunks([]).isEmpty)
    let optionalChunks = try #require(await proxy.echoOptionalChunks([nil, Chunk(id: 3), nil]))
    #expect(optionalChunks.map { $0?.id } == [nil, 3, nil])
    #expect(try await proxy.echoOptionalChunks(nil) == nil)
    let unknownMode = Mode(rawValue: .max)
    #expect(try await proxy.echoModes([.IDLE, unknownMode]) == [.IDLE, unknownMode])
    #expect(try await proxy.echoModes(nil) == nil)
    #expect(try await proxy.echoByteModes([.HIGH, ByteMode(rawValue: .min)]) == [.HIGH, ByteMode(rawValue: .min)])
    let fields = try await proxy.echoEnumFields(EnumFields(mode: unknownMode, byteMode: .HIGH))
    #expect(fields.mode == unknownMode && fields.byteMode == .HIGH && fields.implicitMode.rawValue == 0)
    guard case let .mode(unionMode) = try await proxy.echoChoice(.mode(unknownMode)) else {
        Issue.record("Expected the enum union variant")
        return
    }
    #expect(unionMode == unknownMode)
    let nestedResult = try await proxy.echoNested(Nested(
        payload: Payload(id: 7, name: "A😀", data: [255]),
        child: Chunk(id: 42, count: .min), tail: 17
    ))
    #expect(nestedResult.payload?.name == "A😀")
    #expect(nestedResult.payload?.data == [255])
    #expect(nestedResult.child.id == 42 && nestedResult.child.count == .min && nestedResult.tail == 17)
    #expect(try await proxy.echoNested(Nested()).payload == nil)
    let stamp = ManualStamp(serial: .min, enabled: true)
    #expect(try await proxy.echoStamp(stamp) == stamp)
    #expect(try await proxy.echoOptionalStamp(stamp) == stamp)
    #expect(try await proxy.echoOptionalStamp(nil) == nil)
    let anotherStamp = ManualStamp(serial: 7, enabled: false)
    #expect(try await proxy.echoStamps([stamp, anotherStamp]) == [stamp, anotherStamp])
    #expect(try await proxy.echoStamps([]).isEmpty)
    #expect(try await proxy.echoOptionalStamps([nil, anotherStamp, nil]) == [nil, anotherStamp, nil])
    #expect(try await proxy.echoOptionalStamps(nil) == nil)

    var invalidStamps = Parcel()
    invalidStamps.appendInterfaceToken(IEchoProxy.descriptor)
    invalidStamps.append(Int32(1))
    invalidStamps.append(Int32(0))
    await #expect(throws: BinderError.failedTransaction) {
        try await stub.transact(code: IEchoTransactionCode.echoStamps, data: invalidStamps, flags: [])
    }

    var byteModes = Parcel()
    byteModes.appendInterfaceToken(IEchoProxy.descriptor)
    byteModes.append(bytes: [0xF9, 0x80, 0])
    let byteReply = try await stub.transact(code: IEchoTransactionCode.echoByteModes, data: byteModes, flags: [])
    #expect(byteReply.bytes == [0, 0, 0, 0, 3, 0, 0, 0, 0xF9, 0x80, 0, 0])

    var truncated = Parcel()
    truncated.appendInterfaceToken(IEchoProxy.descriptor)
    truncated.append(Int32.max)
    truncated.append(Int32(42))
    await #expect(throws: ParcelError.endOfParcel) {
        try await stub.transact(code: IEchoTransactionCode.echoInts, data: truncated, flags: [])
    }

    var invalidStringArray = Parcel()
    invalidStringArray.appendInterfaceToken(IEchoProxy.descriptor)
    invalidStringArray.append(Int32(1))
    invalidStringArray.appendNullString()
    await #expect(throws: ParcelError.invalidLength(-1)) {
        try await stub.transact(code: IEchoTransactionCode.echoTexts, data: invalidStringArray, flags: [])
    }

    var invalidChunkArray = Parcel()
    invalidChunkArray.appendInterfaceToken(IEchoProxy.descriptor)
    invalidChunkArray.append(Int32(1))
    invalidChunkArray.append(Int32(0))
    await #expect(throws: BinderError.failedTransaction) {
        try await stub.transact(code: IEchoTransactionCode.echoChunks, data: invalidChunkArray, flags: [])
    }

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
    await #expect(throws: ParcelError.invalidLength(-1)) {
        try await invalidReplyProxy.echoInts([42])
    }

    var byteRequest = Parcel()
    byteRequest.appendInterfaceToken(IEchoProxy.descriptor)
    byteRequest.appendNullBytes()
    await #expect(throws: ParcelError.invalidLength(-1)) {
        try await stub.transact(code: IEchoTransactionCode.echoBytes, data: byteRequest, flags: [])
    }
}

public struct ManualStamp: BinderParcelable, Equatable {
    let serial: Int64
    let enabled: Bool

    init(serial: Int64, enabled: Bool) {
        self.serial = serial
        self.enabled = enabled
    }

    public init(from reader: inout Parcel.Reader) throws {
        serial = try reader.readInt64()
        enabled = try reader.readBool()
    }

    public func write(to parcel: inout Parcel) throws {
        parcel.append(serial)
        parcel.append(enabled)
    }
}
@Test func generatedUnionUsesDeclaredTagAndActivePayload() throws {
    var parcel = Parcel()
    try Choice.big(42).writeTypedObject(to: &parcel)
    #expect(parcel.bytes == [1, 0, 0, 0, 1, 0, 0, 0, 42, 0, 0, 0, 0, 0, 0, 0])

    var invalid = Parcel()
    invalid.append(Int32(7))
    var reader = invalid.reader()
    #expect(throws: BinderError.failedTransaction) {
        try Choice(from: &reader)
    }

    var absent = Parcel()
    try Choice.data(nil).writeTypedObject(to: &absent)
    #expect(absent.bytes == [1, 0, 0, 0, 3, 0, 0, 0, 255, 255, 255, 255])

    var invalidText = Parcel()
    invalidText.append(Int32(2))
    invalidText.appendNullString()
    var invalidTextReader = invalidText.reader()
    #expect(throws: ParcelError.invalidLength(-1)) {
        try Choice(from: &invalidTextReader)
    }

    var flags = Parcel()
    try Choice.flags([true, false]).write(to: &flags)
    #expect(flags.bytes == [5, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0])
}

@Test func generatedParcelableArrayFieldsRespectFrameBounds() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aidl")
    try """
        package demo;
        parcelable ArrayFields {
            int[] values;
            @nullable long[] optionalValues;
            int tail;
        }
        """.write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("GeneratedArrayFields.swift")
    #expect(try AIDLCompiler().compile(sourcePath: path.path) == String(contentsOf: fixture, encoding: .utf8))

    var parcel = Parcel()
    try ArrayFields(values: [.min, .max], optionalValues: [.min], tail: 42).write(to: &parcel)
    #expect(parcel.bytes.count == 32)
    parcel.append(Int32(99))
    var reader = parcel.reader()
    let fields = try ArrayFields(from: &reader)
    #expect(fields.values == [Int32.min, Int32.max])
    #expect(fields.optionalValues == [Int64.min] && fields.tail == 42)
    #expect(try reader.readInt32() == 99)

    var older = Parcel()
    older.append(Int32(4))
    var oldReader = older.reader()
    let defaults = try ArrayFields(from: &oldReader)
    #expect(defaults.values.isEmpty && defaults.optionalValues == nil)

    var malformed = Parcel()
    malformed.append(Int32(8))
    malformed.append(Int32(1))
    malformed.append(Int32(99))
    var malformedReader = malformed.reader()
    #expect(throws: ParcelError.endOfParcel) { try ArrayFields(from: &malformedReader) }
    #expect(try malformedReader.readInt32() == 99)
}

@Test func generatedCollectionFieldsPreserveElementFraming() throws {
    let unknownMode = ByteMode(rawValue: .min)
    var parcel = Parcel()
    try CollectionFields(
        labels: ["", "A😀"], chunks: [nil, Chunk(id: 7)], modes: [.HIGH, unknownMode]
    ).write(to: &parcel)
    #expect(parcel.count == 68)
    var header = parcel.reader()
    #expect(try header.readInt32() == 68)
    parcel.append(Int32(42))

    var reader = parcel.reader()
    let decoded = try CollectionFields(from: &reader)
    #expect(decoded.labels == ["", "A😀"])
    #expect(decoded.chunks?.map { $0?.id } == [nil, 7])
    #expect(decoded.modes == [.HIGH, unknownMode])
    #expect(try reader.readInt32() == 42)

    var older = Parcel()
    older.append(Int32(4))
    var oldReader = older.reader()
    let defaults = try CollectionFields(from: &oldReader)
    #expect(defaults.labels.isEmpty && defaults.chunks == nil && defaults.modes.isEmpty)
}

@Test func generatedNestedUnionsPreserveTagsAndPresenceMarkers() throws {
    var parcel = Parcel()
    try UnionEnvelope(choice: .choice(.big(42)), optionalChoice: .chunk(nil)).write(to: &parcel)
    #expect(parcel.bytes == [
        40, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0,
        1, 0, 0, 0, 42, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
    ])
    var reader = parcel.reader()
    let decoded = try UnionEnvelope(from: &reader)
    guard case let .choice(.big(value)) = decoded.choice,
          case .some(.chunk(nil)) = decoded.optionalChoice else {
        Issue.record("Expected the original nested variants")
        return
    }
    #expect(value == 42)
    #expect(reader.isAtEnd)

    var older = Parcel()
    older.append(Int32(4))
    var oldReader = older.reader()
    let defaults = try UnionEnvelope(from: &oldReader)
    guard case let .number(number) = defaults.choice else {
        Issue.record("Expected the first union variant")
        return
    }
    #expect(number == 0 && defaults.optionalChoice == nil)
}

@Test func generatedEnumFieldsUseBackingAndDeclaredDefaults() throws {
    let initialized = EnumFields()
    #expect(initialized.mode == .RUNNING)
    #expect(initialized.byteMode == .HIGH)
    #expect(initialized.implicitMode.rawValue == 0)

    var parcel = Parcel()
    try initialized.write(to: &parcel)
    #expect(parcel.bytes == [16, 0, 0, 0, 4, 0, 0, 0, 249, 255, 255, 255, 0, 0, 0, 0])

    var older = Parcel()
    older.append(Int32(8))
    older.append(Int32(17))
    var reader = older.reader()
    let decoded = try EnumFields(from: &reader)
    #expect(decoded.mode.rawValue == 17)
    #expect(decoded.byteMode == .HIGH && decoded.implicitMode.rawValue == 0)
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

private let payloadAIDL = """
        package demo;
        parcelable Payload {
            int id;
            String name;
            @nullable byte[] data;
            @nullable String note;
            byte[] trailer;
        }
        """

@Test func generatedParcelableSizesVariableLengthFields() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aidl")
    try payloadAIDL.write(to: path, atomically: true, encoding: .utf8)
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

@Test func generatedNestedParcelableRespectsParentFrame() throws {
    var parcel = Parcel()
    try Nested(child: Chunk(id: 3), tail: 9).write(to: &parcel)
    #expect(parcel.bytes.count == 36)
    var header = parcel.reader()
    #expect(try header.readInt32() == 36)
    #expect(try header.readInt32() == 0)
    #expect(try header.readInt32() == 1)
    #expect(try header.readInt32() == 20)

    var truncated = Parcel()
    truncated.append(Int32(12))
    truncated.append(Int32(0))
    truncated.append(Int32(1))
    truncated.append(Int32(20))
    var reader = truncated.reader()
    #expect(throws: ParcelError.endOfParcel) { try Nested(from: &reader) }
    #expect(try reader.readInt32() == 20)
}

@Test func generatedParcelableUsesExplicitDefaultsForMissingFields() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aidl")
    try """
        package demo;
        parcelable Defaults {
            int mask = (1 << 4) | 3;
            byte level = -7;
            boolean enabled = true;
            String title = "hello " + "binder";
            @nullable String note = "default";
        }
        """.write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("GeneratedDefaults.swift")
    #expect(try AIDLCompiler().compile(sourcePath: path.path) == String(contentsOf: fixture, encoding: .utf8))

    let initialized = Defaults()
    #expect(initialized.mask == 19)
    #expect(initialized.level == -7)
    #expect(initialized.enabled)
    #expect(initialized.title == "hello binder")
    #expect(initialized.note == "default")

    var older = Parcel()
    older.append(Int32(8))
    older.append(Int32(42))
    var oldReader = older.reader()
    let decoded = try Defaults(from: &oldReader)
    #expect(decoded.mask == 42 && decoded.level == initialized.level)
    #expect(decoded.enabled && decoded.title == initialized.title && decoded.note == initialized.note)

    var parcel = Parcel()
    try Defaults(mask: 0, enabled: false, title: "", note: nil).write(to: &parcel)
    var reader = parcel.reader()
    let supplied = try Defaults(from: &reader)
    #expect(supplied.mask == 0 && !supplied.enabled && supplied.title.isEmpty && supplied.note == nil)
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

    override func echoInts(_ value: [Int32]) async throws -> [Int32] { value }

    override func echoLongs(_ value: [Int64]?) async throws -> [Int64]? { value }

    override func echoBools(_ value: [Bool]) async throws -> [Bool] { value }

    override func echoChars(_ value: [UInt16]) async throws -> [UInt16] { value }

    override func echoFloats(_ value: [Float]) async throws -> [Float] { value }

    override func echoDoubles(_ value: [Double]?) async throws -> [Double]? { value }

    override func echoTexts(_ value: [String]) async throws -> [String] { value }

    override func echoOptionalTexts(_ value: [String?]?) async throws -> [String?]? { value }

    override func echoChunks(_ value: [Chunk]) async throws -> [Chunk] { value }

    override func echoOptionalChunks(_ value: [Chunk?]?) async throws -> [Chunk?]? { value }

    override func echoModes(_ value: [Mode]?) async throws -> [Mode]? { value }

    override func echoByteModes(_ value: [ByteMode]) async throws -> [ByteMode] { value }

    override func echoEnumFields(_ value: EnumFields) async throws -> EnumFields { value }

    override func echoNested(_ value: Nested) async throws -> Nested { value }

    override func echoStamp(_ value: ManualStamp) async throws -> ManualStamp { value }

    override func echoOptionalStamp(_ value: ManualStamp?) async throws -> ManualStamp? { value }

    override func echoStamps(_ value: [ManualStamp]) async throws -> [ManualStamp] { value }

    override func echoOptionalStamps(_ value: [ManualStamp?]?) async throws -> [ManualStamp?]? { value }
}
