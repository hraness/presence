import CoreAudio
import CoreMediaIO

/// Whether any audio input device is running in any process.
///
/// Reads `kAudioDevicePropertyDeviceIsRunningSomewhere`, which needs no microphone
/// permission: it says a device is open, not what it hears. Nil when CoreAudio fails.
func microphoneInUse() -> Bool? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    if count == 0 { return false }
    var devices = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return nil }
    for device in devices.prefix(Int(size) / MemoryLayout<AudioObjectID>.size) {
        var streams = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamBytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamBytes) == noErr, streamBytes > 0 else { continue }
        var running = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var valueSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &running, 0, nil, &valueSize, &value) == noErr, value != 0 {
            return true
        }
    }
    return false
}

/// Whether any camera is running in any process.
///
/// Reads `kCMIODevicePropertyDeviceIsRunningSomewhere`, which needs no camera permission.
/// Nil when CoreMediaIO fails.
func cameraInUse() -> Bool? {
    var address = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    let system = CMIOObjectID(kCMIOObjectSystemObject)
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0 else { return nil }
    let count = Int(size) / MemoryLayout<CMIOObjectID>.size
    if count == 0 { return false }
    var devices = [CMIOObjectID](repeating: 0, count: count)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return nil }
    for device in devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size) {
        var running = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var value: UInt32 = 0
        var valueUsed: UInt32 = 0
        if CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &valueUsed, &value) == 0, value != 0 {
            return true
        }
    }
    return false
}
