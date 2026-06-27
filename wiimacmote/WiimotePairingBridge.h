#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^WMPairingLogHandler)(NSString *message);
typedef void (^WMPairingCompletion)(IOReturn result, NSString * _Nullable detail);
typedef void (^WMDeviceRemovalCompletion)(IOReturn result, NSString * _Nullable detail);

/// Isolates the private IOBluetooth selectors required to send a Wii Remote's
/// six-byte binary PIN. Selectors are checked at runtime so macOS changes fail
/// cleanly instead of crashing the Swift application.
@interface WMPairingBridge : NSObject <IOBluetoothDevicePairDelegate>

@property (nonatomic, strong, readonly) IOBluetoothDevice *device;

- (instancetype)initWithDevice:(IOBluetoothDevice *)device
                    logHandler:(WMPairingLogHandler)logHandler
                     completion:(WMPairingCompletion)completion NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (IOReturn)start;
- (void)cancel;

@end

@interface WMDeviceRemovalBridge : NSObject

+ (void)removePairingForDevice:(IOBluetoothDevice *)device
                     completion:(WMDeviceRemovalCompletion)completion;

@end

NS_ASSUME_NONNULL_END
