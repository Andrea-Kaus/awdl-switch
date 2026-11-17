import Darwin
import Foundation

enum AWDLInterface {
    private static let name = "awdl0"

    static func setUp(_ up: Bool) throws {
        if try isUp() == up { return }

        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        command.arguments = [name, up ? "up" : "down"]
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        try command.run()
        command.waitUntilExit()

        guard command.terminationStatus == 0 else {
            throw Failure("Couldn’t turn AWDL \(up ? "on" : "off") (ifconfig exit \(command.terminationStatus)).")
        }
        guard try isUp() == up else {
            throw Failure("AWDL did not stay \(up ? "on" : "off").")
        }
    }

    private static func isUp() throws -> Bool {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else {
            throw Failure("Couldn’t read network interfaces (errno \(errno)).")
        }
        defer { freeifaddrs(addresses) }
        var next = addresses
        while let entry = next {
            if String(cString: entry.pointee.ifa_name) == name {
                return entry.pointee.ifa_flags & UInt32(IFF_UP) != 0
            }
            next = entry.pointee.ifa_next
        }
        throw Failure("The awdl0 network interface is unavailable.")
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
