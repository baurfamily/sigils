import Foundation
import MessagePack
import Testing
@testable import StudioCore

@Test func fragmentedMessagesAndExtensions() throws {
    let message = MessagePackValue.array([.uint(1), .extended(0, Data([42])), .string("héllo")])
    let bytes = pack(message)
    var stream = MessageStream()
    for byte in bytes.dropLast() {
        #expect(try stream.append(Data([byte])).isEmpty)
    }

    let last = try #require(bytes.last)
    #expect(try stream.append(Data([last])) == [message])
    try stream.finish()
}

@Test func coalescedMessages() throws {
    let first = MessagePackValue.array([.uint(1), .string("first")])
    let second = MessagePackValue.array([.uint(2), .string("second")])
    var stream = MessageStream()
    #expect(try stream.append(pack(first) + pack(second)) == [first, second])
    try stream.finish()
}

@Test func malformedAndTruncatedMessagesAreErrors() throws {
    var malformed = MessageStream()
    #expect(throws: (any Error).self) { try malformed.append(Data([0xC1])) }
    var truncated = MessageStream()
    #expect(try truncated.append(Data([0xD9])).isEmpty)
    #expect(throws: StudioError.self) { try truncated.finish() }
}

@Test func oversizedIntegersDoNotTrap() throws {
    #expect(throws: StudioError.self) { try MessagePackValue.uint(UInt64.max).integer() }
    #expect(try MessagePackValue.int(-1).integer() == -1)
}
