import Foundation
import UniformTypeIdentifiers
import CoreTransferable

struct BlockTransfer: Codable, Transferable {
    let blockId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .vaireBlock)
    }
}

extension UTType {
    static var vaireBlock: UTType {
        UTType(exportedAs: "com.martinmatousek.vaire.block")
    }
}
