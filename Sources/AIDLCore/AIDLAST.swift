public struct AIDLFile: Equatable, Sendable {
    public let sourcePath: String
    public let packageName: [String]
    public let imports: [[String]]
    public let declarations: [AIDLDeclaration]
}

public struct AIDLAnnotation: Equatable, Sendable {
    public let name: String
    /// Tokens within the annotation's parentheses, retaining their source spelling.
    public let arguments: [AIDLToken]
}

public struct AIDLType: Equatable, Sendable {
    public let name: String
    public let typeArguments: [AIDLType]
    public let arrayDimensions: Int
    public let annotations: [AIDLAnnotation]
}

public indirect enum AIDLDeclaration: Equatable, Sendable {
    case interface(AIDLInterface)
    case parcelable(AIDLParcelable)
    case enumeration(AIDLEnum)
    case union(AIDLUnion)
}

public struct AIDLInterface: Equatable, Sendable {
    public let name: String
    public let descriptor: String
    public let annotations: [AIDLAnnotation]
    public let isOneway: Bool
    public let methods: [AIDLMethod]
    public let constants: [AIDLConstant]
    public let nestedDeclarations: [AIDLDeclaration]
}

public struct AIDLMethod: Equatable, Sendable {
    public let name: String
    public let annotations: [AIDLAnnotation]
    public let isOneway: Bool
    public let returnType: AIDLType
    public let parameters: [AIDLParameter]
    public let explicitTransactionId: UInt32?
    public let computedTransactionCode: UInt32
}

public struct AIDLParameter: Equatable, Sendable {
    public enum Direction: String, Equatable, Sendable { case `in`, out, inoutDirection = "inout" }
    public let name: String
    public let direction: Direction
    public let type: AIDLType
}

public struct AIDLField: Equatable, Sendable {
    public let name: String
    public let type: AIDLType
    public let defaultValue: [AIDLToken]?
}

public struct AIDLConstant: Equatable, Sendable {
    public let name: String
    public let type: AIDLType
    public let value: [AIDLToken]
}

public struct AIDLParcelable: Equatable, Sendable {
    public let name: String
    public let annotations: [AIDLAnnotation]
    public let isOpaqueForwardDecl: Bool
    public let typeParameters: [String]
    /// Backend declaration keywords and their string literal tokens.
    public let backendNames: [String: AIDLToken]
    public let fields: [AIDLField]
    public let constants: [AIDLConstant]
    public let nestedDeclarations: [AIDLDeclaration]
}

public struct AIDLEnum: Equatable, Sendable {
    public struct Case: Equatable, Sendable {
        public let name: String
        public let value: [AIDLToken]?
    }
    public let name: String
    public let annotations: [AIDLAnnotation]
    public let cases: [Case]
}

public struct AIDLUnion: Equatable, Sendable {
    public let name: String
    public let annotations: [AIDLAnnotation]
    public let fields: [AIDLField]
    public let constants: [AIDLConstant]
    public let nestedDeclarations: [AIDLDeclaration]
}
