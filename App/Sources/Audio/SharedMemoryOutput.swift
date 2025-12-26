import Foundation

/// 共有メモリ設定
public enum SharedMemoryConfig {
    public static let name = "com.voicechanger.audio"
    public static let magic: UInt32 = 0x4D564356  // 'VCVM'
    public static let version: UInt32 = 1
    public static let sampleRate: UInt32 = 48000
    public static let frameSize: UInt32 = 256
    public static let bufferFrames: UInt32 = 64  // 約340ms

    public static var headerSize: Int { 64 }  // アライメント済み
    public static var bufferSize: Int { Int(frameSize * bufferFrames) * MemoryLayout<Float>.size }
    public static var totalSize: Int { headerSize + bufferSize }
}

/// 共有メモリヘッダー構造体（Cと互換）
public struct VCSharedBufferHeader {
    var magic: UInt32
    var version: UInt32
    var sampleRate: UInt32
    var frameSize: UInt32
    var bufferFrames: UInt32
    var writeIndex: UInt32  // Atomic
    var readIndex: UInt32   // Atomic
    var state: UInt32       // Atomic: 0=inactive, 1=active
    var reserved: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
}

/// 共有メモリ出力（App → Virtual Mic Driver）
public final class SharedMemoryOutput {

    // MARK: - Properties

    private var fileDescriptor: Int32 = -1
    private var mappedMemory: UnsafeMutableRawPointer?
    private var mappedSize: Int = 0

    private var header: UnsafeMutablePointer<VCSharedBufferHeader>?
    private var samples: UnsafeMutablePointer<Float>?

    public private(set) var isConnected: Bool = false

    private let lock = NSLock()

    // MARK: - Initialization

    public init() {}

    deinit {
        disconnect()
    }

    // MARK: - Public Methods

    /// 共有メモリを作成して接続
    public func connect() throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isConnected else { return }

        // 共有メモリを作成
        let name = SharedMemoryConfig.name
        fileDescriptor = shm_open(name, O_CREAT | O_RDWR, 0644)

        guard fileDescriptor >= 0 else {
            throw SharedMemoryError.createFailed(errno: errno)
        }

        // サイズを設定
        let size = SharedMemoryConfig.totalSize
        guard ftruncate(fileDescriptor, off_t(size)) == 0 else {
            close(fileDescriptor)
            fileDescriptor = -1
            throw SharedMemoryError.truncateFailed(errno: errno)
        }

        // メモリマップ
        let ptr = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fileDescriptor, 0)
        guard ptr != MAP_FAILED else {
            close(fileDescriptor)
            fileDescriptor = -1
            throw SharedMemoryError.mmapFailed(errno: errno)
        }

        mappedMemory = ptr
        mappedSize = size

        // ポインタ設定
        header = ptr!.assumingMemoryBound(to: VCSharedBufferHeader.self)
        samples = (ptr! + SharedMemoryConfig.headerSize).assumingMemoryBound(to: Float.self)

        // ヘッダー初期化
        initializeHeader()

        isConnected = true
        logInfo("SharedMemory connected", category: .audio)
    }

    /// 共有メモリを切断
    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }

        guard isConnected else { return }

        // 状態を非アクティブに
        if let header = header {
            OSAtomicCompareAndSwap32(1, 0, UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.state))))
        }

        // メモリアンマップ
        if let ptr = mappedMemory {
            munmap(ptr, mappedSize)
            mappedMemory = nil
        }

        // ファイルディスクリプタをクローズ
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        header = nil
        samples = nil
        isConnected = false

        logInfo("SharedMemory disconnected", category: .audio)
    }

    /// 音声サンプルを書き込み
    /// - Parameter buffer: Float32サンプルの配列
    /// - Returns: 書き込んだサンプル数
    @discardableResult
    public func write(_ buffer: [Float]) -> Int {
        guard isConnected, let header = header, let samples = samples else {
            return 0
        }

        let bufferCapacity = Int(SharedMemoryConfig.frameSize * SharedMemoryConfig.bufferFrames)
        let count = min(buffer.count, bufferCapacity)

        // 現在のインデックス取得（Atomic）
        let writeIdx = Int(OSAtomicAdd32(0, UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.writeIndex)))))
        let readIdx = Int(OSAtomicAdd32(0, UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.readIndex)))))

        // 空き容量チェック
        let used = (writeIdx >= readIdx) ? (writeIdx - readIdx) : (bufferCapacity - readIdx + writeIdx)
        let available = bufferCapacity - used - 1  // 1サンプル分の余裕

        if available < count {
            // オーバーラン - 古いデータを破棄
            logWarning("SharedMemory overrun, dropping samples", category: .audio)
        }

        // 書き込み位置
        let startPos = writeIdx % bufferCapacity

        if startPos + count <= bufferCapacity {
            // 連続書き込み
            buffer.withUnsafeBufferPointer { src in
                memcpy(samples.advanced(by: startPos), src.baseAddress!, count * MemoryLayout<Float>.size)
            }
        } else {
            // 2分割書き込み（wrap-around）
            let firstPart = bufferCapacity - startPos
            let secondPart = count - firstPart

            buffer.withUnsafeBufferPointer { src in
                memcpy(samples.advanced(by: startPos), src.baseAddress!, firstPart * MemoryLayout<Float>.size)
                memcpy(samples, src.baseAddress!.advanced(by: firstPart), secondPart * MemoryLayout<Float>.size)
            }
        }

        // 書き込みインデックス更新（Atomic）
        OSAtomicAdd32(Int32(count), UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.writeIndex))))

        return count
    }

    /// 状態をアクティブに設定
    public func activate() {
        guard let header = header else { return }
        OSAtomicCompareAndSwap32(0, 1, UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.state))))
    }

    /// 状態を非アクティブに設定
    public func deactivate() {
        guard let header = header else { return }
        OSAtomicCompareAndSwap32(1, 0, UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.state))))
    }

    /// リングバッファをリセット
    public func reset() {
        guard let header = header else { return }
        OSAtomicCompareAndSwap32(
            OSAtomicAdd32(0, UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.writeIndex)))),
            0,
            UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.writeIndex)))
        )
        OSAtomicCompareAndSwap32(
            OSAtomicAdd32(0, UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.readIndex)))),
            0,
            UnsafeMutablePointer<Int32>(OpaquePointer(UnsafeMutablePointer(&header.pointee.readIndex)))
        )
    }

    // MARK: - Private Methods

    private func initializeHeader() {
        guard let header = header else { return }

        header.pointee.magic = SharedMemoryConfig.magic
        header.pointee.version = SharedMemoryConfig.version
        header.pointee.sampleRate = SharedMemoryConfig.sampleRate
        header.pointee.frameSize = SharedMemoryConfig.frameSize
        header.pointee.bufferFrames = SharedMemoryConfig.bufferFrames
        header.pointee.writeIndex = 0
        header.pointee.readIndex = 0
        header.pointee.state = 0
        header.pointee.reserved = (0, 0, 0, 0, 0, 0, 0, 0)
    }
}

// MARK: - Errors

public enum SharedMemoryError: LocalizedError {
    case createFailed(errno: Int32)
    case truncateFailed(errno: Int32)
    case mmapFailed(errno: Int32)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .createFailed(let errno):
            return "Failed to create shared memory: \(String(cString: strerror(errno)))"
        case .truncateFailed(let errno):
            return "Failed to set shared memory size: \(String(cString: strerror(errno)))"
        case .mmapFailed(let errno):
            return "Failed to map shared memory: \(String(cString: strerror(errno)))"
        case .notConnected:
            return "Shared memory not connected"
        }
    }
}
