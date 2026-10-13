import Foundation

enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            if value & 1 == 1 {
                value = 0xEDB8_8320 ^ (value >> 1)
            } else {
                value >>= 1
            }
        }
        return value
    }
}

/// Stored (uncompressed) ZIP so a backup can be shared without extra libraries.
enum ZipStore {
    struct Entry {
        var name: String
        var data: Data
    }

    static func archive(entries: [Entry]) -> Data {
        var output = Data()
        var central = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let nameLength = UInt16(nameData.count)

            var local = Data()
            local.append(le32(0x0403_4B50))
            local.append(le16(20))
            local.append(le16(1 << 11))
            local.append(le16(0))
            local.append(le16(0))
            local.append(le16(0))
            local.append(le32(crc))
            local.append(le32(size))
            local.append(le32(size))
            local.append(le16(nameLength))
            local.append(le16(0))
            local.append(nameData)
            local.append(entry.data)

            var header = Data()
            header.append(le32(0x0201_4B50))
            header.append(le16(20))
            header.append(le16(20))
            header.append(le16(1 << 11))
            header.append(le16(0))
            header.append(le16(0))
            header.append(le16(0))
            header.append(le32(crc))
            header.append(le32(size))
            header.append(le32(size))
            header.append(le16(nameLength))
            header.append(le16(0))
            header.append(le16(0))
            header.append(le16(0))
            header.append(le16(0))
            header.append(le32(0))
            header.append(le32(offset))
            header.append(nameData)

            output.append(local)
            central.append(header)
            offset += UInt32(local.count)
        }

        let centralStart = UInt32(output.count)
        output.append(central)

        var end = Data()
        end.append(le32(0x0605_4B50))
        end.append(le16(0))
        end.append(le16(0))
        end.append(le16(UInt16(entries.count)))
        end.append(le16(UInt16(entries.count)))
        end.append(le32(UInt32(central.count)))
        end.append(le32(centralStart))
        end.append(le16(0))
        output.append(end)
        return output
    }

    private static func le16(_ value: UInt16) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: MemoryLayout<UInt16>.size)
    }

    private static func le32(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: MemoryLayout<UInt32>.size)
    }
}
