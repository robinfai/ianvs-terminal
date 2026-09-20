import CryptoKit
import Foundation
import Darwin

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

// Private material only goes to a file/stdin; stdout contains a public key.
let arguments = CommandLine.arguments
if arguments.count != 3 || !["generate", "verify"].contains(arguments[1]) {
  fail("usage: update_keys.swift generate|verify PRIVATE_KEY_FILE")
}
let path = URL(fileURLWithPath: arguments[2])
let key: Curve25519.Signing.PrivateKey
if arguments[1] == "generate" {
  guard !FileManager.default.fileExists(atPath: path.path) else {
    fail("Refusing to overwrite an existing signing key")
  }
  key = Curve25519.Signing.PrivateKey()
  let data = Data(key.rawRepresentation.base64EncodedString().utf8)
  guard FileManager.default.createFile(atPath: path.path, contents: data,
    attributes: [.posixPermissions: 0o600]) else { fail("Cannot write key") }
} else {
  let encoded = try String(contentsOf: path, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  guard let seed = Data(base64Encoded: encoded), seed.count == 32 else {
    fail("Use a 32-byte Sparkle private seed exported by generate_keys")
  }
  key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
  guard key.publicKey.rawRepresentation.base64EncodedString()
    == ProcessInfo.processInfo.environment["SPARKLE_PUBLIC_KEY"] else {
    fail("Sparkle private key does not match the public key embedded in the application")
  }
}
print(key.publicKey.rawRepresentation.base64EncodedString())
