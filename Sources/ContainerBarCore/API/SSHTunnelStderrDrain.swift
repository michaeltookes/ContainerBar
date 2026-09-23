import Foundation

/// Drains an adopted SSH tunnel's stderr pipe so its fixed-size (~64 KB) buffer
/// can never fill.
///
/// `ssh` prints `channel N: open failed…` to stderr for every forwarded
/// connection that cannot reach the remote daemon (wrong `remoteSocketPath`, a
/// down remote daemon, …). Once the pipe buffer fills, `ssh` blocks on
/// `write(2)`, stops forwarding, and — because the process stays alive —
/// `isRunning` remains true, so the tunnel-death path never trips and every
/// request hangs until its deadline. Installing a `readabilityHandler` keeps
/// the buffer empty; the drained bytes are forwarded to a sink (production logs
/// them once at debug and discards them) so a genuinely useful failure message
/// still reaches the log without ever backing up.
///
/// The handler is installed *only* on the adopted path, after `waitForSocket`
/// returns. The launch-error path reads the same pipe with
/// `readDataToEndOfFile()` and runs only pre-adoption, so installing the handler
/// earlier would race that read.
enum SSHTunnelStderrDrain {
    /// Installs a readability handler that forwards drained data to `sink` and
    /// discards it. On EOF (the write end closing) the handler removes itself.
    static func installDrainHandler(
        on handle: FileHandle,
        onDrain sink: @escaping @Sendable (Data) -> Void
    ) {
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                // EOF: the ssh process closed its stderr. Stop observing.
                fileHandle.readabilityHandler = nil
                return
            }
            sink(data)
        }
    }

    /// Removes any installed drain handler. Safe to call with a `nil` handle or
    /// on a handle that has no handler installed. The read handle itself is not
    /// closed here: the pipe is owned by the ssh `Process`, which the connection
    /// terminates on teardown, so the pipe closes with the process and there is
    /// no risk of double-closing a handle Foundation still owns.
    static func removeDrainHandler(from handle: FileHandle?) {
        handle?.readabilityHandler = nil
    }
}
