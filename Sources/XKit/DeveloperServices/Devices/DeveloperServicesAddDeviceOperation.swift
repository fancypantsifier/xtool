import Foundation
import DeveloperAPI

public struct DeveloperServicesAddDeviceOperation: DeveloperServicesOperation {
    public let context: SigningContext
    public init(context: SigningContext) {
        self.context = context
    }

    public func perform() async throws {
        guard let targetDevice = context.targetDevice else { return }

        // Skip registration if the device is already on the team. Registering it again normally
        // returns 409 CONFLICT (handled below), but once a team is at its device limit (e.g. 3 iPads
        // on a free account) Apple returns 403 FORBIDDEN instead, which would fail every install.
        let registered = try await DeveloperAPIPages {
            try await context.developerAPIClient.devicesGetCollection().ok.body.json
        } next: {
            $0.links.next
        }
        .map(\.data)
        .reduce(into: [], +=)
        if registered.contains(where: {
            $0.attributes?.udid?.caseInsensitiveCompare(targetDevice.udid) == .orderedSame
        }) {
            return
        }

        // try to register the device
        let response = try await context.developerAPIClient.devicesCreateInstance(
            body: .json(.init(data: .init(
                _type: .devices,
                attributes: .init(
                    name: targetDevice.name,
                    platform: .init(.ios),
                    udid: targetDevice.udid
                )
            )))
        )

        // we get a 409 CONFLICT if the device was already registered.
        // handle this by returning gracefully.
        if (try? response.conflict) != nil {
            return
        }

        // otherwise, we should get a 201 CREATED to indicate that the device
        // was added. any other case is unexpected, and this will throw.
        _ = try response.created
    }

}
