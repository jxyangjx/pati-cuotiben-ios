import Foundation
import SwiftData

enum ModelContainerFactory {
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            Child.self,
            LocalJob.self,
            Page.self,
            Question.self,
            Answer.self,
            CanonicalAnswer.self,
            Verdict.self,
            WrongItem.self,
        ])
        let name = inMemory ? "PaiTiCuoTiBen-\(UUID().uuidString)" : "PaiTiCuoTiBen"
        // Records stay in the local store. CloudKit is off; phase 1 has no sync.
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
