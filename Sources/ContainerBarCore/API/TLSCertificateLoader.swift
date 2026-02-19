import Foundation
import Security

/// Utilities for loading TLS certificates and keys from PEM files
enum TLSCertificateLoader {

    /// Load a certificate from a PEM file
    static func loadCertificate(path: String) throws -> SecCertificate {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let pemString = String(data: data, encoding: .utf8) ?? ""

        // Strip PEM headers
        let base64 = pemString
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        guard let derData = Data(base64Encoded: base64) else {
            throw DockerAPIError.invalidConfiguration("Invalid certificate at \(path)")
        }

        guard let cert = SecCertificateCreateWithData(nil, derData as CFData) else {
            throw DockerAPIError.invalidConfiguration("Could not create certificate from \(path)")
        }

        return cert
    }

    /// Load a client identity (cert + key) from PEM files
    static func loadIdentity(certPath: String, keyPath: String) throws -> SecIdentity {
        let cert = try loadCertificate(path: certPath)

        // Load private key from PEM and detect key type
        let keyData = try Data(contentsOf: URL(fileURLWithPath: keyPath))
        let keyPEM = String(data: keyData, encoding: .utf8) ?? ""

        let keyType = detectKeyType(from: keyPEM)

        let keyBase64 = keyPEM
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        guard let derKeyData = Data(base64Encoded: keyBase64) else {
            throw DockerAPIError.invalidConfiguration("Invalid private key at \(keyPath)")
        }

        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: keyType,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(derKeyData as CFData, keyAttributes as CFDictionary, &error) else {
            throw DockerAPIError.invalidConfiguration("Could not create private key: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
        }

        // Create a PKCS#12 data blob to import as identity
        let p12Data = try createPKCS12(cert: cert, key: privateKey)

        var items: CFArray?
        let importOptions: [String: Any] = [
            kSecImportExportPassphrase as String: "" as CFString
        ]
        let status = SecPKCS12Import(p12Data as CFData, importOptions as CFDictionary, &items)

        guard status == errSecSuccess,
              let itemArray = items as? [[String: Any]],
              let firstItem = itemArray.first,
              let identity = firstItem[kSecImportItemIdentity as String] else {
            throw DockerAPIError.invalidConfiguration("Failed to import client identity (status: \(status))")
        }

        // swiftlint:disable:next force_cast
        return identity as! SecIdentity
    }

    /// Detect key type from PEM header
    private static func detectKeyType(from pemString: String) -> CFString {
        if pemString.contains("BEGIN EC PRIVATE KEY") {
            return kSecAttrKeyTypeECSECPrimeRandom
        }
        // PKCS#8 "BEGIN PRIVATE KEY" could be RSA or EC — default to RSA
        // since Docker TLS predominantly uses RSA keys
        return kSecAttrKeyTypeRSA
    }

    private static func createPKCS12(cert: SecCertificate, key: SecKey) throws -> Data {
        var keyParams = SecItemImportExportKeyParameters()
        keyParams.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        keyParams.passphrase = Unmanaged.passUnretained("" as CFString)

        var exportData: CFData?
        let status = withUnsafePointer(to: &keyParams) { paramsPtr in
            SecItemExport(
                [cert, key] as CFArray,
                .formatPKCS12,
                [],
                paramsPtr,
                &exportData
            )
        }

        guard status == errSecSuccess, let data = exportData else {
            throw DockerAPIError.invalidConfiguration("Failed to export identity as PKCS#12 (status: \(status))")
        }

        return data as Data
    }
}
