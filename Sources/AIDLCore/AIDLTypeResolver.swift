/// A declaration indexed by its fully qualified AIDL name.
public struct AIDLSymbol: Equatable, Sendable {
    public let qualifiedName: String
    public let declaration: AIDLDeclaration
    let sourceFile: AIDLFile
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
        "String", "CharSequence", "IBinder", "FileDescriptor", "ParcelFileDescriptor", "ParcelableHolder", "List", "Map"
    ]
    private static let builtinAliases = [
        "android.os.IBinder": "IBinder",
        "android.os.ParcelFileDescriptor": "ParcelFileDescriptor",
        "java.lang.String": "String",
        "java.lang.CharSequence": "CharSequence",
        "java.util.List": "List",
        "java.util.Map": "Map",
    ]

    static func builtinName(_ name: String) -> String? {
        builtins.contains(name) ? name : builtinAliases[name]
    }
    public let symbols: [String: AIDLSymbol]
    private let preprocessedNames: [String: [String]]

    public init(graph: AIDLSourceGraph) throws {
        var index: [String: AIDLSymbol] = [:]
        for file in graph.files {
            try Self.index(file.declarations, from: file, prefix: file.packageName, into: &index)
        }
        var preprocessed: [String: AIDLSymbol] = [:]
        for file in graph.preprocessedFiles {
            var fileIndex: [String: AIDLSymbol] = [:]
            try Self.index(file.declarations, from: file, prefix: file.packageName, into: &fileIndex)
            preprocessed.merge(fileIndex) { existing, _ in existing }
        }
        preprocessedNames = Dictionary(grouping: preprocessed.keys) { name in
            String(name.split(separator: ".").last ?? "")
        }
        symbols = index.merging(preprocessed) { source, _ in source }
    }

    /// `scope` contains enclosing declaration names, from outermost to innermost.
    public func resolve(_ type: AIDLType, in file: AIDLFile, scope: [String] = []) throws -> AIDLResolvedType {
        let target: AIDLResolvedType.Target
        if let builtin = Self.builtinName(type.name) {
            target = .builtin(builtin)
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
        _ = try validateTypeReferences(in: graph)
    }

    func validateTypeReferences(in graph: AIDLSourceGraph) throws -> Set<String> {
        var opaqueParcelables = Set<String>()
        for file in graph.files {
            try validate(file.declarations, in: file, scope: [], opaqueParcelables: &opaqueParcelables)
        }
        return opaqueParcelables
    }

    private func validate(
        _ declarations: [AIDLDeclaration],
        in file: AIDLFile,
        scope: [String],
        opaqueParcelables: inout Set<String>
    ) throws {
        func collectOpaqueTypes(_ type: AIDLResolvedType) {
            if case let .declaration(name) = type.target,
               case let .parcelable(parcelable)? = symbols[name]?.declaration,
               parcelable.isOpaqueForwardDecl {
                opaqueParcelables.insert(name)
            }
            for argument in type.typeArguments {
                collectOpaqueTypes(argument)
            }
        }

        for declaration in declarations {
            let nestedScope = scope + [declaration.name]
            let memberTypes: [AIDLType]
            switch declaration {
            case let .interface(value):
                memberTypes = value.constants.map(\.type) + value.methods.flatMap { method in
                    [method.returnType] + method.parameters.map(\.type)
                }
            case let .parcelable(value):
                memberTypes = value.fields.map(\.type) + value.constants.map(\.type)
            case let .union(value):
                memberTypes = value.fields.map(\.type) + value.constants.map(\.type)
            case .enumeration:
                continue
            }
            for type in memberTypes {
                collectOpaqueTypes(try resolve(type, in: file, scope: nestedScope))
            }
            try validate(declaration.nestedDeclarations, in: file, scope: nestedScope, opaqueParcelables: &opaqueParcelables)
        }
    }

    func resolveName(_ name: String, in file: AIDLFile, scope: [String]) throws -> String {
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
        if let candidates = preprocessedNames[name] {
            guard candidates.count == 1, let candidate = candidates.first else {
                throw AIDLTypeResolutionError.ambiguousImport(name, sourcePath: file.sourcePath)
            }
            return candidate
        }
        throw AIDLTypeResolutionError.unresolvedType(name, sourcePath: file.sourcePath)
    }

    private static func index(
        _ declarations: [AIDLDeclaration], from file: AIDLFile,
        prefix: [String], into symbols: inout [String: AIDLSymbol]
    ) throws {
        for declaration in declarations {
            let path = prefix + [declaration.name]
            let qualifiedName = path.joined(separator: ".")
            guard symbols[qualifiedName] == nil else { throw AIDLTypeResolutionError.duplicateSymbol(qualifiedName) }
            symbols[qualifiedName] = AIDLSymbol(qualifiedName: qualifiedName, declaration: declaration, sourceFile: file)
            try index(declaration.nestedDeclarations, from: file, prefix: path, into: &symbols)
        }
    }
}
