import Foundation

struct CallSnapshot: Decodable, Sendable {
    let id: String
    let chatId: String?
    let title: String
    let myPeerId: String?
    let joinedHere: Bool
    let myStatus: String
    let participants: [CallParticipant]
    let rtpCapabilities: JSONValue

    var connections: [CallConnection] { participants.flatMap(\.connections) }
}

struct CallParticipant: Decodable, Sendable {
    let id: String
    let name: String
    let status: String?
    let connections: [CallConnection]
}

struct CallConnection: Decodable, Sendable {
    let peerId: String
    let producer: CallProducer?
}

struct CallProducer: Decodable, Sendable {
    let id: String
    let paused: Bool
}

struct CallsSnapshot: Decodable, Sendable {
    let enabled: Bool
    let calls: [CallSnapshot]
    let iceServers: JSONValue
}

enum CallTarget {
    case chat(String)
    case call(String)
    var command: [String: JSONValue] {
        switch self {
        case .chat(let id): return ["action": .string("start"), "chatId": .string(id)]
        case .call(let id): return ["action": .string("join"), "callId": .string(id), "resetConnection": .bool(true)]
        }
    }
}

struct MediaTransportOptions: Decodable, Sendable {
    let id: String
    let iceParameters: JSONValue
    let iceCandidates: JSONValue
    let dtlsParameters: JSONValue
}

struct MediaConsumerOptions: Decodable, Sendable {
    let id: String
    let producerId: String
    let rtpParameters: JSONValue
}
