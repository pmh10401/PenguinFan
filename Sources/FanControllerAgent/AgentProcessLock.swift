import Darwin
import Foundation

final class AgentProcessLock {
    static let defaultPath =
        "/private/var/run/com.m2max.fancontroller.agent.lock"

    private var descriptor: Int32

    init(path: String = defaultPath) throws {
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw AgentProcessLockError.systemCall("open", errno)
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let errorNumber = errno
            close(descriptor)
            if errorNumber == EWOULDBLOCK {
                throw AgentProcessLockError.alreadyRunning
            }
            throw AgentProcessLockError.systemCall(
                "flock",
                errorNumber
            )
        }

        self.descriptor = descriptor
    }

    func release() {
        guard descriptor >= 0 else {
            return
        }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}

enum AgentProcessLockError: Error, Equatable, LocalizedError {
    case alreadyRunning
    case systemCall(String, Int32)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "another fan controller agent is already running"
        case .systemCall(let operation, let errorNumber):
            "\(operation) failed: \(String(cString: strerror(errorNumber)))"
        }
    }
}
