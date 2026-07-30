import Darwin
import Foundation
import OSLog
import Security
import SystemConfiguration

public final class XPCClientValidator: @unchecked Sendable {
    static let requiredExecutablePath =
        "/Applications/PenguinFan Experimental.app/Contents/MacOS/FanControllerApp"
    static let requiredSigningIdentifier =
        "com.local.PenguinFan.experimental"

    typealias SecurityIdentity = (
        effectiveUID: uid_t,
        processID: pid_t
    )

    private static let logger = Logger(
        subsystem: "com.local.PenguinFan.experimental",
        category: "XPCValidation"
    )

    private let securityIdentity:
        @Sendable (NSXPCConnection) throws -> SecurityIdentity
    private let consoleUserUID: @Sendable () throws -> uid_t
    private let executablePath: @Sendable (pid_t) throws -> String
    private let signingIdentifier: @Sendable (String) throws -> String
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
            executablePath: { processID in
                var buffer = [CChar](
                    repeating: 0,
                    count: 4 * Int(MAXPATHLEN)
                )
                let length = proc_pidpath(
                    processID,
                    &buffer,
                    UInt32(buffer.count)
                )
                guard length > 0 else {
                    throw ValidationError.executableUnavailable
                }
                return String(
                    decoding: buffer.prefix(Int(length)).map {
                        UInt8(bitPattern: $0)
                    },
                    as: UTF8.self
                )
            },
            signingIdentifier: { path in
                var staticCode: SecStaticCode?
                let createStatus = SecStaticCodeCreateWithPath(
                    URL(fileURLWithPath: path) as CFURL,
                    [],
                    &staticCode
                )
                guard createStatus == errSecSuccess,
                      let staticCode
                else {
                    throw ValidationError.staticCodeUnavailable
                }
                guard SecStaticCodeCheckValidity(
                    staticCode,
                    [],
                    nil
                ) == errSecSuccess else {
                    throw ValidationError.invalidCodeSignature
                }

                var information: CFDictionary?
                let informationStatus = SecCodeCopySigningInformation(
                    staticCode,
                    [],
                    &information
                )
                guard informationStatus == errSecSuccess,
                      let dictionary = information as? [String: Any],
                      let identifier = dictionary[
                        kSecCodeInfoIdentifier as String
                      ] as? String
                else {
                    throw ValidationError.signingIdentifierUnavailable
                }
                return identifier
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
        executablePath: @escaping @Sendable (pid_t) throws -> String,
        signingIdentifier: @escaping @Sendable (String) throws -> String,
        logFailure: @escaping @Sendable (String) -> Void
    ) {
        self.securityIdentity = securityIdentity
        self.consoleUserUID = consoleUserUID
        self.executablePath = executablePath
        self.signingIdentifier = signingIdentifier
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

            let path = try executablePath(identity.processID)
            guard path == Self.requiredExecutablePath else {
                logFailure("executable path mismatch")
                return false
            }

            let identifier = try signingIdentifier(path)
            guard identifier == Self.requiredSigningIdentifier else {
                logFailure("signing identifier mismatch")
                return false
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
    case executableUnavailable
    case staticCodeUnavailable
    case invalidCodeSignature
    case signingIdentifierUnavailable
}
