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

public final class XPCClientValidator: @unchecked Sendable {
    static let requiredBundlePath =
        "/Applications/PenguinFan Experimental.app"
    static let requiredExecutablePath =
        "/Applications/PenguinFan Experimental.app/Contents/MacOS/FanControllerApp"
    static let requiredSigningIdentifier =
        "com.local.PenguinFan.experimental"
    static let requiredTeamIdentifier = "UUUQNVQ67B"

    typealias SecurityIdentity = (
        effectiveUID: uid_t,
        processID: pid_t
    )
    typealias ProcessCodeIdentity = (
        executablePath: String,
        signingIdentifier: String,
        teamIdentifier: String?
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
                    signingIdentifier: signingIdentifier,
                    teamIdentifier: dictionary[
                        kSecCodeInfoTeamIdentifier as String
                    ] as? String
                )
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
        filesystemMetadata: @escaping @Sendable
            (String) throws -> FilesystemSecurityMetadata,
        logFailure: @escaping @Sendable (String) -> Void
    ) {
        self.securityIdentity = securityIdentity
        self.consoleUserUID = consoleUserUID
        self.processCodeIdentity = processCodeIdentity
        self.filesystemMetadata = filesystemMetadata
        logEvent = logFailure
    }

    public func accepts(_ connection: NSXPCConnection) -> Bool {
        do {
            let identity = try securityIdentity(connection)
            let currentConsoleUserID = try consoleUserUID()
            guard identity.effectiveUID == currentConsoleUserID else {
                reject(reason: "effective_uid_mismatch")
                return false
            }

            let codeIdentity = try processCodeIdentity(identity.processID)
            guard codeIdentity.executablePath == Self.requiredExecutablePath else {
                reject(reason: "executable_path_mismatch")
                return false
            }
            guard codeIdentity.signingIdentifier ==
                    Self.requiredSigningIdentifier
            else {
                reject(reason: "identifier_mismatch")
                return false
            }
            guard let teamIdentifier = codeIdentity.teamIdentifier,
                  !teamIdentifier.isEmpty
            else {
                reject(reason: "team_identifier_missing")
                return false
            }
            guard teamIdentifier == Self.requiredTeamIdentifier else {
                reject(reason: "team_identifier_mismatch")
                return false
            }
            try validateInstallationFilesystem()
            accept()
            return true
        } catch {
            reject(reason: "inspection_failed")
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

    private func accept() {
        logEvent("outcome=accepted reason=validated")
    }

    private func reject(reason: String) {
        logEvent("outcome=rejected reason=\(reason)")
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
    case installationPermissionsInvalid
    case filesystemMetadataUnavailable
    case aclUnavailable
}
