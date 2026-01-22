import Foundation
import CryptoKit

guard CommandLine.arguments.count == 3 else {
    print("Usage: swift sign_update.swift <file_path> <private_key_base64>")
    exit(1)
}

let filePath = CommandLine.arguments[1]
let keyBase64 = CommandLine.arguments[2]

guard let data = FileManager.default.contents(atPath: filePath) else {
    print("Error: Could not read file at \(filePath)")
    exit(1)
}

guard let keyData = Data(base64Encoded: keyBase64) else {
    print("Error: Invalid base64 key")
    exit(1)
}

do {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
    let signature = try key.signature(for: data)
    print(signature.base64EncodedString())
} catch {
    print("Error: Signing failed - \(error)")
    exit(1)
}
