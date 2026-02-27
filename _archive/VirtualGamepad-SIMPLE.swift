//
//  VirtualGamepad.swift
//  wiimacmote
//
//  Virtual HID gamepad device for macOS
//  USE THIS VERSION - Simple and works with bridging header
//

import Foundation
import IOKit

/// A virtual HID gamepad that appears to macOS as a physical controller
final class VirtualGamepad {
    private var device: IOHIDUserDevice?
    private var lastButtonMask: UInt16 = 0
    
    init?() {
        // HID descriptor for a simple gamepad with 10 buttons
        let descriptor: [UInt8] = [
            0x05, 0x01,       // Usage Page (Generic Desktop)
            0x09, 0x05,       // Usage (Gamepad)
            0xA1, 0x01,       // Collection (Application)
            0x05, 0x09,       //  Usage Page (Button)
            0x19, 0x01,       //  Usage Min (1)
            0x29, 0x0A,       //  Usage Max (10)
            0x15, 0x00,       //  Logical Min (0)
            0x25, 0x01,       //  Logical Max (1)
            0x95, 0x0A,       //  Report Count (10 buttons)
            0x75, 0x01,       //  Report Size (1 bit)
            0x81, 0x02,       //  Input (Data,Var,Abs)
            0x95, 0x01,       //  Report Count (1) padding
            0x75, 0x06,       //  Report Size (6 bits)
            0x81, 0x03,       //  Input (Const,Var,Abs) padding
            0xC0              // End Collection
        ]

        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey as String: Data(descriptor),
            kIOHIDProductKey as String: "Wiimote Virtual Gamepad",
            kIOHIDVendorIDKey as String: 0x057E,  // Nintendo vendor ID
            kIOHIDProductIDKey as String: 0x0306  // Wiimote product ID
        ]

        guard let dev = IOHIDUserDeviceCreateWithProperties(
            kCFAllocatorDefault,
            properties as CFDictionary,
            0
        ) else {
            print("⚠️  IOHIDUserDeviceCreateWithProperties returned nil")
            print("    Possible causes:")
            print("    • App not code signed")
            print("    • Input Monitoring permission not granted")
            print("    • System Settings → Privacy & Security → Input Monitoring")
            return nil
        }

        self.device = dev
        
        // Activate the device (required on modern macOS)
        let result = IOHIDUserDeviceActivate(dev)
        if result == kIOReturnSuccess {
            print("✅ Virtual gamepad created and activated")
            print("📱 Device: Wiimote Virtual Gamepad")
            print("🎮 Should now appear in gamepad testers")
            print("🌐 Test at: https://gamepad-tester.com")
        } else {
            print("⚠️  IOHIDUserDeviceActivate failed with code: \(result)")
            return nil
        }
    }
    
    deinit {
        if let device = device {
            IOHIDUserDeviceCancel(device)
            print("🔌 Virtual gamepad deactivated")
        }
    }

    /// Send button state to the virtual gamepad
    /// - Parameter mask: 10-bit bitfield where bit 0 = button 1, bit 1 = button 2, etc.
    func sendButtonMask(_ mask: UInt16) {
        guard let device = device else { return }
        
        self.lastButtonMask = mask
        var report = mask
        withUnsafeBytes(of: &report) { buffer in
            guard let ptr = buffer.baseAddress else { return }
            let timestamp = mach_absolute_time()
            let result = IOHIDUserDeviceHandleReportWithTimeStamp(
                device,
                timestamp,
                ptr.assumingMemoryBound(to: UInt8.self),
                buffer.count
            )
            
            if result == kIOReturnSuccess {
                // Success - buttons sent
            } else {
                print("⚠️  Failed to send button report: \(result)")
            }
        }
    }
    
    /// Send individual button states
    /// - Parameter buttons: Array of button numbers (1-10) that are currently pressed
    func sendButtons(_ buttons: [Int]) {
        var mask: UInt16 = 0
        for button in buttons where button >= 1 && button <= 10 {
            mask |= (1 << (button - 1))
        }
        sendButtonMask(mask)
    }
    
    /// Clear all button states (release all buttons)
    func releaseAll() {
        sendButtonMask(0)
    }
    
    /// Get current button state
    func getCurrentMask() -> UInt16 {
        return lastButtonMask
    }
}
