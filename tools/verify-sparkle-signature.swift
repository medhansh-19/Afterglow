import CryptoKit
import Foundation

func reject(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}
let arguments = CommandLine.arguments
let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
guard let publicBytes = Data(base64Encoded: arguments[2]),
  let signature = Data(base64Encoded: arguments[3]) else { reject("Malformed Sparkle signature") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
guard key.isValidSignature(signature, for: data) else { reject("Update signature does not match the app's public key") }
print("Sparkle signature verified against the packaged public key.")
