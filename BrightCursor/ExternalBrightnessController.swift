// ExternalBrightnessController.swift
// Controls external display brightness on Apple Silicon Macs using the DDC/CI
// protocol over IOAVService (the I2C path for DisplayPort/USB-C connections).
//
// Algorithm (ported from MonitorControl's Arm64DDC.swift):
//   1. Walk the IOService plane from root.
//   2. For each AppleCLCD2 / IOMobileFramebufferShim node, read EDID UUID,
//      IODisplayLocation, product name from its DisplayAttributes property.
//   3. For each child DCPAVServiceProxy node, read "Location".
//      Only nodes with Location == "External" are valid DDC targets.
//   4. Match each CGDirectDisplayID to a service using a score algorithm that
//      compares EDID UUID segments, IODisplayLocation, product name, serial.
//   5. Send DDC VCP 0x10 (brightness) write via IOAVServiceWriteI2C.
//
// DDC packet format (write):
//   Chip address : 0x37  (7-bit, works for DisplayPort)
//   Data address : 0x51
//   Payload      : [0x80|(len+1), len, vcpCode, valueHigh, valueLow, checksum]
//   Checksum     : XOR of (chipAddr<<1 ^ dataAddr ^ all payload bytes except last)
//
// Brightness scale: DDC VCP 0x10 uses 0–100.

import Foundation
import IOKit
import CoreGraphics
import OSLog

// MARK: - Constants

private let kDDCChipAddress: UInt32 = 0x37   // 7-bit I2C address for DDC
private let kDDCDataAddress: UInt32 = 0x51
private let kVCPBrightness: UInt8 = 0x10
private let kDDCMaxBrightness: Int   = 100
private let kDDCBrightnessStep: Int  = 6      // ~1/16 of 100
private let kWriteSleepUs: UInt32 = 10_000  // 10 ms before write
private let kReadSleepUs: UInt32 = 50_000  // 50 ms before read
private let kRetrySleepUs: UInt32 = 20_000  // 20 ms between retries
private let kWriteCycles: Int    = 2
private let kRetryAttempts: Int = 4

// MARK: - Supporting types

private struct IORegService {
    var edidUUID: String = ""
    var productName: String = ""
    var serialNumber: Int64 = 0
    var ioDisplayLocation: String = ""
    var location: String = ""
    var serviceLocation: Int = 0
    var avService: IOAVService?
}

private struct DisplayServiceMatch {
    var displayID: CGDirectDisplayID
    var avService: IOAVService?
    var serviceLocation: Int
    var score: Int
}

// MARK: - Controller

final class ExternalBrightnessController: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.bjw.app", category: "ExternalDDC")

    // displayID → (avService, serviceLocation)
    private var serviceMap: [CGDirectDisplayID: IOAVService] = [:]
    // displayID → last known DDC brightness (0–100)
    private var brightnessCache: [CGDirectDisplayID: Int] = [:]
    private let lock = NSLock()

    // MARK: - Public

    /// Walk IORegistry and build the displayID ↔ IOAVService mapping.
    /// Must be called before adjustBrightness. Re-call on display config change.
    func buildServiceMap() {
        let services = getIORegServices()
        var onlineIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &onlineIDs, &count) == .success else { return }

        let displayIDs = Array(onlineIDs.prefix(Int(count))).filter {
            $0 != 0 && CGDisplayIsBuiltin($0) == 0
        }

        var newMap: [CGDirectDisplayID: IOAVService] = [:]
        var matched = Set<Int>()    // serviceLocation already assigned
        var matchedDisplays = Set<CGDirectDisplayID>()

        // Score every (displayID, service) pair, take highest score first
        var candidates: [DisplayServiceMatch] = []
        for displayID in displayIDs {
            for service in services {
                let score = matchScore(displayID: displayID, service: service)
                candidates.append(DisplayServiceMatch(
                    displayID: displayID,
                    avService: service.avService,
                    serviceLocation: service.serviceLocation,
                    score: score))
            }
        }
        candidates.sort { $0.score > $1.score }

        for candidate in candidates {
            guard candidate.score > 0 else { continue }
            guard !matchedDisplays.contains(candidate.displayID),
                  !matched.contains(candidate.serviceLocation),
                  let svc = candidate.avService else { continue }
            newMap[candidate.displayID] = svc
            matchedDisplays.insert(candidate.displayID)
            matched.insert(candidate.serviceLocation)
            let score = candidate.score
            let loc = candidate.serviceLocation
            logger.info("Matched display \(candidate.displayID) → service location \(loc) (score \(score))")
        }

        lock.lock()
        serviceMap = newMap
        lock.unlock()
        logger.info("Service map built: \(newMap.count) external display(s) mapped.")
    }

    @discardableResult
    func adjustBrightness(displayID: CGDirectDisplayID, increase: Bool) -> Int? {
        lock.lock()
        let service = serviceMap[displayID]
        lock.unlock()

        guard let avService = service else {
            logger.error("No IOAVService for display \(displayID). Rebuilding map…")
            buildServiceMap()
            return nil
        }

        // Read current brightness from DDC, or use cache if read fails
        let current: Int
        if let cached = brightnessCache[displayID] {
            current = cached
        } else {
            current = readBrightness(service: avService) ?? 50
        }

        let delta = increase ? kDDCBrightnessStep : -kDDCBrightnessStep
        let newValue = min(kDDCMaxBrightness, max(0, current + delta))

        let success = writeBrightness(service: avService, value: UInt16(newValue))
        if success {
            brightnessCache[displayID] = newValue
            logger.info("External brightness set to \(newValue) on display \(displayID)")
            return newValue
        } else {
            logger.error("DDC write failed for display \(displayID)")
            return nil
        }
    }

    // MARK: - DDC Read

    private func readBrightness(service: IOAVService) -> Int? {
        // DDC Get VCP Feature request: send [vcpCode], receive 11-byte reply
        var send: [UInt8] = [kVCPBrightness]
        var reply = [UInt8](repeating: 0, count: 11)

        guard performDDC(service: service, send: &send, reply: &reply) else {
            return nil
        }

        // Reply layout: [_, _, _, _, _, _, maxHi, maxLo, curHi, curLo, checksum]
        let current = Int(reply[8]) * 256 + Int(reply[9])
        return current
    }

    // MARK: - DDC Write

    private func writeBrightness(service: IOAVService, value: UInt16) -> Bool {
        var send: [UInt8] = [kVCPBrightness, UInt8(value >> 8), UInt8(value & 0xFF)]
        var reply: [UInt8] = []
        return performDDC(service: service, send: &send, reply: &reply)
    }

    // MARK: - Core DDC Communication

    private func performDDC(service: IOAVService,
                            send: inout [UInt8],
                            reply: inout [UInt8]) -> Bool {
        // Build DDC packet:
        //  [0x80|(payloadLen+1), payloadLen, ...payload..., checksum]
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        // Checksum seed depends on whether this is a read (1 byte send) or write
        let checksumSeed: UInt8 = send.count == 1
            ? UInt8(kDDCChipAddress) << 1
            : (UInt8(kDDCChipAddress) << 1) ^ UInt8(kDDCDataAddress)
        packet[packet.count - 1] = checksum(seed: checksumSeed, data: &packet, range: 0..<(packet.count - 1))

        var success = false

        for _ in 0..<(kRetryAttempts + 1) {
            for _ in 0..<kWriteCycles {
                usleep(kWriteSleepUs)
                let result = IOAVServiceWriteI2C(
                    service,
                    kDDCChipAddress,
                    kDDCDataAddress,
                    &packet,
                    UInt32(packet.count))
                success = (result == kIOReturnSuccess)
            }

            if !reply.isEmpty {
                usleep(kReadSleepUs)
                let readResult = IOAVServiceReadI2C(
                    service,
                    kDDCChipAddress,
                    0,
                    &reply,
                    UInt32(reply.count))
                if readResult == kIOReturnSuccess {
                    // Verify reply checksum
                    let expected = checksum(seed: 0x50, data: &reply, range: 0..<(reply.count - 1))
                    success = (expected == reply[reply.count - 1])
                } else {
                    success = false
                }
            }

            if success { return true }
            usleep(kRetrySleepUs)
        }
        return false
    }

    private func checksum(seed: UInt8, data: inout [UInt8], range: Range<Int>) -> UInt8 {
        var result = seed
        for i in range { result ^= data[i] }
        return result
    }

    // MARK: - IORegistry Walk

    /// Walk the IOService plane and collect all DCPAVServiceProxy entries that
    /// have Location == "External", along with their parent framebuffer metadata.
    private func getIORegServices() -> [IORegService] {
        var results: [IORegService] = []

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator) == KERN_SUCCESS else { return results }
        defer { IOObjectRelease(iterator) }

        var serviceLocation = 0
        var currentFramebufferService = IORegService()

        let framebufferKeys = ["AppleCLCD2", "IOMobileFramebufferShim"]
        let dcpKey = "DCPAVServiceProxy"

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }

            var nameBuf = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
            guard IORegistryEntryGetName(entry, &nameBuf) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuf)

            if framebufferKeys.contains(where: { name.contains($0) }) {
                serviceLocation += 1
                currentFramebufferService = IORegService()
                currentFramebufferService.serviceLocation = serviceLocation
                readFramebufferProperties(entry: entry, into: &currentFramebufferService)

            } else if name.contains(dcpKey) {
                var svc = currentFramebufferService
                if let location = ioRegString(entry: entry, key: "Location"), location == "External" {
                    svc.location = location
                    svc.avService = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
                    results.append(svc)
                    logger.debug("Found external IOAVService at location \(svc.serviceLocation) (\(svc.productName))")
                }
            }
        }
        return results
    }

    private func readFramebufferProperties(entry: io_service_t, into svc: inout IORegService) {
        // EDID UUID
        if let uuid = ioRegString(entry: entry, key: "EDID UUID") {
            svc.edidUUID = uuid
        }
        // IODisplayLocation path
        var path = [CChar](repeating: 0, count: MemoryLayout<io_string_t>.size)
        IORegistryEntryGetPath(entry, kIOServicePlane, &path)
        svc.ioDisplayLocation = String(cString: path)

        // DisplayAttributes → ProductAttributes
        if let unmanaged = IORegistryEntryCreateCFProperty(
            entry,
            "DisplayAttributes" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)) {
            let attrs = unmanaged.takeRetainedValue() as? NSDictionary
            if let prod = attrs?["ProductAttributes"] as? NSDictionary {
                svc.productName   = prod["ProductName"] as? String ?? ""
                svc.serialNumber  = prod["SerialNumber"] as? Int64 ?? 0
            }
        }
    }

    private func ioRegString(entry: io_service_t, key: String) -> String? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0) else { return nil }
        return unmanaged.takeRetainedValue() as? String
    }

    // MARK: - Match Scoring

    /// Score how well a CGDirectDisplayID matches an IORegService.
    /// Higher = better. Uses EDID UUID segments + IODisplayLocation + product name + serial.
    private func matchScore(displayID: CGDirectDisplayID, service: IORegService) -> Int {
        var score = 0
        guard let dict = CoreDisplay_DisplayCreateInfoDictionary(displayID)?
            .takeRetainedValue() as NSDictionary? else { return 0 }

        // IODisplayLocation match — strongest signal (10 pts)
        if !service.ioDisplayLocation.isEmpty,
           let kLoc = dict[kIODisplayLocationKey] as? String,
           service.ioDisplayLocation == kLoc {
            score += 10
        }

        // EDID UUID — compare up to 4 fields (vendor, product, mfg date, image size)
        if !service.edidUUID.isEmpty {
            let uuid = service.edidUUID
            struct Segment { let offset: Int; let key: String }
            let segments: [Segment] = [
                Segment(offset: 0, key: edidVendorSegment(dict: dict)),
                Segment(offset: 4, key: edidProductSegment(dict: dict)),
                Segment(offset: 19, key: edidMfgDateSegment(dict: dict)),
                Segment(offset: 30, key: edidSizeSegment(dict: dict)),
            ]
            for seg in segments {
                guard !seg.key.isEmpty, seg.key != "0000" else { continue }
                let startIndex = uuid.index(
                    uuid.startIndex, offsetBy: seg.offset, limitedBy: uuid.endIndex
                ) ?? uuid.endIndex
                let endIndex = uuid.index(
                    startIndex, offsetBy: 4, limitedBy: uuid.endIndex
                ) ?? uuid.endIndex
                if String(uuid[startIndex..<endIndex]) == seg.key { score += 1 }
            }
        }

        // Product name match (1 pt)
        if !service.productName.isEmpty,
           let nameDict = dict["DisplayProductName"] as? [String: String],
           let name = nameDict["en_US"] ?? nameDict.values.first,
           name.lowercased() == service.productName.lowercased() {
            score += 1
        }

        // Serial number match (1 pt)
        if service.serialNumber != 0,
           let serial = dict[kDisplaySerialNumber] as? Int64,
           serial == service.serialNumber {
            score += 1
        }

        return score
    }

    // MARK: - EDID UUID segment helpers

    private func edidVendorSegment(dict: NSDictionary) -> String {
        guard let v = dict[kDisplayVendorID] as? Int64 else { return "" }
        return String(format: "%04X", UInt16(clamping: v))
    }

    private func edidProductSegment(dict: NSDictionary) -> String {
        guard let productID = dict[kDisplayProductID] as? Int64 else { return "" }
        let pid = UInt16(clamping: productID)
        return String(format: "%02X%02X", UInt8(pid & 0xFF), UInt8(pid >> 8))
    }

    private func edidMfgDateSegment(dict: NSDictionary) -> String {
        guard let w = dict[kDisplayWeekOfManufacture] as? Int64,
              let y = dict[kDisplayYearOfManufacture] as? Int64 else { return "" }
        return String(format: "%02X%02X", UInt8(clamping: w), UInt8(clamping: y - 1990))
    }

    private func edidSizeSegment(dict: NSDictionary) -> String {
        guard let h = dict[kDisplayHorizontalImageSize] as? Int64,
              let v = dict[kDisplayVerticalImageSize]   as? Int64 else { return "" }
        return String(format: "%02X%02X", UInt8(clamping: h / 10), UInt8(clamping: v / 10))
    }
}
