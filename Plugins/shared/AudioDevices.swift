import Foundation
import CoreAudio

/// Minimal CoreAudio helpers shared by plugins (default output/input device lookup and switching).
enum AudioDevices {
    struct Device: Equatable { let id: AudioDeviceID; let name: String }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func hasStreams(_ id: AudioDeviceID, output: Bool) -> Bool {
        var a = address(kAudioDevicePropertyStreams, scope: output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0
    }

    private static func name(_ id: AudioDeviceID) -> String {
        var a = address(kAudioObjectPropertyName)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &cf) == noErr, let s = cf?.takeRetainedValue() else { return "Device \(id)" }
        return s as String
    }

    private static func isVirtual(_ id: AudioDeviceID) -> Bool {
        var a = address(kAudioDevicePropertyTransportType)
        var t: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &t) == noErr else { return false }
        return t == kAudioDeviceTransportTypeVirtual || t == kAudioDeviceTransportTypeAggregate
    }

    /// Real (non-virtual, non-aggregate) devices that can play / record, in system order.
    static func devices(output: Bool) -> [Device] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { hasStreams($0, output: output) && !isVirtual($0) }.map { Device(id: $0, name: name($0)) }
    }

    static func defaultDevice(output: Bool) -> AudioDeviceID? {
        var a = address(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr ? id : nil
    }

    @discardableResult
    static func setDefault(_ id: AudioDeviceID, output: Bool) -> Bool {
        var a = address(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        var dev = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &dev) == noErr
    }

    /// The device after `current` in `list`, wrapping around; nil when there's nothing to switch to.
    static func next(after current: AudioDeviceID?, in list: [Device]) -> Device? {
        guard list.count > 1 else { return nil }
        guard let c = current, let i = list.firstIndex(where: { $0.id == c }) else { return list.first }
        return list[(i + 1) % list.count]
    }

    /// Calls `handler` whenever the default output (or input) device changes. Returns a token for `stopObserving`.
    static func observeDefault(output: Bool, queue: DispatchQueue = .main, _ handler: @escaping () -> Void) -> (AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock) {
        var a = address(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, block)
        return (a, block)
    }

    static func stopObserving(_ token: (AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock), queue: DispatchQueue = .main) {
        var a = token.0
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, token.1)
    }

    static func nameOf(_ id: AudioDeviceID) -> String { name(id) }
}
