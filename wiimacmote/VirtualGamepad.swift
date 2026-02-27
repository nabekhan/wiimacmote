//
//  VirtualGamepad.swift
//  wiimacmote
//
//  Creates a virtual HID gamepad that macOS recognizes as a standard controller.
//  Uses IOHIDUserDevice to appear as a real gamepad to games and apps.
//

import Foundation
import IOKit

/// A virtual HID gamepad device that appears to macOS as a physical game controller.
/// Report format: 8 bytes
final class VirtualGamepad {
    
    // MARK: - Properties
    
    private var device: IOHIDUserDevice?
    private(set) var isActive: Bool = false
    
    /// Current gamepad state
    struct GamepadState {
        var x: Int8 = 0
        var y: Int8 = 0
        var z: Int8 = 0
        var rz: Int8 = 0
        var hat: UInt8 = 0x08 // 0-7 direction, 8 null
        var buttons: UInt16 = 0 // 15 buttons
    }
    
    private var state = GamepadState()
    
    // MARK: - Button Definitions
    
    /// Gamepad button indices
    enum Button: Int, CaseIterable {
        case a = 0          // 1
        case b = 1          // 2
        case x = 2          // 3
        case y = 3          // 4
        case leftShoulder = 4   // 5
        case rightShoulder = 5  // 6
        case leftTrigger = 6    // 7 (Button, not axis for now)
        case rightTrigger = 7   // 8
        case select = 8     // 9
        case start = 9      // 10
        case leftThumb = 10 // 11
        case rightThumb = 11// 12
        case home = 12      // 13
        // 14, 15 spare
        
        var mask: UInt16 { 1 << rawValue }
        
        // Mappings for WiimoteManager convenience
        static let minus = select
        static let plus = start
    }
    
    // MARK: - Initialization
    
    init?() {
        // Extended Gamepad Descriptor (Xbox-ish style)
        let descriptor: [UInt8] = [
            0x05, 0x01,        // Usage Page (Generic Desktop)
            0x09, 0x05,        // Usage (Gamepad)
            0xA1, 0x01,        // Collection (Application)
            
            // --- Axes (X, Y, Z, Rz) ---
            0x09, 0x01,        //   Usage (Pointer)
            0xA1, 0x00,        //   Collection (Physical)
            0x09, 0x30,        //     Usage (X)
            0x09, 0x31,        //     Usage (Y)
            0x09, 0x32,        //     Usage (Z)
            0x09, 0x35,        //     Usage (Rz)
            0x15, 0x81,        //     Logical Min (-127)
            0x25, 0x7F,        //     Logical Max (127)
            0x75, 0x08,        //     Report Size (8)
            0x95, 0x04,        //     Report Count (4)
            0x81, 0x02,        //     Input (Data, Var, Abs)
            0xC0,              //   End Collection
            
            // --- Hat Switch (D-pad) ---
            0x09, 0x39,        //   Usage (Hat Switch)
            0x15, 0x00,        //   Logical Min (0)
            0x25, 0x07,        //   Logical Max (7)
            0x35, 0x00,        //   Physical Min (0)
            0x46, 0x3B, 0x01,  //   Physical Max (315)
            0x65, 0x14,        //   Unit (Degrees)
            0x75, 0x04,        //   Report Size (4)
            0x95, 0x01,        //   Report Count (1)
            0x81, 0x42,        //   Input (Data, Var, Abs, Null)
            
            // --- Buttons (15) ---
            0x05, 0x09,        //   Usage Page (Button)
            0x19, 0x01,        //   Usage Min (1)
            0x29, 0x0F,        //   Usage Max (15)
            0x15, 0x00,        //   Logical Min (0)
            0x25, 0x01,        //   Logical Max (1)
            0x75, 0x01,        //   Report Size (1)
            0x95, 0x0F,        //   Report Count (15)
            0x81, 0x02,        //   Input (Data, Var, Abs)
            
            // --- Padding (13 bits) ---
            // 4 axes (32) + Hat (4) + Buttons (15) = 51 bits.
            // 64 - 51 = 13 bits.
            0x75, 0x01,        //   Report Size (1)
            0x95, 0x0D,        //   Report Count (13)
            0x81, 0x03,        //   Input (Const, Var, Abs)
            
            0xC0               // End Collection
        ]
        
        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey as String: Data(descriptor),
            kIOHIDProductKey as String: "Wiimote Virtual Controller",
            kIOHIDManufacturerKey as String: "wiimacmote",
            kIOHIDVendorIDKey as String: NSNumber(value: 0x045E),   // Microsoft (Best compatibility)
            kIOHIDProductIDKey as String: NSNumber(value: 0x028E),  // Xbox 360 Controller
            kIOHIDTransportKey as String: "Virtual",
            kIOHIDPrimaryUsagePageKey as String: 0x01,
            kIOHIDPrimaryUsageKey as String: 0x05
        ]
        
        guard let dev = IOHIDUserDeviceCreateWithProperties(
            kCFAllocatorDefault,
            properties as CFDictionary,
            0
        ) else {
            print("❌ IOHIDUserDeviceCreateWithProperties returned nil")
            return nil
        }
        
        self.device = dev
        
        IOHIDUserDeviceSetDispatchQueue(dev, DispatchQueue.main)
        IOHIDUserDeviceActivate(dev)
        
        self.isActive = true
        print("✅ Virtual gamepad activated (Xbox 360 Mode)")
    }
    
    deinit {
        if let device = device {
            IOHIDUserDeviceCancel(device)
        }
    }
    
    // MARK: - State Updates
    
    private func sendReport() {
        guard let device = device else { return }
        
        // Format: [X][Y][Z][Rz] [Hat(low4)|Btn1-4(high4)] [Btn5-12] [Btn13-15(low3)|Pad(high5)] [Pad]
        // But packing is bit-level.
        // Byte 0: X
        // Byte 1: Y
        // Byte 2: Z
        // Byte 3: Rz
        // Byte 4: Hat (0-3) + Btn1-4 (4-7)
        // Byte 5: Btn5-12
        // Byte 6: Btn13-15 (0-2) + Pad (3-7)
        // Byte 7: Pad
        
        var report = [UInt8](repeating: 0, count: 8)
        report[0] = UInt8(bitPattern: state.x)
        report[1] = UInt8(bitPattern: state.y)
        report[2] = UInt8(bitPattern: state.z)
        report[3] = UInt8(bitPattern: state.rz)
        
        let hat = state.hat & 0x0F
        let btns = state.buttons
        
        // Byte 4: Hat (low 4 bits) | Btn 1-4 (high 4 bits)
        // Btn 1 is bit 0 of buttons.
        let b1_4 = UInt8(btns & 0x0F)
        report[4] = hat | (b1_4 << 4)
        
        // Byte 5: Btn 5-12 (bits 4-11 of buttons)
        let b5_12 = UInt8((btns >> 4) & 0xFF)
        report[5] = b5_12
        
        // Byte 6: Btn 13-15 (bits 12-14)
        let b13_15 = UInt8((btns >> 12) & 0x07)
        report[6] = b13_15
        
        // Byte 7: 0
        
        report.withUnsafeBufferPointer { buffer in
            guard let ptr = buffer.baseAddress else { return }
            let timestamp = mach_absolute_time()
            IOHIDUserDeviceHandleReportWithTimeStamp(
                device,
                timestamp,
                ptr,
                buffer.count
            )
        }
    }
    
    /// Update gamepad state
    /// - Parameters:
    ///   - xAxis: Left Stick X
    ///   - yAxis: Left Stick Y
    ///   - dpad: (up, down, left, right) booleans
    ///   - buttons: Button mask (VirtualGamepad.Button)
    func update(xAxis: Int8, yAxis: Int8, dpad: (Bool, Bool, Bool, Bool), buttons: UInt16) {
        state.x = xAxis
        state.y = yAxis
        state.z = 0
        state.rz = 0
        state.buttons = buttons
        
        // Calculate Hat
        // 0=Up, 1=UR, 2=R, 3=DR, 4=D, 5=DL, 6=L, 7=UL, 8=Null
        let (up, down, left, right) = dpad
        var h: UInt8 = 0x08
        
        if up {
            if right { h = 1 }
            else if left { h = 7 }
            else { h = 0 }
        } else if down {
            if right { h = 3 }
            else if left { h = 5 }
            else { h = 4 }
        } else if right {
            h = 2
        } else if left {
            h = 6
        }
        
        state.hat = h
        sendReport()
    }
    
    func reset() {
        state = GamepadState()
        sendReport()
    }
}
