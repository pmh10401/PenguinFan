import FanControllerCore
import Foundation

actor SensorPoller {
    typealias ReadSnapshot = @Sendable () throws -> SensorSnapshot

    private let readSnapshot: ReadSnapshot

    init(readSnapshot: @escaping ReadSnapshot) {
        self.readSnapshot = readSnapshot
    }

    func run(
        deliver: @escaping @MainActor @Sendable (SensorSnapshot) -> Void,
        reportError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        while !Task.isCancelled {
            do {
                let snapshot = try readSnapshot()
                await deliver(snapshot)
            } catch {
                await reportError(error.localizedDescription)
            }

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }
}
