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

// ドライバインターフェース実装
static HRESULT VirtualMic_QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface);
static ULONG VirtualMic_AddRef(void* inDriver);
static ULONG VirtualMic_Release(void* inDriver);
static OSStatus VirtualMic_Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost);
static OSStatus VirtualMic_CreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID);
static OSStatus VirtualMic_DestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID);
static OSStatus VirtualMic_AddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
static OSStatus VirtualMic_RemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
static OSStatus VirtualMic_PerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);
static OSStatus VirtualMic_AbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);

// プロパティ操作
static Boolean VirtualMic_HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress);
static OSStatus VirtualMic_IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable);
static OSStatus VirtualMic_GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32* outDataSize);
static OSStatus VirtualMic_GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData);
static OSStatus VirtualMic_SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, const void* inData);

// I/O操作
static OSStatus VirtualMic_StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus VirtualMic_StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus VirtualMic_GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed);
static OSStatus VirtualMic_WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outIsInput);
static OSStatus VirtualMic_BeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);
static OSStatus VirtualMic_DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer);
static OSStatus VirtualMic_EndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);

// ヘルパー関数
static OSStatus SharedMemory_Open(VirtualMicDriverState* state);
static void SharedMemory_Close(VirtualMicDriverState* state);

#endif /* VirtualMicDriver_h */
