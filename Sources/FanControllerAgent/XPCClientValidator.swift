import Darwin
import Foundation
import OSLog
import Security
import SystemConfiguration

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

    private static let protectedFilesystemObjects = [
        (path: requiredBundlePath, isDirectory: true),
        (
            path: requiredBundlePath + "/Contents",
            isDirectory: true
        ),
        (
            path: requiredBundlePath + "/Contents/MacOS",
            isDirectory: true
        ),
        (path: requiredExecutablePath, isDirectory: false),
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
    private let filesystemObjectIsSecure:
        @Sendable (String, Bool) throws -> Bool
    private let logFailure: @Sendable (String) -> Void

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
                guard guestStatus == errSecSuccess,
                      let guestCode
                else {
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
            filesystemObjectIsSecure: { path, isDirectory in
                var metadata = stat()
                guard lstat(path, &metadata) == 0,
                      metadata.st_uid == 0,
                      metadata.st_mode & (S_IWGRP | S_IWOTH) == 0
                else {
                    return false
                }
                let expectedType: mode_t = isDirectory ? S_IFDIR : S_IFREG
                return metadata.st_mode & S_IFMT == expectedType
            },
            logFailure: { reason in
                XPCClientValidator.logger.error(
                    "Rejected XPC client: \(reason, privacy: .public)"
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
        filesystemObjectIsSecure: @escaping @Sendable
            (String, Bool) throws -> Bool,
        logFailure: @escaping @Sendable (String) -> Void
    ) {
        self.securityIdentity = securityIdentity
        self.consoleUserUID = consoleUserUID
        self.processCodeIdentity = processCodeIdentity
        self.filesystemObjectIsSecure = filesystemObjectIsSecure
        self.logFailure = logFailure
    }

    public func accepts(_ connection: NSXPCConnection) -> Bool {
        do {
            let identity = try securityIdentity(connection)
            let currentConsoleUserID = try consoleUserUID()
            guard identity.effectiveUID == currentConsoleUserID else {
                logFailure("effective user mismatch")
                return false
            }

            let codeIdentity = try processCodeIdentity(identity.processID)
            guard codeIdentity.executablePath == Self.requiredExecutablePath else {
                logFailure("executable path mismatch")
                return false
            }
            guard codeIdentity.signingIdentifier ==
                    Self.requiredSigningIdentifier
            else {
                logFailure("signing identifier mismatch")
                return false
            }
            for object in Self.protectedFilesystemObjects {
                guard try filesystemObjectIsSecure(
                    object.path,
                    object.isDirectory
                ) else {
                    logFailure("installation permissions invalid")
                    return false
                }
            }
            return true
        } catch {
            logFailure("client inspection failed")
            return false
        }
    }
}

private enum ValidationError: Error {
    case securityIdentityUnavailable
    case consoleUserUnavailable
    case processCodeUnavailable
    case invalidProcessCode
    case processCodeMetadataUnavailable
}
