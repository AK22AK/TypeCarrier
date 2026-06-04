import CryptoKit
import Foundation

public enum AndroidPairingCode {
    public static func isValid(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }

    public static func generate(randomNumber: (Range<Int>) -> Int = { Int.random(in: $0) }) -> String {
        String(format: "%06d", randomNumber(0..<1_000_000))
    }
}

public struct AndroidTrustToken: Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func generate() throws -> AndroidTrustToken {
        try generate(randomBytes: secureRandomBytes(count:))
    }

    public static func generate(randomBytes: (Int) throws -> Data) throws -> AndroidTrustToken {
        AndroidTrustToken(rawValue: urlSafeBase64(try randomBytes(32)))
    }

    public static func proof(token: AndroidTrustToken, challenge: Data) -> String {
        let key = SymmetricKey(data: Data(token.rawValue.utf8))
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: challenge, using: key)
        return urlSafeBase64(Data(authenticationCode))
    }

    public static func verify(token: AndroidTrustToken, challenge: Data, proof: String) -> Bool {
        self.proof(token: token, challenge: challenge) == proof
    }

    private static func secureRandomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AndroidTrustTokenError.randomGenerationFailed(status)
        }
        return Data(bytes)
    }

    private static func urlSafeBase64(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum AndroidTrustTokenError: Error, Equatable, Sendable {
    case randomGenerationFailed(OSStatus)
}
