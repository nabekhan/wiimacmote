//
//  wiimacmoteApp.swift
//  wiimacmote
//
//  Wiimote to Virtual Gamepad bridge for macOS.
//  Pairs a Wii Remote via Bluetooth and makes it appear
//  as a standard game controller to any Mac game.
//

import SwiftUI

@main
struct wiimacmoteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 520, height: 600)
    }
}
