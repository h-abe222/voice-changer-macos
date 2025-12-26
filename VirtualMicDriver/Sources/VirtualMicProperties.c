//
//  VirtualMicProperties.c
//  VoiceChanger Virtual Mic Driver
//
//  Property getter implementations
//

#include "VirtualMicDriver.h"

#pragma mark - PlugIn Properties

OSStatus VirtualMic_GetPlugInPropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    OSStatus result = noErr;

    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioObjectClassID;
            }
            break;

        case kAudioObjectPropertyClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioPlugInClassID;
            }
            break;

        case kAudioObjectPropertyOwner:
            *outDataSize = sizeof(AudioObjectID);
            if (inDataSize >= sizeof(AudioObjectID)) {
                *(AudioObjectID*)outData = kAudioObjectUnknown;
            }
            break;

        case kAudioObjectPropertyManufacturer:
            *outDataSize = sizeof(CFStringRef);
            if (inDataSize >= sizeof(CFStringRef)) {
                *(CFStringRef*)outData = CFSTR("VoiceChanger");
            }
            break;

        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
            *outDataSize = sizeof(AudioObjectID);
            if (inDataSize >= sizeof(AudioObjectID)) {
                *(AudioObjectID*)outData = kObjectID_Device;
            }
            break;

        case kAudioPlugInPropertyTranslateUIDToDevice:
            *outDataSize = sizeof(AudioObjectID);
            if (inDataSize >= sizeof(AudioObjectID)) {
                *(AudioObjectID*)outData = kObjectID_Device;
            }
            break;

        case kAudioPlugInPropertyResourceBundle:
            *outDataSize = sizeof(CFStringRef);
            if (inDataSize >= sizeof(CFStringRef)) {
                *(CFStringRef*)outData = CFSTR("");
            }
            break;

        default:
            result = kAudioHardwareUnknownPropertyError;
            break;
    }

    return result;
}

#pragma mark - Device Properties

OSStatus VirtualMic_GetDevicePropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    OSStatus result = noErr;

    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioObjectClassID;
            }
            break;

        case kAudioObjectPropertyClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioDeviceClassID;
            }
            break;

        case kAudioObjectPropertyOwner:
            *outDataSize = sizeof(AudioObjectID);
            if (inDataSize >= sizeof(AudioObjectID)) {
                *(AudioObjectID*)outData = kObjectID_PlugIn;
            }
            break;

        case kAudioObjectPropertyName:
            *outDataSize = sizeof(CFStringRef);
            if (inDataSize >= sizeof(CFStringRef)) {
                *(CFStringRef*)outData = CFSTR("VoiceChanger Virtual Mic");
            }
            break;

        case kAudioObjectPropertyManufacturer:
            *outDataSize = sizeof(CFStringRef);
            if (inDataSize >= sizeof(CFStringRef)) {
                *(CFStringRef*)outData = CFSTR("VoiceChanger");
            }
            break;

        case kAudioDevicePropertyDeviceUID:
            *outDataSize = sizeof(CFStringRef);
            if (inDataSize >= sizeof(CFStringRef)) {
                *(CFStringRef*)outData = CFSTR("com.voicechanger.virtualmicdriver");
            }
            break;

        case kAudioDevicePropertyModelUID:
            *outDataSize = sizeof(CFStringRef);
            if (inDataSize >= sizeof(CFStringRef)) {
                *(CFStringRef*)outData = CFSTR("com.voicechanger.virtualmicdriver.model");
            }
            break;

        case kAudioDevicePropertyTransportType:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = kAudioDeviceTransportTypeVirtual;
            }
            break;

        case kAudioDevicePropertyDeviceIsAlive:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = 1;
            }
            break;

        case kAudioDevicePropertyDeviceIsRunning:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                extern VirtualMicDriverState gDriverState;
                *(UInt32*)outData = atomic_load(&gDriverState.isIORunning) ? 1 : 0;
            }
            break;

        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                // 入力デバイスのみ（スコープによる）
                *(UInt32*)outData = (inAddress->mScope == kAudioObjectPropertyScopeInput) ? 1 : 0;
            }
            break;

        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = 0;  // システムデバイスにはしない
            }
            break;

        case kAudioDevicePropertyLatency:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = 0;  // ゼロレイテンシ
            }
            break;

        case kAudioDevicePropertyStreams:
            if (inAddress->mScope == kAudioObjectPropertyScopeInput) {
                *outDataSize = sizeof(AudioObjectID);
                if (inDataSize >= sizeof(AudioObjectID)) {
                    *(AudioObjectID*)outData = kObjectID_Stream_Input;
                }
            } else {
                *outDataSize = 0;
            }
            break;

        case kAudioObjectPropertyControlList:
            *outDataSize = sizeof(AudioObjectID) * 2;
            if (inDataSize >= sizeof(AudioObjectID) * 2) {
                AudioObjectID* ids = (AudioObjectID*)outData;
                ids[0] = kObjectID_Volume_Input;
                ids[1] = kObjectID_Mute_Input;
            }
            break;

        case kAudioObjectPropertyOwnedObjects:
            *outDataSize = sizeof(AudioObjectID) * 3;
            if (inDataSize >= sizeof(AudioObjectID) * 3) {
                AudioObjectID* ids = (AudioObjectID*)outData;
                ids[0] = kObjectID_Stream_Input;
                ids[1] = kObjectID_Volume_Input;
                ids[2] = kObjectID_Mute_Input;
            }
            break;

        case kAudioDevicePropertyNominalSampleRate:
            *outDataSize = sizeof(Float64);
            if (inDataSize >= sizeof(Float64)) {
                *(Float64*)outData = kSampleRate;
            }
            break;

        case kAudioDevicePropertyAvailableNominalSampleRates:
            *outDataSize = sizeof(AudioValueRange);
            if (inDataSize >= sizeof(AudioValueRange)) {
                AudioValueRange* range = (AudioValueRange*)outData;
                range->mMinimum = kSampleRate;
                range->mMaximum = kSampleRate;
            }
            break;

        case kAudioDevicePropertyIsHidden:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = 0;  // 表示する
            }
            break;

        case kAudioDevicePropertyZeroTimeStampPeriod:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = kFrameSize;
            }
            break;

        case kAudioDevicePropertyIcon:
            *outDataSize = sizeof(CFURLRef);
            if (inDataSize >= sizeof(CFURLRef)) {
                *(CFURLRef*)outData = NULL;  // アイコンなし
            }
            break;

        default:
            result = kAudioHardwareUnknownPropertyError;
            break;
    }

    return result;
}

#pragma mark - Stream Properties

OSStatus VirtualMic_GetStreamPropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    OSStatus result = noErr;

    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioObjectClassID;
            }
            break;

        case kAudioObjectPropertyClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioStreamClassID;
            }
            break;

        case kAudioObjectPropertyOwner:
            *outDataSize = sizeof(AudioObjectID);
            if (inDataSize >= sizeof(AudioObjectID)) {
                *(AudioObjectID*)outData = kObjectID_Device;
            }
            break;

        case kAudioObjectPropertyName:
            *outDataSize = sizeof(CFStringRef);
            if (inDataSize >= sizeof(CFStringRef)) {
                *(CFStringRef*)outData = CFSTR("VoiceChanger Input");
            }
            break;

        case kAudioStreamPropertyIsActive:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = 1;
            }
            break;

        case kAudioStreamPropertyDirection:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = 1;  // 1 = input
            }
            break;

        case kAudioStreamPropertyTerminalType:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = kAudioStreamTerminalTypeMicrophone;
            }
            break;

        case kAudioStreamPropertyStartingChannel:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = 1;
            }
            break;

        case kAudioStreamPropertyLatency:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                *(UInt32*)outData = 0;
            }
            break;

        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            *outDataSize = sizeof(AudioStreamBasicDescription);
            if (inDataSize >= sizeof(AudioStreamBasicDescription)) {
                AudioStreamBasicDescription* desc = (AudioStreamBasicDescription*)outData;
                desc->mSampleRate = kSampleRate;
                desc->mFormatID = kAudioFormatLinearPCM;
                desc->mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
                desc->mBytesPerPacket = sizeof(Float32) * kChannelsPerFrame;
                desc->mFramesPerPacket = 1;
                desc->mBytesPerFrame = sizeof(Float32) * kChannelsPerFrame;
                desc->mChannelsPerFrame = kChannelsPerFrame;
                desc->mBitsPerChannel = kBitsPerChannel;
            }
            break;

        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            *outDataSize = sizeof(AudioStreamRangedDescription);
            if (inDataSize >= sizeof(AudioStreamRangedDescription)) {
                AudioStreamRangedDescription* desc = (AudioStreamRangedDescription*)outData;
                desc->mFormat.mSampleRate = kSampleRate;
                desc->mFormat.mFormatID = kAudioFormatLinearPCM;
                desc->mFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
                desc->mFormat.mBytesPerPacket = sizeof(Float32) * kChannelsPerFrame;
                desc->mFormat.mFramesPerPacket = 1;
                desc->mFormat.mBytesPerFrame = sizeof(Float32) * kChannelsPerFrame;
                desc->mFormat.mChannelsPerFrame = kChannelsPerFrame;
                desc->mFormat.mBitsPerChannel = kBitsPerChannel;
                desc->mSampleRateRange.mMinimum = kSampleRate;
                desc->mSampleRateRange.mMaximum = kSampleRate;
            }
            break;

        default:
            result = kAudioHardwareUnknownPropertyError;
            break;
    }

    return result;
}

#pragma mark - Volume Control Properties

OSStatus VirtualMic_GetVolumePropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    OSStatus result = noErr;
    extern VirtualMicDriverState gDriverState;

    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioControlClassID;
            }
            break;

        case kAudioObjectPropertyClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioVolumeControlClassID;
            }
            break;

        case kAudioObjectPropertyOwner:
            *outDataSize = sizeof(AudioObjectID);
            if (inDataSize >= sizeof(AudioObjectID)) {
                *(AudioObjectID*)outData = kObjectID_Device;
            }
            break;

        case kAudioObjectPropertyOwnedObjects:
            *outDataSize = 0;
            break;

        case kAudioControlPropertyScope:
            *outDataSize = sizeof(AudioObjectPropertyScope);
            if (inDataSize >= sizeof(AudioObjectPropertyScope)) {
                *(AudioObjectPropertyScope*)outData = kAudioObjectPropertyScopeInput;
            }
            break;

        case kAudioControlPropertyElement:
            *outDataSize = sizeof(AudioObjectPropertyElement);
            if (inDataSize >= sizeof(AudioObjectPropertyElement)) {
                *(AudioObjectPropertyElement*)outData = kAudioObjectPropertyElementMain;
            }
            break;

        case kAudioLevelControlPropertyScalarValue:
            *outDataSize = sizeof(Float32);
            if (inDataSize >= sizeof(Float32)) {
                pthread_mutex_lock(&gDriverState.stateMutex);
                *(Float32*)outData = gDriverState.inputVolumeScalar;
                pthread_mutex_unlock(&gDriverState.stateMutex);
            }
            break;

        case kAudioLevelControlPropertyDecibelValue:
            *outDataSize = sizeof(Float32);
            if (inDataSize >= sizeof(Float32)) {
                pthread_mutex_lock(&gDriverState.stateMutex);
                Float32 scalar = gDriverState.inputVolumeScalar;
                pthread_mutex_unlock(&gDriverState.stateMutex);
                // スカラー値をdBに変換 (0-1 -> -96 to 0 dB)
                *(Float32*)outData = (scalar > 0) ? (20.0f * log10f(scalar)) : -96.0f;
            }
            break;

        case kAudioLevelControlPropertyDecibelRange:
            *outDataSize = sizeof(AudioValueRange);
            if (inDataSize >= sizeof(AudioValueRange)) {
                AudioValueRange* range = (AudioValueRange*)outData;
                range->mMinimum = -96.0;
                range->mMaximum = 0.0;
            }
            break;

        case kAudioLevelControlPropertyConvertScalarToDecibels:
        case kAudioLevelControlPropertyConvertDecibelsToScalar:
            // 変換は呼び出し側で行う
            result = kAudioHardwareUnknownPropertyError;
            break;

        default:
            result = kAudioHardwareUnknownPropertyError;
            break;
    }

    return result;
}

#pragma mark - Mute Control Properties

OSStatus VirtualMic_GetMutePropertyData(const AudioObjectPropertyAddress* inAddress, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    OSStatus result = noErr;
    extern VirtualMicDriverState gDriverState;

    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioControlClassID;
            }
            break;

        case kAudioObjectPropertyClass:
            *outDataSize = sizeof(AudioClassID);
            if (inDataSize >= sizeof(AudioClassID)) {
                *(AudioClassID*)outData = kAudioMuteControlClassID;
            }
            break;

        case kAudioObjectPropertyOwner:
            *outDataSize = sizeof(AudioObjectID);
            if (inDataSize >= sizeof(AudioObjectID)) {
                *(AudioObjectID*)outData = kObjectID_Device;
            }
            break;

        case kAudioObjectPropertyOwnedObjects:
            *outDataSize = 0;
            break;

        case kAudioControlPropertyScope:
            *outDataSize = sizeof(AudioObjectPropertyScope);
            if (inDataSize >= sizeof(AudioObjectPropertyScope)) {
                *(AudioObjectPropertyScope*)outData = kAudioObjectPropertyScopeInput;
            }
            break;

        case kAudioControlPropertyElement:
            *outDataSize = sizeof(AudioObjectPropertyElement);
            if (inDataSize >= sizeof(AudioObjectPropertyElement)) {
                *(AudioObjectPropertyElement*)outData = kAudioObjectPropertyElementMain;
            }
            break;

        case kAudioBooleanControlPropertyValue:
            *outDataSize = sizeof(UInt32);
            if (inDataSize >= sizeof(UInt32)) {
                pthread_mutex_lock(&gDriverState.stateMutex);
                *(UInt32*)outData = gDriverState.inputMute ? 1 : 0;
                pthread_mutex_unlock(&gDriverState.stateMutex);
            }
            break;

        default:
            result = kAudioHardwareUnknownPropertyError;
            break;
    }

    return result;
}
