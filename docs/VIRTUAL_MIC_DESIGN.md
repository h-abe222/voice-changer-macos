# Virtual Mic Driver 設計書

## 1. 概要

### 1.1 目的

Voice Changer アプリから変換された音声を、Google Meet / Zoom / Teams などの会議アプリに送るための仮想マイクデバイスを実装する。

### 1.2 調査結果サマリー

**BlackHole** (https://github.com/ExistentialAudio/BlackHole) を参考に実装する。

| 項目 | BlackHole | Voice Changer Virtual Mic |
|------|-----------|--------------------------|
| ライセンス | GPL-3.0 | 独自実装（参考のみ） |
| チャンネル | 2/16/64/128/256 | 1（モノラル） |
| 用途 | 汎用ループバック | 専用（アプリ連携） |
| データ供給 | 内部リングバッファ | 共有メモリ経由 |

### 1.3 アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                     Voice Changer App                        │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ Audio Capture │ → │  DSP Chain   │ → │ SharedMemory │  │
│  └──────────────┘    └──────────────┘    └──────┬───────┘  │
└─────────────────────────────────────────────────┼───────────┘
                                                  │
                                                  ▼ IPC
┌─────────────────────────────────────────────────────────────┐
│              Virtual Mic Driver (.driver bundle)             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ SharedMemory │ → │ Ring Buffer  │ → │ IOProc出力   │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
                                                  │
                                                  ▼
                                        ┌──────────────┐
                                        │ 会議アプリ    │
                                        │ (Meet/Zoom)  │
                                        └──────────────┘
```

---

## 2. Audio Server Driver Plug-in 構造

### 2.1 オブジェクト階層

```
AudioServerPlugIn (Bundle)
  └─ PlugIn Object (kObjectID_PlugIn)
      └─ Device Object (kObjectID_Device)
          ├─ Input Stream (仮想マイク出力 = アプリへの入力)
          ├─ Volume Control
          └─ Mute Control
```

### 2.2 必須実装関数

```c
// ファクトリ関数
void* VirtualMic_Create(CFAllocatorRef, CFUUIDRef);

// ドライバインターフェース
AudioServerPlugInDriverInterface gDriverInterface = {
    // 初期化
    .Initialize         = VirtualMic_Initialize,
    .CreateDevice       = VirtualMic_CreateDevice,
    .DestroyDevice      = VirtualMic_DestroyDevice,

    // プロパティ
    .HasProperty              = VirtualMic_HasProperty,
    .IsPropertySettable       = VirtualMic_IsPropertySettable,
    .GetPropertyDataSize      = VirtualMic_GetPropertyDataSize,
    .GetPropertyData          = VirtualMic_GetPropertyData,
    .SetPropertyData          = VirtualMic_SetPropertyData,

    // I/O
    .StartIO            = VirtualMic_StartIO,
    .StopIO             = VirtualMic_StopIO,
    .GetZeroTimeStamp   = VirtualMic_GetZeroTimeStamp,
    .WillDoIOOperation  = VirtualMic_WillDoIOOperation,
    .BeginIOOperation   = VirtualMic_BeginIOOperation,
    .DoIOOperation      = VirtualMic_DoIOOperation,
    .EndIOOperation     = VirtualMic_EndIOOperation,
};
```

### 2.3 主要プロパティ

| プロパティ | 値 |
|-----------|-----|
| kAudioDevicePropertyDeviceName | "VoiceChanger Virtual Mic" |
| kAudioDevicePropertyDeviceUID | "com.voicechanger.virtualmicdriver" |
| kAudioDevicePropertyNominalSampleRate | 48000.0 |
| kAudioStreamPropertyPhysicalFormat | Float32, 48kHz, 1ch |
| kAudioDevicePropertyStreams | Input Stream のみ |

---

## 3. 共有メモリ設計

### 3.1 構造

```c
// 共有メモリレイアウト
typedef struct {
    // ヘッダー (64 bytes)
    uint32_t magic;           // 'VCVM' = 0x4D56435
    uint32_t version;         // 1
    uint32_t sampleRate;      // 48000
    uint32_t frameSize;       // 256
    uint32_t bufferFrames;    // 64 (約340ms)
    _Atomic uint32_t writeIndex;
    _Atomic uint32_t readIndex;
    _Atomic uint32_t state;   // 0=inactive, 1=active
    uint8_t reserved[32];

    // リングバッファ (frameSize * bufferFrames * sizeof(float))
    float samples[];          // 256 * 64 = 16384 floats = 64KB
} VCSharedBuffer;
```

### 3.2 共有メモリ名

```
/dev/shm/com.voicechanger.audio.buffer
```

macOSでは `/dev/shm` がないため、以下を使用：

```c
// POSIX共有メモリ
int fd = shm_open("com.voicechanger.audio", O_RDWR, 0644);
void* ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
```

### 3.3 同期方式

- **Lock-free**: Atomic操作でインデックス管理
- **SPSC**: Single Producer (App) / Single Consumer (Driver)
- **Wrap-around**: インデックスがバッファ終端で0に戻る

---

## 4. I/O処理フロー

### 4.1 DoIOOperation (ReadInput)

```c
static OSStatus VirtualMic_DoIOOperation(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    AudioObjectID inStreamObjectID,
    UInt32 inClientID,
    UInt32 inOperationID,
    UInt32 inIOBufferFrameSize,
    const AudioServerPlugInIOCycleInfo* inIOCycleInfo,
    void* ioMainBuffer,
    void* ioSecondaryBuffer)
{
    // 共有メモリからサンプルを読み取り
    VCSharedBuffer* shared = gSharedBuffer;

    if (shared == NULL || shared->state != 1) {
        // 接続なし or 非アクティブ → 無音を返す
        memset(ioMainBuffer, 0, inIOBufferFrameSize * sizeof(float));
        return noErr;
    }

    // リングバッファから読み取り
    uint32_t readIdx = atomic_load(&shared->readIndex);
    uint32_t writeIdx = atomic_load(&shared->writeIndex);

    uint32_t available = writeIdx - readIdx;
    if (available < inIOBufferFrameSize) {
        // アンダーラン → 無音で補完
        memset(ioMainBuffer, 0, inIOBufferFrameSize * sizeof(float));
        return noErr;
    }

    // コピー（wrap-around対応）
    uint32_t bufferFrames = shared->bufferFrames * shared->frameSize;
    uint32_t startPos = readIdx % bufferFrames;
    uint32_t endPos = (readIdx + inIOBufferFrameSize) % bufferFrames;

    if (endPos > startPos) {
        // 連続コピー
        memcpy(ioMainBuffer, &shared->samples[startPos],
               inIOBufferFrameSize * sizeof(float));
    } else {
        // 2分割コピー
        uint32_t firstPart = bufferFrames - startPos;
        memcpy(ioMainBuffer, &shared->samples[startPos],
               firstPart * sizeof(float));
        memcpy((float*)ioMainBuffer + firstPart, shared->samples,
               endPos * sizeof(float));
    }

    atomic_store(&shared->readIndex, readIdx + inIOBufferFrameSize);

    return noErr;
}
```

### 4.2 タイムスタンプ管理

```c
static OSStatus VirtualMic_GetZeroTimeStamp(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    Float64* outSampleTime,
    UInt64* outHostTime,
    UInt64* outSeed)
{
    // ホスト時間ベースでサンプル時間を計算
    UInt64 hostTime = mach_absolute_time();
    Float64 sampleTime = hostTime * gHostTicksToSampleTime;

    *outSampleTime = sampleTime;
    *outHostTime = hostTime;
    *outSeed = gSeed;

    return noErr;
}
```

---

## 5. インストール

### 5.1 バンドル構造

```
VirtualMicDriver.driver/
├── Contents/
│   ├── Info.plist
│   ├── MacOS/
│   │   └── VirtualMicDriver
│   └── Resources/
│       └── (icons, etc.)
```

### 5.2 Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.voicechanger.virtualmicdriver</string>
    <key>CFBundleName</key>
    <string>VoiceChanger Virtual Mic</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>AudioServerPlugIn</key>
    <dict>
        <key>Name</key>
        <string>VoiceChanger Virtual Mic</string>
    </dict>
</dict>
</plist>
```

### 5.3 インストールパス

```bash
/Library/Audio/Plug-Ins/HAL/VirtualMicDriver.driver
```

### 5.4 インストールスクリプト

```bash
#!/bin/bash
DRIVER_PATH="/Library/Audio/Plug-Ins/HAL"
DRIVER_NAME="VirtualMicDriver.driver"

# 古いドライバを削除
sudo rm -rf "$DRIVER_PATH/$DRIVER_NAME"

# 新しいドライバをコピー
sudo cp -R "$DRIVER_NAME" "$DRIVER_PATH/"

# 権限設定
sudo chown -R root:wheel "$DRIVER_PATH/$DRIVER_NAME"

# CoreAudioを再起動
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
```

---

## 6. セキュリティ考慮

### 6.1 コード署名

- Apple Developer ID での署名必須
- Notarization 必須（macOS 10.15+）
- Hardened Runtime 有効化

### 6.2 共有メモリアクセス

- アプリとドライバ間のみアクセス可能
- 権限は 0644（owner read/write, others read）
- 不正なデータは無視（magic/version チェック）

---

## 7. 実装タスク

### Phase 1: 基本実装

- [ ] Xcodeプロジェクト作成（.driver bundle）
- [ ] AudioServerPlugInDriverInterface 実装
- [ ] 基本プロパティ応答
- [ ] 無音出力（共有メモリなし）
- [ ] ビルド・インストールスクリプト

### Phase 2: 共有メモリ連携

- [ ] 共有メモリ作成/接続
- [ ] リングバッファ読み取り
- [ ] アンダーラン処理

### Phase 3: 安定化

- [ ] エラーハンドリング
- [ ] ログ出力
- [ ] コード署名
- [ ] Notarization

---

## 8. 参考資料

- [BlackHole GitHub](https://github.com/ExistentialAudio/BlackHole)
- [Apple Audio Server Plug-In SDK](https://developer.apple.com/documentation/coreaudio)
- [Core Audio Data Types Reference](https://developer.apple.com/documentation/coreaudio/core_audio_data_types)
