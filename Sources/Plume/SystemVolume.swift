import CoreAudio
import Foundation

/// Coupe le son de la sortie par défaut le temps d'une dictée (musique, vidéo en cours), puis
/// le rétablit. On passe par le réglage « muet » de la sortie, pas par le volume : rien n'est
/// à mémoriser, et un son coupé par l'utilisateur lui-même le reste.
enum SystemVolume {
    private static var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// - Returns: `true` si l'état a changé (faux si la sortie était déjà muette, ou ne sait pas se couper).
    @discardableResult
    static func mute(_ on: Bool) -> Bool {
        guard let device = defaultOutput(), AudioObjectHasProperty(device, &address) else { return false }
        var current: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr else { return false }
        if on, current != 0 { return false }
        var value: UInt32 = on ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    private static func defaultOutput() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
