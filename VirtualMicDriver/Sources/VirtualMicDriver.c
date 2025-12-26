//
//  VirtualMicDriver.c
//  VoiceChanger Virtual Mic Driver
//
//  Audio Server Plug-In for macOS
//

#include "VirtualMicDriver.h"
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <os/log.h>

#pragma mark - Globals

VirtualMicDriverState gDriverState = {0};
static UInt32 gRefCount = 0;

static os_log_t gLog = NULL;

#define LOG_DEBUG(fmt, ...) os_log_debug(gLog, fmt, ##__VA_ARGS__)
#define LOG_INFO(fmt, ...)  os_log_info(gLog, fmt, ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...) os_log_error(gLog, fmt, ##__VA_ARGS__)

// Forward declarations for static functions
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
static Boolean VirtualMic_HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress);
static OSStatus VirtualMic_IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable);
static OSStatus VirtualMic_GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32* outDataSize);
static OSStatus VirtualMic_GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData);
static OSStatus VirtualMic_SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, const void* inData);
static OSStatus VirtualMic_StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus VirtualMic_StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus VirtualMic_GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed);
static OSStatus VirtualMic_WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outIsInput);
static OSStatus VirtualMic_BeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);
static OSStatus VirtualMic_DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer);
static OSStatus VirtualMic_EndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);
static OSStatus SharedMemory_Open(VirtualMicDriverState* state);
static void SharedMemory_Close(VirtualMicDriverState* state);

#pragma mark - Driver Interface

static AudioServerPlugInDriverInterface gDriverInterface = {
    NULL,  // _reserved
    VirtualMic_QueryInterface,
    VirtualMic_AddRef,
    VirtualMic_Release,
    VirtualMic_Initialize,
    VirtualMic_CreateDevice,
    VirtualMic_DestroyDevice,
    VirtualMic_AddDeviceClient,
    VirtualMic_RemoveDeviceClient,
    VirtualMic_PerformDeviceConfigurationChange,
    VirtualMic_AbortDeviceConfigurationChange,
    VirtualMic_HasProperty,
    VirtualMic_IsPropertySettable,
    VirtualMic_GetPropertyDataSize,
    VirtualMic_GetPropertyData,
    VirtualMic_SetPropertyData,
    VirtualMic_StartIO,
    VirtualMic_StopIO,
    VirtualMic_GetZeroTimeStamp,
    VirtualMic_WillDoIOOperation,
    VirtualMic_BeginIOOperation,
    VirtualMic_DoIOOperation,
    VirtualMic_EndIOOperation,
};

static AudioServerPlugInDriverInterface* gDriverInterfacePtr = &gDriverInterface;

#pragma mark - Factory Function

void* VirtualMic_Create(CFAllocatorRef inAllocator, CFUUIDRef inRequestedTypeUUID) {
    (void)inAllocator;

    // ログ初期化
    if (gLog == NULL) {
        gLog = os_log_create("com.voicechanger.virtualmicdriver", "driver");
    }

    LOG_INFO("VirtualMic_Create called");

    // UUIDチェック
    if (!CFEqual(inRequestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        LOG_ERROR("Invalid type UUID requested");
        return NULL;
    }

    return &gDriverInterfacePtr;
}

#pragma mark - IUnknown Implementation

static HRESULT VirtualMic_QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface) {
    (void)inDriver;

    CFUUIDRef requestedUUID = CFUUIDCreateFromUUIDBytes(NULL, inUUID);
    if (requestedUUID == NULL) {
        return E_NOINTERFACE;
    }

    HRESULT result = E_NOINTERFACE;

    if (CFEqual(requestedUUID, IUnknownUUID) ||
        CFEqual(requestedUUID, kAudioServerPlugInDriverInterfaceUUID)) {
        VirtualMic_AddRef(inDriver);
        *outInterface = &gDriverInterfacePtr;
        result = S_OK;
    }

    CFRelease(requestedUUID);
    return result;
}

static ULONG VirtualMic_AddRef(void* inDriver) {
    (void)inDriver;
    return ++gRefCount;
}

static ULONG VirtualMic_Release(void* inDriver) {
    (void)inDriver;
    if (gRefCount > 0) {
        gRefCount--;
    }
    return gRefCount;
}

#pragma mark - Initialization

static OSStatus VirtualMic_Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost) {
    (void)inDriver;

    LOG_INFO("VirtualMic_Initialize");

    // ホスト参照を保存
    gDriverState.hostRef = inHost;

    // タイミング情報を計算
    mach_timebase_info_data_t timebaseInfo;
    mach_timebase_info(&timebaseInfo);
    Float64 hostTicksPerSecond = (Float64)timebaseInfo.denom * 1000000000.0 / (Float64)timebaseInfo.numer;
    gDriverState.hostTicksPerFrame = hostTicksPerSecond / kSampleRate;

    // 初期値設定
    gDriverState.inputVolumeScalar = 1.0f;
    gDriverState.inputMute = false;
    gDriverState.anchorHostTime = mach_absolute_time();

    // mutex初期化
    pthread_mutex_init(&gDriverState.stateMutex, NULL);
    pthread_mutex_init(&gDriverState.ioMutex, NULL);

    // 共有メモリを開く（存在しなければNULLのまま）
    SharedMemory_Open(&gDriverState);

    return noErr;
}

#pragma mark - Device Management

static OSStatus VirtualMic_CreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID) {
    (void)inDriver;
    (void)inDescription;
    (void)inClientInfo;

    LOG_INFO("VirtualMic_CreateDevice");

    *outDeviceObjectID = kObjectID_Device;
    return noErr;
}

static OSStatus VirtualMic_DestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID) {
    (void)inDriver;
    (void)inDeviceObjectID;

    LOG_INFO("VirtualMic_DestroyDevice");
    return noErr;
}

static OSStatus VirtualMic_AddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inClientInfo;

    LOG_DEBUG("VirtualMic_AddDeviceClient");
    return noErr;
}

static OSStatus VirtualMic_RemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inClientInfo;

    LOG_DEBUG("VirtualMic_RemoveDeviceClient");
    return noErr;
}

static OSStatus VirtualMic_PerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inChangeAction;
    (void)inChangeInfo;

    return noErr;
}

static OSStatus VirtualMic_AbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inChangeAction;
    (void)inChangeInfo;

    return noErr;
}

#pragma mark - Property Operations

static Boolean VirtualMic_HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress) {
    (void)inDriver;
    (void)inClientProcessID;

    switch (inObjectID) {
        case kObjectID_PlugIn:
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyManufacturer:
                case kAudioObjectPropertyOwnedObjects:
                case kAudioPlugInPropertyDeviceList:
                case kAudioPlugInPropertyTranslateUIDToDevice:
                case kAudioPlugInPropertyResourceBundle:
                    return true;
            }
            break;

        case kObjectID_Device:
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyName:
                case kAudioObjectPropertyManufacturer:
                case kAudioObjectPropertyOwnedObjects:
                case kAudioDevicePropertyDeviceUID:
                case kAudioDevicePropertyModelUID:
                case kAudioDevicePropertyTransportType:
                case kAudioDevicePropertyDeviceIsAlive:
                case kAudioDevicePropertyDeviceIsRunning:
                case kAudioDevicePropertyDeviceCanBeDefaultDevice:
                case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
                case kAudioDevicePropertyLatency:
                case kAudioDevicePropertyStreams:
                case kAudioObjectPropertyControlList:
                case kAudioDevicePropertyNominalSampleRate:
                case kAudioDevicePropertyAvailableNominalSampleRates:
                case kAudioDevicePropertyIsHidden:
                case kAudioDevicePropertyZeroTimeStampPeriod:
                case kAudioDevicePropertyIcon:
                    return true;
            }
            break;

        case kObjectID_Stream_Input:
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyName:
                case kAudioStreamPropertyIsActive:
                case kAudioStreamPropertyDirection:
                case kAudioStreamPropertyTerminalType:
                case kAudioStreamPropertyStartingChannel:
                case kAudioStreamPropertyLatency:
                case kAudioStreamPropertyVirtualFormat:
                case kAudioStreamPropertyPhysicalFormat:
                case kAudioStreamPropertyAvailableVirtualFormats:
                case kAudioStreamPropertyAvailablePhysicalFormats:
                    return true;
            }
            break;

        case kObjectID_Volume_Input:
        case kObjectID_Mute_Input:
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyOwnedObjects:
                case kAudioControlPropertyScope:
                case kAudioControlPropertyElement:
                case kAudioLevelControlPropertyScalarValue:
                case kAudioLevelControlPropertyDecibelValue:
                case kAudioLevelControlPropertyDecibelRange:
                case kAudioLevelControlPropertyConvertScalarToDecibels:
                case kAudioLevelControlPropertyConvertDecibelsToScalar:
                case kAudioBooleanControlPropertyValue:
                    return true;
            }
            break;
    }

    return false;
}

static OSStatus VirtualMic_IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable) {
    (void)inDriver;
    (void)inClientProcessID;

    *outIsSettable = false;

    switch (inObjectID) {
        case kObjectID_Device:
            if (inAddress->mSelector == kAudioDevicePropertyNominalSampleRate) {
                *outIsSettable = false;  // サンプルレート固定
            }
            break;

        case kObjectID_Stream_Input:
            if (inAddress->mSelector == kAudioStreamPropertyVirtualFormat ||
                inAddress->mSelector == kAudioStreamPropertyPhysicalFormat) {
                *outIsSettable = false;  // フォーマット固定
            }
            break;

        case kObjectID_Volume_Input:
            if (inAddress->mSelector == kAudioLevelControlPropertyScalarValue ||
                inAddress->mSelector == kAudioLevelControlPropertyDecibelValue) {
                *outIsSettable = true;
            }
            break;

        case kObjectID_Mute_Input:
            if (inAddress->mSelector == kAudioBooleanControlPropertyValue) {
                *outIsSettable = true;
            }
            break;
    }

    return noErr;
}

static OSStatus VirtualMic_GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32* outDataSize) {
    (void)inDriver;
    (void)inClientProcessID;
    (void)inQualifierDataSize;
    (void)inQualifierData;

    *outDataSize = 0;

    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
            *outDataSize = sizeof(AudioClassID);
            break;

        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
            *outDataSize = sizeof(CFStringRef);
            break;

        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyLatency:  // Same as kAudioStreamPropertyLatency
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioControlPropertyScope:
        case kAudioControlPropertyElement:
            *outDataSize = sizeof(UInt32);
            break;

        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyIsHidden:
        case kAudioStreamPropertyIsActive:
        case kAudioBooleanControlPropertyValue:
            *outDataSize = sizeof(UInt32);  // Boolean as UInt32
            break;

        case kAudioDevicePropertyNominalSampleRate:
            *outDataSize = sizeof(Float64);
            break;

        case kAudioDevicePropertyAvailableNominalSampleRates:
            *outDataSize = sizeof(AudioValueRange);  // 1つのサンプルレートのみ
            break;

        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            *outDataSize = sizeof(AudioStreamBasicDescription);
            break;

        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            *outDataSize = sizeof(AudioStreamRangedDescription);
            break;

        case kAudioLevelControlPropertyScalarValue:
            *outDataSize = sizeof(Float32);
            break;

        case kAudioLevelControlPropertyDecibelValue:
            *outDataSize = sizeof(Float32);
            break;

        case kAudioLevelControlPropertyDecibelRange:
            *outDataSize = sizeof(AudioValueRange);
            break;

        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
        case kAudioDevicePropertyStreams:
        case kAudioObjectPropertyControlList:
            // オブジェクトによって異なる
            if (inObjectID == kObjectID_PlugIn) {
                *outDataSize = sizeof(AudioObjectID);  // 1デバイス
            } else if (inObjectID == kObjectID_Device) {
                if (inAddress->mSelector == kAudioDevicePropertyStreams) {
                    *outDataSize = sizeof(AudioObjectID);  // 1ストリーム
                } else if (inAddress->mSelector == kAudioObjectPropertyControlList) {
                    *outDataSize = sizeof(AudioObjectID) * 2;  // Volume + Mute
                } else {
                    *outDataSize = sizeof(AudioObjectID) * 3;  // Stream + Volume + Mute
                }
            }
            break;

        default:
            return kAudioHardwareUnknownPropertyError;
    }

    return noErr;
}

static OSStatus VirtualMic_GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    (void)inDriver;
    (void)inClientProcessID;
    (void)inQualifierDataSize;
    (void)inQualifierData;

    OSStatus result = noErr;

    switch (inObjectID) {
        case kObjectID_PlugIn:
            result = VirtualMic_GetPlugInPropertyData(inAddress, inDataSize, outDataSize, outData);
            break;

        case kObjectID_Device:
            result = VirtualMic_GetDevicePropertyData(inAddress, inDataSize, outDataSize, outData);
            break;

        case kObjectID_Stream_Input:
            result = VirtualMic_GetStreamPropertyData(inAddress, inDataSize, outDataSize, outData);
            break;

        case kObjectID_Volume_Input:
            result = VirtualMic_GetVolumePropertyData(inAddress, inDataSize, outDataSize, outData);
            break;

        case kObjectID_Mute_Input:
            result = VirtualMic_GetMutePropertyData(inAddress, inDataSize, outDataSize, outData);
            break;

        default:
            result = kAudioHardwareBadObjectError;
            break;
    }

    return result;
}

static OSStatus VirtualMic_SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, const void* inData) {
    (void)inDriver;
    (void)inClientProcessID;
    (void)inQualifierDataSize;
    (void)inQualifierData;
    (void)inDataSize;

    OSStatus result = noErr;

    switch (inObjectID) {
        case kObjectID_Volume_Input:
            if (inAddress->mSelector == kAudioLevelControlPropertyScalarValue) {
                pthread_mutex_lock(&gDriverState.stateMutex);
                gDriverState.inputVolumeScalar = *(Float32*)inData;
                pthread_mutex_unlock(&gDriverState.stateMutex);
            }
            break;

        case kObjectID_Mute_Input:
            if (inAddress->mSelector == kAudioBooleanControlPropertyValue) {
                pthread_mutex_lock(&gDriverState.stateMutex);
                gDriverState.inputMute = (*(UInt32*)inData != 0);
                pthread_mutex_unlock(&gDriverState.stateMutex);
            }
            break;

        default:
            result = kAudioHardwareUnknownPropertyError;
            break;
    }

    return result;
}

#pragma mark - I/O Operations

static OSStatus VirtualMic_StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inClientID;

    LOG_INFO("VirtualMic_StartIO");

    pthread_mutex_lock(&gDriverState.stateMutex);

    if (gDriverState.ioClientCount == 0) {
        gDriverState.anchorHostTime = mach_absolute_time();
        atomic_store(&gDriverState.isIORunning, true);

        // 共有メモリを再接続（アプリが起動している場合）
        if (gDriverState.sharedBuffer == NULL) {
            SharedMemory_Open(&gDriverState);
        }
    }

    gDriverState.ioClientCount++;

    pthread_mutex_unlock(&gDriverState.stateMutex);

    return noErr;
}

static OSStatus VirtualMic_StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inClientID;

    LOG_INFO("VirtualMic_StopIO");

    pthread_mutex_lock(&gDriverState.stateMutex);

    if (gDriverState.ioClientCount > 0) {
        gDriverState.ioClientCount--;

        if (gDriverState.ioClientCount == 0) {
            atomic_store(&gDriverState.isIORunning, false);
        }
    }

    pthread_mutex_unlock(&gDriverState.stateMutex);

    return noErr;
}

static OSStatus VirtualMic_GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inClientID;

    UInt64 currentHostTime = mach_absolute_time();
    UInt64 elapsedHostTime = currentHostTime - gDriverState.anchorHostTime;
    Float64 elapsedSampleTime = elapsedHostTime / gDriverState.hostTicksPerFrame;

    // ゼロタイムスタンプを計算（周期に丸める）
    UInt64 samplePeriod = (UInt64)kFrameSize;
    UInt64 sampleTimePeriods = (UInt64)elapsedSampleTime / samplePeriod;

    *outSampleTime = (Float64)(sampleTimePeriods * samplePeriod);
    *outHostTime = gDriverState.anchorHostTime + (UInt64)(*outSampleTime * gDriverState.hostTicksPerFrame);
    *outSeed = 1;

    return noErr;
}

static OSStatus VirtualMic_WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outIsInput) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inClientID;

    *outWillDo = false;
    *outIsInput = false;

    switch (inOperationID) {
        case kAudioServerPlugInIOOperationReadInput:
            *outWillDo = true;
            *outIsInput = true;
            break;
    }

    return noErr;
}

static OSStatus VirtualMic_BeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inClientID;
    (void)inOperationID;
    (void)inIOBufferFrameSize;
    (void)inIOCycleInfo;

    return noErr;
}

static OSStatus VirtualMic_DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inStreamObjectID;
    (void)inClientID;
    (void)inIOCycleInfo;
    (void)ioSecondaryBuffer;

    if (inOperationID != kAudioServerPlugInIOOperationReadInput) {
        return noErr;
    }

    Float32* outputBuffer = (Float32*)ioMainBuffer;
    VCSharedBuffer* shared = gDriverState.sharedBuffer;

    // 共有メモリがない、または非アクティブの場合は無音
    if (shared == NULL ||
        shared->magic != kSharedMemoryMagic ||
        atomic_load(&shared->state) != 1) {
        memset(outputBuffer, 0, inIOBufferFrameSize * sizeof(Float32));
        return noErr;
    }

    // リングバッファから読み取り
    uint32_t readIdx = atomic_load(&shared->readIndex);
    uint32_t writeIdx = atomic_load(&shared->writeIndex);
    uint32_t bufferSize = shared->bufferFrames * shared->frameSize;

    uint32_t available = (writeIdx >= readIdx) ?
        (writeIdx - readIdx) :
        (bufferSize - readIdx + writeIdx);

    if (available < inIOBufferFrameSize) {
        // アンダーラン - 無音で補完
        memset(outputBuffer, 0, inIOBufferFrameSize * sizeof(Float32));
        return noErr;
    }

    // 読み取り位置
    uint32_t startPos = readIdx % bufferSize;

    if (startPos + inIOBufferFrameSize <= bufferSize) {
        // 連続コピー
        memcpy(outputBuffer, &shared->samples[startPos], inIOBufferFrameSize * sizeof(Float32));
    } else {
        // 2分割コピー（wrap-around）
        uint32_t firstPart = bufferSize - startPos;
        memcpy(outputBuffer, &shared->samples[startPos], firstPart * sizeof(Float32));
        memcpy(outputBuffer + firstPart, shared->samples, (inIOBufferFrameSize - firstPart) * sizeof(Float32));
    }

    // 読み取りインデックス更新
    atomic_store(&shared->readIndex, readIdx + inIOBufferFrameSize);

    // ミュート/ボリューム適用
    pthread_mutex_lock(&gDriverState.stateMutex);
    bool mute = gDriverState.inputMute;
    Float32 volume = gDriverState.inputVolumeScalar;
    pthread_mutex_unlock(&gDriverState.stateMutex);

    if (mute) {
        memset(outputBuffer, 0, inIOBufferFrameSize * sizeof(Float32));
    } else if (volume != 1.0f) {
        for (UInt32 i = 0; i < inIOBufferFrameSize; i++) {
            outputBuffer[i] *= volume;
        }
    }

    return noErr;
}

static OSStatus VirtualMic_EndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    (void)inDriver;
    (void)inDeviceObjectID;
    (void)inClientID;
    (void)inOperationID;
    (void)inIOBufferFrameSize;
    (void)inIOCycleInfo;

    return noErr;
}

#pragma mark - Shared Memory

static OSStatus SharedMemory_Open(VirtualMicDriverState* state) {
    int fd = shm_open(kSharedMemoryName, O_RDONLY, 0644);
    if (fd < 0) {
        LOG_DEBUG("Shared memory not available yet");
        return kAudioHardwareNotReadyError;
    }

    // サイズ計算
    size_t headerSize = 64;  // アライメント済み
    size_t bufferSize = kFrameSize * kBufferFrameCount * sizeof(float);
    size_t totalSize = headerSize + bufferSize;

    void* ptr = mmap(NULL, totalSize, PROT_READ, MAP_SHARED, fd, 0);
    if (ptr == MAP_FAILED) {
        LOG_ERROR("Failed to mmap shared memory");
        close(fd);
        return kAudioHardwareUnspecifiedError;
    }

    state->sharedBuffer = (VCSharedBuffer*)ptr;
    state->sharedMemoryFD = fd;
    state->sharedMemorySize = totalSize;

    // 検証
    if (state->sharedBuffer->magic != kSharedMemoryMagic) {
        LOG_ERROR("Invalid shared memory magic");
        SharedMemory_Close(state);
        return kAudioHardwareUnspecifiedError;
    }

    LOG_INFO("Shared memory opened successfully");
    return noErr;
}

static void SharedMemory_Close(VirtualMicDriverState* state) {
    if (state->sharedBuffer != NULL) {
        munmap(state->sharedBuffer, state->sharedMemorySize);
        state->sharedBuffer = NULL;
    }

    if (state->sharedMemoryFD >= 0) {
        close(state->sharedMemoryFD);
        state->sharedMemoryFD = -1;
    }
}
