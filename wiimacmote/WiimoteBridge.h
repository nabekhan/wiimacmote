//
//  WiimoteBridge.h
//  wiimacmote
//
//  Bridging header exposing private IOBluetooth APIs needed for Wiimote pairing.
//  Based on the approach from dolphin-emu/WiimotePair.
//

#import <IOBluetooth/IOBluetooth.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <IOKit/hidsystem/IOHIDUserDevice.h>

// Private API: IOBluetoothDevice
// Exposes the classicPeer property needed for pairing
@interface IOBluetoothDevice (Private)
- (id)classicPeer;
@end

// Private API: IOBluetoothDevicePair
// Exposes methods needed for custom PIN code pairing
@interface IOBluetoothDevicePair (Private)
- (void)setUserDefinedPincode:(BOOL)enabled;
- (NSUInteger)currentPairingType;
@end

// Private API: IOBluetoothCoreBluetoothCoordinator
// Needed to send the pairing PIN code directly
@interface IOBluetoothCoreBluetoothCoordinator : NSObject
+ (IOBluetoothCoreBluetoothCoordinator *)sharedInstance;
- (void)pairPeer:(id)peer forType:(NSUInteger)type withKey:(NSNumber *)key;
@end
