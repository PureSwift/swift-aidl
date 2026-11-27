import AIDLCore
import Binder
import Testing

@Test func roundTripsAIDLMethodThroughBinder() async throws {
    var parser = try AIDLParser(source: """
        package demo;
        interface IEcho { int echo(int value) = 7; }
        """)
    let file = try parser.parse()
    guard case let .interface(interface) = try #require(file.declarations.first) else {
        Issue.record("Expected an AIDL interface")
        return
    }
    let method = try #require(interface.methods.first)
    let stub = EchoStub(descriptor: interface.descriptor)

    var request = Parcel()
    request.appendInterfaceToken(interface.descriptor)
    request.append(Int32(42))
    let reply = try await stub.transact(code: method.computedTransactionCode, data: request, flags: [])
    var reader = reply.reader()
    try reader.readException()
    #expect(try reader.readInt32() == 42)
    #expect(reader.isAtEnd)
}

private final class EchoStub: BinderStub, @unchecked Sendable {
    override func onTransact(
        code: UInt32,
        data: inout Parcel.Reader,
        reply: inout Parcel,
        flags: TransactionFlags
    ) async throws -> Bool {
        guard code == BinderConstants.firstCallTransaction + 7 else {
            return try await super.onTransact(code: code, data: &data, reply: &reply, flags: flags)
        }
        try data.enforceInterface(interfaceDescriptor)
        let value = try data.readInt32()
        reply.writeNoException()
        reply.append(value)
        return true
    }
}
