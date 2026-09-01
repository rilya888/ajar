// Разведка датчика угла крышки. Запуск: swift lidangle.swift [сколько_отсчётов]
// Печатает время, угол, число экранов и сырой отчёт. Не падает при ошибке чтения
// и при исчезновении устройства — это и есть предмет измерения в Block 01.
import Foundation
import IOKit.hid
import AppKit

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDDeviceUsagePageKey: 0x20,   // Sensors
    kIOHIDDeviceUsageKey: 0x8A,       // Lid angle
] as CFDictionary)

guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
    print("IOHIDManagerOpen failed"); exit(1)
}

func findDevice() -> IOHIDDevice? {
    (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first
}

let clock = DateFormatter()
clock.dateFormat = "HH:mm:ss.SSS"

var device = findDevice()
if device == nil { print("датчик угла не найден") }

let samples = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? Int.max
for _ in 0..<samples {
    let t = clock.string(from: Date())
    let screens = NSScreen.screens.count

    if device == nil { device = findDevice() }
    guard let d = device else {
        print("\(t)  DEVICE ABSENT      screens=\(screens)")
        fflush(stdout); usleep(100_000); continue
    }

    var buf = [UInt8](repeating: 0, count: 8)
    var len = buf.count
    let r = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, 1, &buf, &len)
    if r == kIOReturnSuccess {
        // ponytail: угол = LE16 из байтов 1-2; сырые байты рядом, чтобы формат был виден глазами
        let angle = Int(buf[1]) | Int(buf[2]) << 8
        let raw = buf[0..<len].map { String(format: "%02x", $0) }.joined(separator: " ")
        print(String(format: "%@  %4d°  screens=%d  raw: %@", t, angle, screens, raw))
    } else {
        print(String(format: "%@  READ ERROR 0x%08x  screens=%d", t, r, screens))
        device = nil   // заставить перематчить устройство на следующем тике
    }
    fflush(stdout)
    usleep(100_000)   // 10 Гц
}
