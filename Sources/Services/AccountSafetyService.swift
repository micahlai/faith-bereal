import Foundation
import Supabase

struct BlockedUser: Codable, Identifiable, Sendable {
    let user_id: UUID
    let display_name: String
    var id: UUID { user_id }
}
protocol AccountSafetyProviding: Sendable {
    func requestDeletion(appleCode: String, receipt: String) async throws
    func receiptStatus(_ receipt: String) async throws -> String
    func deletionStatus() async throws -> String
    func setBlock(userID: UUID, blocked: Bool) async throws
    func blockedUsers() async throws -> [BlockedUser]
    func report(blessingID: UUID?, responseID: UUID?, reason: String, detail: String) async throws
}
actor SupabaseAccountSafetyService: AccountSafetyProviding {
    let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }
    func requestDeletion(appleCode: String, receipt: String) async throws {
        struct Body: Encodable { let action = "request"; let apple_code: String; let receipt: String }
        struct Result: Decodable { let status: String }
        let result: Result = try await client.functions.invoke("account-lifecycle", options: FunctionInvokeOptions(body: Body(apple_code: appleCode, receipt: receipt)))
        guard result.status == "pending" else { throw URLError(.badServerResponse) }
    }
    func receiptStatus(_ receipt: String) async throws -> String {
        struct Body: Encodable { let action = "receipt"; let receipt: String }
        struct Result: Decodable { let status: String }
        let result: Result = try await client.functions.invoke("account-lifecycle", options: FunctionInvokeOptions(body: Body(receipt: receipt)))
        return result.status
    }
    func deletionStatus() async throws -> String {
        try await client.rpc("my_account_deletion_status").execute().value
    }
    func setBlock(userID: UUID, blocked: Bool) async throws {
        struct Params: Encodable { let p_user: UUID; let p_blocked: Bool }
        try await client.rpc("set_user_block", params: Params(p_user: userID, p_blocked: blocked)).execute()
    }
    func blockedUsers() async throws -> [BlockedUser] { try await client.rpc("my_blocked_users").execute().value }
    func report(blessingID: UUID?, responseID: UUID?, reason: String, detail: String) async throws {
        struct Params: Encodable { let p_blessing: UUID?; let p_response: UUID?; let p_reason: String; let p_detail: String }
        try await client.rpc("report_content", params: Params(p_blessing: blessingID, p_response: responseID, p_reason: reason, p_detail: detail)).execute()
    }
}
actor LocalAccountSafetyService: AccountSafetyProviding {
    private var blocks: Set<UUID> = []
    func requestDeletion(appleCode: String, receipt: String) async throws { }
    func receiptStatus(_ receipt: String) async throws -> String { "none" }
    func deletionStatus() async throws -> String { "none" }
    func setBlock(userID: UUID, blocked: Bool) async throws { if blocked { blocks.insert(userID) } else { blocks.remove(userID) } }
    func blockedUsers() async throws -> [BlockedUser] { blocks.map { BlockedUser(user_id: $0, display_name: "Blocked member") } }
    func report(blessingID: UUID?, responseID: UUID?, reason: String, detail: String) async throws { }
}
