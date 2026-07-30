import Darwin
import Foundation
import OSLog
import Security
import SystemConfiguration

enum FilesystemObjectKind: Sendable {
    case directory
    case regularFile
    case other
}

struct FilesystemSecurityMetadata: Sendable {
    let ownerUID: uid_t
    let mode: mode_t
    let kind: FilesystemObjectKind
    let hasUnsafeExtendedACL: Bool
}

enum LiveProcessCodeInspectionError: Error {
    case unavailableForAdHoc
}

struct StaticCodeIdentity: Sendable {
    let signingIdentifier: String
    let teamIdentifier: String?
    let isAdHoc: Bool
}

public final class XPCClientValidator: @unchecked Sendable {
    static let requiredBundlePath =
        "/Applications/PenguinFan Experimental.app"
    static let requiredExecutablePath =
        "/Applications/PenguinFan Experimental.app/Contents/MacOS/FanControllerApp"
    static let requiredSigningIdentifier =
        "com.local.PenguinFan.experimental"

    typealias SecurityIdentity = (
        effectiveUID: uid_t,
        processID: pid_t
    )
    typealias ProcessCodeIdentity = (
        executablePath: String,
        signingIdentifier: String
    )

    static let requiredFilesystemPaths = [
        "/Applications",
        requiredBundlePath,
        requiredBundlePath + "/Contents",
        requiredBundlePath + "/Contents/MacOS",
        requiredExecutablePath,
    ]

    private static let logger = Logger(
        subsystem: "com.local.PenguinFan.experimental",
        category: "XPCValidation"
    )

    private let securityIdentity:
        @Sendable (NSXPCConnection) throws -> SecurityIdentity
    private let consoleUserUID: @Sendable () throws -> uid_t
    private let processCodeIdentity:
        @Sendable (pid_t) throws -> ProcessCodeIdentity
    private let processExecutablePath:
        @Sendable (pid_t) throws -> String
    private let canonicalPath: @Sendable (String) throws -> String
    private let staticCodeIdentity:
        @Sendable (String) throws -> StaticCodeIdentity
    private let filesystemMetadata:
        @Sendable (String) throws -> FilesystemSecurityMetadata
    private let logEvent: @Sendable (String) -> Void

    public convenience init() {
        self.init(
            securityIdentity: { connection in
                // Foundation does not publicly expose NSXPCConnection's raw
                // audit_token_t. These documented connection security
                // attributes are the audit-derived values intended for
                // listener admission decisions on macOS 13 and later.
                let processID = connection.processIdentifier
                guard processID > 0 else {
                    throw ValidationError.securityIdentityUnavailable
                }
                return (
                    effectiveUID: connection.effectiveUserIdentifier,
                    processID: processID
                )
            },
            consoleUserUID: {
                var userID: uid_t = 0
                guard SCDynamicStoreCopyConsoleUser(
                    nil,
                    &userID,
                    nil
                ) != nil, userID != 0 else {
                    throw ValidationError.consoleUserUnavailable
                }
                return userID
            },
            processCodeIdentity: { processID in
                let attributes = [
                    kSecGuestAttributePid as String: NSNumber(
                        value: processID
                    )
                ] as CFDictionary
                var guestCode: SecCode?
                let guestStatus = SecCodeCopyGuestWithAttributes(
                    nil,
                    attributes,
                    [],
                    &guestCode
                )
                guard guestStatus == errSecSuccess else {
                    if guestStatus == errSecCSNoSuchCode {
                        throw LiveProcessCodeInspectionError
                            .unavailableForAdHoc
                    }
                    throw ValidationError.processCodeUnavailable
                }
                guard let guestCode else {
                    throw ValidationError.processCodeUnavailable
                }
                guard SecCodeCheckValidity(
                    guestCode,
                    [],
                    nil
                ) == errSecSuccess else {
                    throw ValidationError.invalidProcessCode
                }

                var staticCode: SecStaticCode?
                let staticCodeStatus = SecCodeCopyStaticCode(
                    guestCode,
                    [],
                    &staticCode
                )
                guard staticCodeStatus == errSecSuccess,
                      let staticCode
                else {
                    throw ValidationError.processCodeMetadataUnavailable
                }

                var information: CFDictionary?
                let informationStatus = SecCodeCopySigningInformation(
                    staticCode,
                    [],
                    &information
                )
                guard informationStatus == errSecSuccess,
                      let dictionary = information as? [String: Any],
                      let executableURL = dictionary[
                        kSecCodeInfoMainExecutable as String
                      ] as? URL,
                      let signingIdentifier = dictionary[
                        kSecCodeInfoIdentifier as String
                      ] as? String
                else {
                    throw ValidationError.processCodeMetadataUnavailable
                }
                return (
                    executablePath: executableURL.path,
                    signingIdentifier: signingIdentifier
                )
            },
            processExecutablePath: { processID in
                try XPCClientValidator.inspectProcessExecutablePath(
                    processID
                )
            },
            canonicalPath: { path in
                try XPCClientValidator.resolveCanonicalPath(path)
            },
            staticCodeIdentity: { path in
                try XPCClientValidator.inspectStaticCode(at: path)
            },
            filesystemMetadata: { path in
                try XPCClientValidator.inspectFilesystemObject(path)
            },
            logFailure: { event in
                XPCClientValidator.logger.notice(
                    "XPC validation \(event, privacy: .public)"
                )
            }
        )
    }

    init(
        securityIdentity: @escaping @Sendable
            (NSXPCConnection) throws -> SecurityIdentity,
        consoleUserUID: @escaping @Sendable () throws -> uid_t,
        processCodeIdentity: @escaping @Sendable
            (pid_t) throws -> ProcessCodeIdentity,
        processExecutablePath: @escaping @Sendable
            (pid_t) throws -> String = { processID in
                try XPCClientValidator.inspectProcessExecutablePath(
                    processID
                )
            },
        canonicalPath: @escaping @Sendable
            (String) throws -> String = { path in
                try XPCClientValidator.resolveCanonicalPath(path)
            },
        staticCodeIdentity: @escaping @Sendable
            (String) throws -> StaticCodeIdentity = { path in
                try XPCClientValidator.inspectStaticCode(at: path)
            },
        filesystemMetadata: @escaping @Sendable
            (String) throws -> FilesystemSecurityMetadata,
        logFailure: @escaping @Sendable (String) -> Void
    ) {
        self.securityIdentity = securityIdentity
        self.consoleUserUID = consoleUserUID
        self.processCodeIdentity = processCodeIdentity
        self.processExecutablePath = processExecutablePath
        self.canonicalPath = canonicalPath
        self.staticCodeIdentity = staticCodeIdentity
        self.filesystemMetadata = filesystemMetadata
        logEvent = logFailure
    }

    public func accepts(_ connection: NSXPCConnection) -> Bool {
        do {
            let identity = try securityIdentity(connection)
            let currentConsoleUserID = try consoleUserUID()
            guard identity.effectiveUID == currentConsoleUserID else {
                reject(route: "primary", reason: "effective_uid_mismatch")
                return false
            }

            let codeIdentity: ProcessCodeIdentity
            do {
                codeIdentity = try processCodeIdentity(identity.processID)
            } catch LiveProcessCodeInspectionError.unavailableForAdHoc {
                return acceptsAdHocFallback(processID: identity.processID)
            } catch {
                reject(route: "primary", reason: "live_code_invalid")
                return false
            }
            guard codeIdentity.executablePath == Self.requiredExecutablePath else {
                reject(route: "primary", reason: "executable_path_mismatch")
                return false
            }
            guard codeIdentity.signingIdentifier ==
                    Self.requiredSigningIdentifier
            else {
                reject(route: "primary", reason: "identifier_mismatch")
                return false
            }
            try validateInstallationFilesystem()
            accept(route: "primary")
            return true
        } catch {
            reject(route: "primary", reason: "inspection_failed")
            return false
        }
    }

    private func acceptsAdHocFallback(processID: pid_t) -> Bool {
        do {
            let firstPath = try processExecutablePath(processID)
            guard firstPath == Self.requiredExecutablePath else {
                reject(route: "fallback", reason: "pid_path_mismatch")
                return false
            }

            let requiredCanonical = try canonicalPath(
                Self.requiredExecutablePath
            )
            guard requiredCanonical == Self.requiredExecutablePath,
                  try canonicalPath(firstPath) == requiredCanonical
            else {
                reject(route: "fallback", reason: "canonical_path_mismatch")
                return false
            }

            let staticIdentity = try staticCodeIdentity(requiredCanonical)
            guard staticIdentity.teamIdentifier?.isEmpty != false else {
                reject(route: "fallback", reason: "team_identifier_present")
                return false
            }
            guard staticIdentity.isAdHoc else {
                reject(route: "fallback", reason: "not_ad_hoc")
                return false
            }
            guard staticIdentity.signingIdentifier ==
                    Self.requiredSigningIdentifier
            else {
                reject(route: "fallback", reason: "identifier_mismatch")
                return false
            }

            try validateInstallationFilesystem()

            let secondPath = try processExecutablePath(processID)
            guard secondPath == firstPath,
                  try canonicalPath(secondPath) == requiredCanonical
            else {
                reject(route: "fallback", reason: "pid_changed_or_exited")
                return false
            }
            accept(route: "fallback")
            return true
        } catch {
            reject(route: "fallback", reason: "inspection_failed")
            return false
        }
    }

    private func validateInstallationFilesystem() throws {
        for path in Self.requiredFilesystemPaths {
            let metadata = try filesystemMetadata(path)
            let expectedKind: FilesystemObjectKind =
                path == Self.requiredExecutablePath
                    ? .regularFile
                    : .directory
            guard metadata.ownerUID == 0,
                  metadata.mode & (S_IWGRP | S_IWOTH) == 0,
                  metadata.kind == expectedKind,
                  !metadata.hasUnsafeExtendedACL
            else {
                throw ValidationError.installationPermissionsInvalid
            }
        }
    }

    private func accept(route: String) {
        logEvent("route=\(route) outcome=accepted reason=validated")
    }

    private func reject(route: String, reason: String) {
        logEvent("route=\(route) outcome=rejected reason=\(reason)")
    }

    private static func inspectProcessExecutablePath(
        _ processID: pid_t
    ) throws -> String {
        var buffer = [CChar](
            repeating: 0,
            count: 4 * Int(MAXPATHLEN)
        )
        let length = proc_pidpath(
            processID,
            &buffer,
            UInt32(buffer.count)
        )
        let pathLength = Int(length)
        guard length > 0,
              pathLength < buffer.count - 1,
              buffer[pathLength] == 0,
              let path = String(
                  bytes: buffer[..<pathLength].map {
                      UInt8(bitPattern: $0)
                  },
                  encoding: .utf8
              ),
              !path.isEmpty
        else {
            throw ValidationError.processPathUnavailable
        }
        return path
    }

    private static func resolveCanonicalPath(
        _ path: String
    ) throws -> String {
        guard let resolved = realpath(path, nil) else {
            throw ValidationError.canonicalPathUnavailable
        }
        defer {
            free(resolved)
        }
        return String(cString: resolved)
    }

    private static func inspectStaticCode(
        at path: String
    ) throws -> StaticCodeIdentity {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            [],
            &staticCode
        ) == errSecSuccess, let staticCode else {
            throw ValidationError.staticCodeUnavailable
        }
        guard SecStaticCodeCheckValidity(
            staticCode,
            [],
            nil
        ) == errSecSuccess else {
            throw ValidationError.invalidStaticCode
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            [],
            &information
        ) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let signingIdentifier = dictionary[
                kSecCodeInfoIdentifier as String
              ] as? String,
              let flags = dictionary[
                kSecCodeInfoFlags as String
              ] as? NSNumber
        else {
            throw ValidationError.staticCodeMetadataUnavailable
        }
        return StaticCodeIdentity(
            signingIdentifier: signingIdentifier,
            teamIdentifier: dictionary[
                kSecCodeInfoTeamIdentifier as String
            ] as? String,
            isAdHoc: flags.uint32Value
                & 0x0002 != 0
        )
    }

    private static func inspectFilesystemObject(
        _ path: String
    ) throws -> FilesystemSecurityMetadata {
        var fileStatus = stat()
        guard lstat(path, &fileStatus) == 0 else {
            throw ValidationError.filesystemMetadataUnavailable
        }
        let fileType = fileStatus.st_mode & S_IFMT
        let kind: FilesystemObjectKind
        switch fileType {
        case S_IFDIR:
            kind = .directory
        case S_IFREG:
            kind = .regularFile
        default:
            kind = .other
        }
        return FilesystemSecurityMetadata(
            ownerUID: fileStatus.st_uid,
            mode: fileStatus.st_mode,
            kind: kind,
            hasUnsafeExtendedACL: try hasUnsafeExtendedACL(path)
        )
    }

    private static func hasUnsafeExtendedACL(
        _ path: String
    ) throws -> Bool {
        guard let acl = acl_get_file(path, ACL_TYPE_EXTENDED) else {
            throw ValidationError.aclUnavailable
        }
        defer {
            _ = acl_free(UnsafeMutableRawPointer(acl))
        }

        var entry: acl_entry_t?
        var status = acl_get_entry(
            acl,
            Int32(ACL_FIRST_ENTRY.rawValue),
            &entry
        )
        while status == 1 {
            guard let currentEntry = entry else {
                throw ValidationError.aclUnavailable
            }
            var tag = acl_tag_t(0)
            guard acl_get_tag_type(currentEntry, &tag) == 0 else {
                throw ValidationError.aclUnavailable
            }
            if tag == ACL_EXTENDED_ALLOW {
                var permissions: acl_permset_t?
                guard acl_get_permset(
                    currentEntry,
                    &permissions
                ) == 0, let permissions else {
                    throw ValidationError.aclUnavailable
                }
                for permission in unsafeACLPermissions {
                    let result = acl_get_perm_np(
                        permissions,
                        permission
                    )
                    guard result >= 0 else {
                        throw ValidationError.aclUnavailable
                    }
                    if result == 1 {
                        return true
                    }
                }
            }
            status = acl_get_entry(
                acl,
                Int32(ACL_NEXT_ENTRY.rawValue),
                &entry
            )
        }
        guard status == 0 else {
            throw ValidationError.aclUnavailable
        }
        return false
    }

    private static let unsafeACLPermissions: [acl_perm_t] = [
        ACL_WRITE_DATA,
        ACL_APPEND_DATA,
        ACL_DELETE,
        ACL_DELETE_CHILD,
        ACL_WRITE_ATTRIBUTES,
        ACL_WRITE_EXTATTRIBUTES,
        ACL_WRITE_SECURITY,
        ACL_CHANGE_OWNER,
    ]
}

private enum ValidationError: Error {
    case securityIdentityUnavailable
    case consoleUserUnavailable
    case processCodeUnavailable
    case invalidProcessCode
    case processCodeMetadataUnavailable
    case processPathUnavailable
    case canonicalPathUnavailable
    case staticCodeUnavailable
    case invalidStaticCode
    case staticCodeMetadataUnavailable
    case installationPermissionsInvalid
    case filesystemMetadataUnavailable
    case aclUnavailable
}
