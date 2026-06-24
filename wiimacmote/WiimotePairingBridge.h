#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^WMPairingLogHandler)(NSString *message);
typedef void (^WMPairingCompletion)(IOReturn result, NSString * _Nullable detail);

/// Isolates the private IOBluetooth selectors currently required to send a Wii
/// Remote's six-byte binary PIN. Every selector is checked at runtime so a
/// future macOS change fails cleanly instead of crashing the Swift application.
@interface WMPairingBridge : NSObject <IOBluetoothDevicePairDelegate>

@property (nonatomic, strong, readonly) IOBluetoothDevice *device;

- (instancetype)initWithDevice:(IOBluetoothDevice *)device
                    logHandler:(WMPairingLogHandler)logHandler
                     completion:(WMPairingCompletion)completion NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (IOReturn)start;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
