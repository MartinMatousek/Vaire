import Foundation
import UniformTypeIdentifiers
import CoreTransferable

struct BlockTransfer: Codable, Transferable {
    let blockId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .timeKeeperBlock)
    }
}

extension UTType {
    static var timeKeeperBlock: UTType {
        UTType(exportedAs: "com.martinmatousek.timekeeper.block")
    }
}
