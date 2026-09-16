import Foundation

func decodeTLSChunkedBody(_ data: Data) throws -> Data {
    try HTTPResponseParser.decodeChunkedBody(data)
}
