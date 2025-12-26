//
//  VirtualMicDriver.h
//  VoiceChanger Virtual Mic Driver
//
//  Audio Server Plug-In for macOS
//

#ifndef VirtualMicDriver_h
#define VirtualMicDriver_h

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <pthread.h>

#pragma mark - Constants

// デバイス設定
#define kSampleRate             48000.0
#define kBitsPerChannel         32
#define kChannelsPerFrame       1
#define kFrameSize              256
#define kBufferFrameCount       64

// オブジェクトID
enum {
    kObjectID_PlugIn            = 1,
    kObjectID_Device            = 2,
    kObjectID_Stream_Input      = 3,
    kObjectID_Volume_Input      = 4,
    kObjectID_Mute_Input        = 5,
};

// 共有メモリ
#define kSharedMemoryName       "com.voicechanger.audio"
#define kSharedMemoryMagic      0x4D564356  // 'VCVM'
#define kSharedMemoryVersion    1

#pragma mark - Shared Memory Structure

typedef struct {
    // ヘッダー (64 bytes aligned)
    uint32_t magic;
    uint32_t version;
    uint32_t sampleRate;
    uint32_t frameSize;
    uint32_t bufferFrames;
    _Atomic uint32_t writeIndex;
    _Atomic uint32_t readIndex;
    _Atomic uint32_t state;         // 0=inactive, 1=active
    uint32_t reserved[8];

    // リングバッファ (starts at offset 64)
    float samples[];
} VCSharedBuffer;

#pragma mark - Driver State

typedef struct {
    // ホスト参照
    AudioServerPlugInHostRef hostRef;

    // タイミング
    Float64 hostTicksPerFrame;
    UInt64 anchorHostTime;

    // 状態
    atomic_bool isIORunning;
    UInt32 ioClientCount;

    // 共有メモリ
    VCSharedBuffer* sharedBuffer;
    int sharedMemoryFD;
    size_t sharedMemorySize;

    // ボリューム/ミュート
    Float32 inputVolumeScalar;
    bool inputMute;

    // mutex
    pthread_mutex_t stateMutex;
    pthread_mutex_t ioMutex;

} VirtualMicDriverState;

#pragma mark - Function Prototypes

// ファクトリ関数
extern void* VirtualMic_Create(CFAllocatorRef inAllocator, CFUUIDRef inRequestedTypeUUID);

// プロパティ取得ヘルパー（VirtualMicProperties.c で定義）
OSStatus VirtualMic_GetPlugInPropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData);
OSStatus VirtualMic_GetDevicePropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData);
OSStatus VirtualMic_GetStreamPropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData);
OSStatus VirtualMic_GetVolumePropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData);
OSStatus VirtualMic_GetMutePropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData);

// グローバルドライバ状態（VirtualMicDriver.c で定義）
extern VirtualMicDriverState gDriverState;

#endif /* VirtualMicDriver_h */
