/// A declaration indexed by its fully qualified AIDL name.
public struct AIDLSymbol: Equatable, Sendable {
    public let qualifiedName: String
    public let declaration: AIDLDeclaration
}

public enum AIDLTypeResolutionError: Error, Sendable, CustomStringConvertible {
    case duplicateSymbol(String)
    case unresolvedType(String, sourcePath: String)
    case ambiguousImport(String, sourcePath: String)

    public var description: String {
        switch self {
        case let .duplicateSymbol(name): "duplicate AIDL declaration '\(name)'"
        case let .unresolvedType(name, sourcePath): "\(sourcePath): unresolved type '\(name)'"
        case let .ambiguousImport(name, sourcePath): "\(sourcePath): ambiguous import for '\(name)'"
        }
    }
}

/// The resolution of a type, including resolutions of its generic arguments.
public struct AIDLResolvedType: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case builtin(String)
        case declaration(String)
    }
    public let target: Target
    public let typeArguments: [AIDLResolvedType]
    public let arrayDimensions: Int
    public let annotations: [AIDLAnnotation]
}

/// Indexes declarations and resolves type names within a file and lexical scope.
public struct AIDLTypeResolver: Sendable {
    private static let builtins: Set<String> = [
        "void", "boolean", "byte", "char", "int", "long", "float", "double",
        "String", "CharSequence", "IBinder", "FileDescriptor", "ParcelFileDescriptor", "List", "Map"
    ]
    public let symbols: [String: AIDLSymbol]

    public init(graph: AIDLSourceGraph) throws {
        var index: [String: AIDLSymbol] = [:]
        for file in graph.files {
            try Self.index(file.declarations, prefix: file.packageName, into: &index)
        }
        symbols = index
    }

    /// `scope` contains enclosing declaration names, from outermost to innermost.
    public func resolve(_ type: AIDLType, in file: AIDLFile, scope: [String] = []) throws -> AIDLResolvedType {
        let target: AIDLResolvedType.Target
        if Self.builtins.contains(type.name) {
            target = .builtin(type.name)
        } else {
            target = .declaration(try resolveName(type.name, in: file, scope: scope))
        }
        return try AIDLResolvedType(
            target: target,
            typeArguments: type.typeArguments.map { try resolve($0, in: file, scope: scope) },
            arrayDimensions: type.arrayDimensions,
            annotations: type.annotations
        )
    }

    /// Resolves every type reference in the graph's declarations.
    public func validateTypes(in graph: AIDLSourceGraph) throws {
        for file in graph.files {
            try validate(file.declarations, in: file, scope: [])
        }
    }

    private func validate(_ declarations: [AIDLDeclaration], in file: AIDLFile, scope: [String]) throws {
        for declaration in declarations {
            switch declaration {
            case let .interface(value):
                let nestedScope = scope + [value.name]
                for constant in value.constants { _ = try resolve(constant.type, in: file, scope: nestedScope) }
                for method in value.methods {
                    _ = try resolve(method.returnType, in: file, scope: nestedScope)
                    for parameter in method.parameters { _ = try resolve(parameter.type, in: file, scope: nestedScope) }
                }
                try validate(value.nestedDeclarations, in: file, scope: nestedScope)
            case let .parcelable(value):
                let nestedScope = scope + [value.name]
                for field in value.fields { _ = try resolve(field.type, in: file, scope: nestedScope) }
                for constant in value.constants { _ = try resolve(constant.type, in: file, scope: nestedScope) }
                try validate(value.nestedDeclarations, in: file, scope: nestedScope)
            case let .union(value):
                let nestedScope = scope + [value.name]
                for field in value.fields { _ = try resolve(field.type, in: file, scope: nestedScope) }
                for constant in value.constants { _ = try resolve(constant.type, in: file, scope: nestedScope) }
                try validate(value.nestedDeclarations, in: file, scope: nestedScope)
            case .enumeration:
                break
            }
        }
    }

    private func resolveName(_ name: String, in file: AIDLFile, scope: [String]) throws -> String {
        let parts = name.split(separator: ".").map(String.init)
        // Check nested declarations, walking outward through enclosing scopes.
        for depth in stride(from: scope.count, through: 0, by: -1) {
            let candidate = (file.packageName + scope.prefix(depth) + parts).joined(separator: ".")
            if symbols[candidate] != nil { return candidate }
        }
        let matches = file.imports.filter { $0.last == parts.first }
        if matches.count > 1 { throw AIDLTypeResolutionError.ambiguousImport(name, sourcePath: file.sourcePath) }
        if let imported = matches.first {
            let candidate = (imported + parts.dropFirst()).joined(separator: ".")
            if symbols[candidate] != nil { return candidate }
        }
        if symbols[name] != nil { return name }
        throw AIDLTypeResolutionError.unresolvedType(name, sourcePath: file.sourcePath)
    }

    private static func index(_ declarations: [AIDLDeclaration], prefix: [String], into symbols: inout [String: AIDLSymbol]) throws {
        for declaration in declarations {
            let name: String
            let nested: [AIDLDeclaration]
            switch declaration {
            case let .interface(value): name = value.name; nested = value.nestedDeclarations
            case let .parcelable(value): name = value.name; nested = value.nestedDeclarations
            case let .enumeration(value): name = value.name; nested = []
            case let .union(value): name = value.name; nested = value.nestedDeclarations
            }
            let path = prefix + [name]
            let qualifiedName = path.joined(separator: ".")
            guard symbols[qualifiedName] == nil else { throw AIDLTypeResolutionError.duplicateSymbol(qualifiedName) }
            symbols[qualifiedName] = AIDLSymbol(qualifiedName: qualifiedName, declaration: declaration)
            try index(nested, prefix: path, into: &symbols)
        }
    }
}
