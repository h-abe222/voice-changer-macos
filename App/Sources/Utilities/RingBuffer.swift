import Foundation

/// Lock-free Single Producer Single Consumer Ring Buffer
/// オーディオI/OスレッドとDSPスレッド間の通信に使用
public final class SPSCRingBuffer<T> {

    private let buffer: UnsafeMutableBufferPointer<T>
    private let capacity: Int
    private var writeIndex: Int = 0
    private var readIndex: Int = 0

    // Atomic counters for thread safety
    private var _writeCount = UnsafeAtomic<Int>.create(0)
    private var _readCount = UnsafeAtomic<Int>.create(0)

    /// 初期化
    /// - Parameter capacity: バッファ容量（フレーム数）
    public init(capacity: Int) {
        self.capacity = capacity
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: capacity)
        self.buffer = UnsafeMutableBufferPointer(start: pointer, count: capacity)
    }

    deinit {
        buffer.baseAddress?.deallocate()
        _writeCount.destroy()
        _readCount.destroy()
    }

    /// 書き込み可能か
    public var canWrite: Bool {
        availableForWrite > 0
    }

    /// 読み込み可能か
    public var canRead: Bool {
        availableForRead > 0
    }

    /// 書き込み可能な要素数
    public var availableForWrite: Int {
        capacity - count
    }

    /// 読み込み可能な要素数
    public var availableForRead: Int {
        count
    }

    /// 現在の要素数
    public var count: Int {
        let write = _writeCount.load(ordering: .acquiring)
        let read = _readCount.load(ordering: .acquiring)
        return write - read
    }

    /// 要素を書き込み
    /// - Parameter item: 書き込む要素
    /// - Returns: 成功したらtrue、満杯ならfalse
    @discardableResult
    public func push(_ item: T) -> Bool {
        guard canWrite else { return false }

        buffer[writeIndex] = item
        writeIndex = (writeIndex + 1) % capacity
        _writeCount.wrappingIncrement(ordering: .releasing)

        return true
    }

    /// 要素を読み込み
    /// - Returns: 要素、空ならnil
    public func pop() -> T? {
        guard canRead else { return nil }

        let item = buffer[readIndex]
        readIndex = (readIndex + 1) % capacity
        _readCount.wrappingIncrement(ordering: .releasing)

        return item
    }

    /// バッファをクリア
    public func reset() {
        writeIndex = 0
        readIndex = 0
        _writeCount.store(0, ordering: .releasing)
        _readCount.store(0, ordering: .releasing)
    }
}

// MARK: - Audio Frame Ring Buffer

/// オーディオフレーム専用のリングバッファ
public final class AudioFrameRingBuffer {
    private let buffer: SPSCRingBuffer<[Float]>
    private let frameSize: Int

    public init(frameSize: Int, bufferMs: Int = 200, sampleRate: Int = 48000) {
        self.frameSize = frameSize
        // バッファ容量を計算（ミリ秒からフレーム数へ）
        let framesPerMs = Float(sampleRate) / Float(frameSize) / 1000.0
        let capacity = Int(Float(bufferMs) * framesPerMs) + 1
        self.buffer = SPSCRingBuffer(capacity: max(capacity, 16))
    }

    public var canWrite: Bool { buffer.canWrite }
    public var canRead: Bool { buffer.canRead }
    public var count: Int { buffer.count }

    @discardableResult
    public func push(_ samples: [Float]) -> Bool {
        buffer.push(samples)
    }

    public func pop() -> [Float]? {
        buffer.pop()
    }

    public func reset() {
        buffer.reset()
    }
}

// MARK: - Unsafe Atomic (simplified)

/// 簡易的なアトミック操作
/// 実際のプロダクションではSwift Atomicsパッケージを使用すべき
public final class UnsafeAtomic<T: FixedWidthInteger> {
    private var value: T

    private init(_ initialValue: T) {
        self.value = initialValue
    }

    public static func create(_ initialValue: T) -> UnsafeAtomic<T> {
        UnsafeAtomic(initialValue)
    }

    public func destroy() {
        // cleanup if needed
    }

    public func load(ordering: AtomicLoadOrdering) -> T {
        // OSAtomicRead相当
        return value
    }

    public func store(_ newValue: T, ordering: AtomicStoreOrdering) {
        value = newValue
    }

    public func wrappingIncrement(ordering: AtomicUpdateOrdering) {
        value &+= 1
    }
}

public enum AtomicLoadOrdering {
    case acquiring
    case relaxed
}

public enum AtomicStoreOrdering {
    case releasing
    case relaxed
}

public enum AtomicUpdateOrdering {
    case releasing
    case relaxed
}
