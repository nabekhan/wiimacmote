import Foundation

guard let gamepad = VirtualGamepad() else {
    print("❌ Failed to create virtual gamepad")
    print("This may require:")
    print("  • Input Monitoring permission in System Settings")
    print("  • Running with 'sudo' during development")
    exit(1)
}

print("✅ Virtual gamepad created successfully!")
print("📱 Device: Wiimote Virtual Gamepad")
print("🎮 It should now appear as a controller in gamepad testers.")
print("🔄 Sending dummy button patterns every second...")
print("⏹️  Press Ctrl+C to exit.\n")

var toggle = false

// Simple timer: every second switch some buttons on/off
let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
    toggle.toggle()
    let mask: UInt16 = toggle ? 0b0000000011 : 0 // buttons 1 & 2
    gamepad.sendButtonMask(mask)
    print("📤 Sent button mask: \(String(mask, radix: 2).padding(toLength: 10, withPad: "0", startingAt: 0)) (buttons \(toggle ? "1,2 ON" : "all OFF"))")
}

RunLoop.main.add(timer, forMode: .default)
RunLoop.main.run()
