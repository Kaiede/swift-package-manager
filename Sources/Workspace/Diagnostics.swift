/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import Utility
import PackageModel
import PackageLoading
import PackageGraph
import Foundation

public struct ManifestParseDiagnostic: DiagnosticData {
    public static let id = DiagnosticID(
        type: ManifestParseDiagnostic.self,
        name: "org.swift.diags.manifest-parse",
        description: {
            $0 <<< { "manifest parse error(s):\n" + $0.errors.joined(separator: "\n") }
        }
    )

    public let errors: [String]
    public init(_ errors: [String]) {
        self.errors = errors
    }
}

public struct ManifestDuplicateDeclDiagnostic: DiagnosticData {
    public static let id = DiagnosticID(
        type: ManifestParseDiagnostic.self,
        name: "org.swift.diags.manifest-dup-dep-decl",
        description: {
            $0 <<< .substitution({
                let `self` = $0 as! ManifestDuplicateDeclDiagnostic
                let stream = BufferedOutputByteStream()

                stream <<< "manifest parse error(s): duplicate dependency declaration\n"
                let indent = Format.asRepeating(string: " ", count: 4)

                for duplicateDecls in self.duplicates {
                    for duplicate in duplicateDecls {
                        stream <<< indent <<< duplicate.url <<< " @ " <<< "\(duplicate.requirement)" <<< "\n"
                    }
                    stream <<< "\n"
                }

                return stream.bytes.asString!
            }, preference: .default)
        }
    )

    public let duplicates: [[PackageDependencyDescription]]
    public init(_ duplicates: [[PackageDependencyDescription]]) {
        self.duplicates = duplicates
    }
}

extension ManifestParseError: DiagnosticDataConvertible {
    public var diagnosticData: DiagnosticData {
        switch self {
        case .invalidManifestFormat(let error):
            return ManifestParseDiagnostic([error])
        case .runtimeManifestErrors(let errors):
            return ManifestParseDiagnostic(errors)
        case .duplicateDependencyDecl(let duplicates):
            return ManifestDuplicateDeclDiagnostic(duplicates)
        }
    }
}

public enum ResolverDiagnostics {

    public struct Unsatisfiable: DiagnosticData {
        public static let id = DiagnosticID(
            type: Unsatisfiable.self,
            name: "org.swift.diags.resolver.unsatisfiable",
            description: {
                $0 <<< "dependency graph is unresolvable;"
                $0 <<< .substitution({
                    let `self` = $0 as! Unsatisfiable

                    // If we don't have any additional data, return empty string.
                    if self.dependencies.isEmpty && self.pins.isEmpty {
                        return ""
                    }
                    var diag = "found these conflicting requirements:"
                    let indent = "    "

                    if !self.dependencies.isEmpty {
                        diag += "\n\nDependencies: \n"
                        diag += self.dependencies.map({ indent + Unsatisfiable.toString($0) }).joined(separator: "\n")
                    }

                    if !self.pins.isEmpty {
                        diag += "\n\nPins: \n"
                        diag += self.pins.map({ indent + Unsatisfiable.toString($0) }).joined(separator: "\n")
                    }
                    return diag
                }, preference: .default)
            }
        )

        static func toString(_ constraint: RepositoryPackageConstraint) -> String {
            let stream = BufferedOutputByteStream()
            stream <<< constraint.identifier.path <<< " @ "

            switch constraint.requirement {
            case .versionSet(let set):
                stream <<< set.description
            case .revision(let revision):
                stream <<< revision
            case .unversioned:
                stream <<< "unversioned"
            }

            return stream.bytes.asString!
        }

        /// The conflicting dependencies.
        public let dependencies: [RepositoryPackageConstraint]

        /// The conflicting pins.
        public let pins: [RepositoryPackageConstraint]

        public init( dependencies: [RepositoryPackageConstraint], pins: [RepositoryPackageConstraint]) {
            self.dependencies = dependencies
            self.pins = pins
        }
    }
}

public struct InvalidToolchainDiagnostic: DiagnosticData, Error {
    public static let id = DiagnosticID(
        type: InvalidToolchainDiagnostic.self,
        name: "org.swift.diags.invalid-toolchain",
        description: {
            $0 <<< "toolchain is invalid:" <<< { $0.error }
        }
    )

    public let error: String
    public init(_ error: String) {
        self.error = error
    }
}

public enum WorkspaceDiagnostics {

    //MARK: - Errors

    /// The diagnostic triggered when an operation fails because its completion
    /// would loose the uncommited changes in a repository.
    public struct UncommitedChanges: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: UncommitedChanges.self,
            name: "org.swift.diags.workspace.uncommited-changes",
            description: {
                $0 <<< "repository" <<< { "'\($0.repositoryPath.asString)'" } <<< "has uncommited changes"
            })
    
        /// The local path to the repository.
        public let repositoryPath: AbsolutePath
    }
    
    /// The diagnostic triggered when an operation fails because its completion
    /// would loose the unpushed changes in a repository.
    public struct UnpushedChanges: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: UnpushedChanges.self,
            name: "org.swift.diags.workspace.unpushed-changes",
            description: {
                $0 <<< "repository" <<< { "'\($0.repositoryPath.asString)'" } <<< "has unpushed changes"
            })
        
        /// The local path to the repository.
        public let repositoryPath: AbsolutePath
    }
    
    public struct LocalDependencyEdited: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: LocalDependencyEdited.self,
            name: "org.swift.diags.workspace.local-dependency-edited",
            description: {
                $0 <<< "local dependency" <<< { "'\($0.dependencyName)'" } <<< "can't be edited"
            })

        /// The name of the dependency being edited.
        public let dependencyName: String
    }

    /// The diagnostic triggered when the edit operation fails because the dependency
    /// is already in edit mode.
    public struct DependencyAlreadyInEditMode: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: DependencyAlreadyInEditMode.self,
            name: "org.swift.diags.workspace.dependency-already-in-edit-mode",
            description: {
                $0 <<< "dependency" <<< { "'\($0.dependencyName)'" } <<< "already in edit mode"
            })
        
        /// The name of the dependency being edited.
        public let dependencyName: String
    }
    
    /// The diagnostic triggered when the unedit operation fails because the dependency
    /// is not in edit mode.
    public struct DependencyNotInEditMode: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: DependencyNotInEditMode.self,
            name: "org.swift.diags.workspace.dependency-not-in-edit-mode",
            description: {
                $0 <<< "dependency" <<< { "'\($0.dependencyName)'" } <<< "not in edit mode"
            })
        
        /// The name of the dependency being unedited.
        public let dependencyName: String
    }
    
    /// The diagnostic triggered when the edit operation fails because the branch
    /// to be created already exists.
    public struct BranchAlreadyExists: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: BranchAlreadyExists.self,
            name: "org.swift.diags.workspace.branch-already-exists",
            description: {
                $0 <<< "branch" <<< { "'\($0.branch)'" } <<< "already exists"
            })
        
        /// The branch to create.
        public let branch: String
    }
    
    /// The diagnostic triggered when the edit operation fails because the specified
    /// revision does not exist.
    public struct RevisionDoesNotExist: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: RevisionDoesNotExist.self,
            name: "org.swift.diags.workspace.revision-does-not-exist",
            description: {
                $0 <<< "revision" <<< { "'\($0.revision)'" } <<< "does not exist"
            })
        
        /// The revision requested.
        public let revision: String
    }

    /// The diagnostic triggered when the root package has an incompatible tools version.
    public struct IncompatibleToolsVersion: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: IncompatibleToolsVersion.self,
            name: "org.swift.diags.workspace.incompatible-tools-version",
            description: {
                $0 <<< "package at" <<< { "'\($0.rootPackagePath.asString)'" }
                $0 <<< "requires a minimum Swift tools version of" <<< { $0.requiredToolsVersion.description }
                $0 <<< { "(currently \($0.currentToolsVersion.description))" }
            })
        
        /// The path of the package.
        public let rootPackagePath: AbsolutePath
        
        /// The tools version required by the package.
        public let requiredToolsVersion: ToolsVersion
        
        /// The current tools version.
        public let currentToolsVersion: ToolsVersion
    }
    
    /// The diagnostic triggered when the package at the edit destination is not the
    /// one user is trying to edit.
    public struct MismatchingDestinationPackage: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: MismatchingDestinationPackage.self,
            name: "org.swift.diags.workspace.mismatching-destination-package",
            description: {
                $0 <<< "package at" <<< { "'\($0.editPath.asString)'" }
                $0 <<< "is" <<< { $0.destinationPackage ?? "<unknown>" }
                $0 <<< "but was expecting" <<< { $0.expectedPackage }
            })
        
        /// The path to be edited to.
        public let editPath: AbsolutePath
        
        /// The package to edit.
        public let expectedPackage: String
        
        /// The package found at the edit location.
        public let destinationPackage: String?
    }

    //MARK: - Warnings

    /// The diagnostic triggered when a checked-out dependency is missing
    /// from the file-system.
    public struct CheckedOutDependencyMissing: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: CheckedOutDependencyMissing.self,
            name: "org.swift.diags.workspace.checked-out-dependency-missing",
            defaultBehavior: .warning,
            description: {
                $0 <<< "dependency" <<< { "'\($0.packageName)'" } <<< "is missing;"
                $0 <<< "cloning again"
            })

        /// The package name of the dependency.
        public let packageName: String
    }

    /// The diagnostic triggered when an edited dependency is missing
    /// from the file-system.
    public struct EditedDependencyMissing: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: EditedDependencyMissing.self,
            name: "org.swift.diags.workspace.edited-dependency-missing",
            defaultBehavior: .warning,
            description: {
                $0 <<< "dependency" <<< { "'\($0.packageName)'" } <<< "was being edited but is missing;"
                $0 <<< "falling back to original checkout"
            })
        
        /// The package name of the dependency.
        public let packageName: String
    }

    /// The diagnostic triggered when a dependency is edited from a revision
    /// but the dependency already exists at the target location.
    public struct EditRevisionNotUsed: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: EditRevisionNotUsed.self,
            name: "org.swift.diags.workspace.edit-revision-not-used",
            defaultBehavior: .warning,
            description: {
                $0 <<< "dependency" <<< { "'\($0.packageName)'" } <<< "already exists at the edit destination;"
                $0 <<< "not using revision" <<< { "'\($0.revisionIdentifier)'" }
            })

        /// The package name of the dependency.
        public let packageName: String

        /// The edit revision.
        public let revisionIdentifier: String
    }

    /// The diagnostic triggered when a dependency is edited with a branch
    /// but the dependency already exists at the target location.
    public struct EditBranchNotCheckedOut: DiagnosticData, Swift.Error {
        public static var id = DiagnosticID(
            type: EditBranchNotCheckedOut.self,
            name: "org.swift.diags.workspace.edit-branch-not-used",
            defaultBehavior: .warning,
            description: {
                $0 <<< "dependency" <<< { "'\($0.packageName)'" } <<< "already exists at the edit destination;"
                $0 <<< "not checking-out branch" <<< { "'\($0.branchName)'" }
            })

        /// The package name of the dependency.
        public let packageName: String

        /// The branch name
        public let branchName: String
    }

    public struct ResolverDurationNote: DiagnosticData {
        public static let id = DiagnosticID(
            type: ResolverDurationNote.self,
            name: "\(ResolverDurationNote.self)",
            defaultBehavior: .note,
            description: {
                $0 <<< "Completed resolution in" <<< { String(format: "%.2f", $0.duration) + "s" }
            }
        )

        public let duration: Double

        public init(_ duration: Double) {
            self.duration = duration
        }
    }

    public struct PD3DeprecatedDiagnostic: DiagnosticData {
        public static let id = DiagnosticID(
            type: PD3DeprecatedDiagnostic.self,
            name: "org.swift.diags.workspace.\(PD3DeprecatedDiagnostic.self)",
            defaultBehavior: .warning,
            description: {
                $0 <<< "PackageDescription API v3 is deprecated and will be removed in the future;"
                $0 <<< "used by package(s):" <<< { $0.manifests.joined(separator: ", ") }
            }
        )

        let manifests: [String]
    }

    public struct OutdatedResolvedFile: DiagnosticData {
        public static let id = DiagnosticID(
            type: OutdatedResolvedFile.self,
            name: "org.swift.diags.workspace.\(OutdatedResolvedFile.self)",
            defaultBehavior: .error,
            description: {
                $0 <<< "the Package.resolved file is most likely severely out-of-date and is preventing correct resolution;"
                $0 <<< "delete the resolved file and try again"
            }
        )
    }
}
