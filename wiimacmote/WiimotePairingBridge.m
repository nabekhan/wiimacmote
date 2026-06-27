#import "WiimotePairingBridge.h"

#import <CoreBluetooth/CoreBluetooth.h>
#import <IOKit/IOReturn.h>
#import <mach/mach_error.h>
#import <objc/message.h>
#import <string.h>

@interface IOBluetoothDevice (WiiMacMotePrivate)
- (id)classicPeer;
@end

static NSString *WMNormalizedBluetoothAddress(NSString *address) {
    if (address.length == 0) {
        return @"";
    }

    NSMutableString *normalized = [NSMutableString stringWithCapacity:address.length];
    NSCharacterSet *hexCharacters = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger index = 0; index < address.length; index++) {
        unichar character = [address characterAtIndex:index];
        if ([hexCharacters characterIsMember:character]) {
            [normalized appendFormat:@"%C", character];
        }
    }
    return normalized.uppercaseString;
}

static BOOL WMPairedDevicesContainAddress(NSString *address) {
    NSString *target = WMNormalizedBluetoothAddress(address);
    if (target.length == 0) {
        return NO;
    }

    NSArray *devices = [IOBluetoothDevice pairedDevices];
    for (IOBluetoothDevice *pairedDevice in devices) {
        NSString *pairedAddress = WMNormalizedBluetoothAddress(pairedDevice.addressString);
        if ([pairedAddress isEqualToString:target]) {
            return YES;
        }
    }
    return NO;
}

static void WMCompleteRemovalAfterVerification(NSString *address,
                                               NSString *method,
                                               WMDeviceRemovalCompletion completion) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (address.length > 0 && !WMPairedDevicesContainAddress(address)) {
            completion(kIOReturnSuccess, method);
            return;
        }

        NSString *detail = method.length > 0
            ? [NSString stringWithFormat:@"%@ did not remove the pairing.", method]
            : @"The pairing still appears in macOS paired devices.";
        completion(kIOReturnError, detail);
    });
}

@implementation WMDeviceRemovalBridge

+ (void)removePairingForDevice:(IOBluetoothDevice *)device
                     completion:(WMDeviceRemovalCompletion)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (device == nil) {
            completion(kIOReturnBadArgument, @"Bluetooth device is unavailable.");
            return;
        }

        NSString *address = device.addressString ?: @"";
        if (address.length > 0 && !WMPairedDevicesContainAddress(address)) {
            completion(kIOReturnSuccess, @"already absent from paired devices");
            return;
        }

        if ([device isConnected]) {
            [device closeConnection];
        }

        [device removeFromFavorites];

        NSArray<NSString *> *deviceSelectors = @[
            @"remove",
            @"unpair",
            @"removePairing",
            @"removeFromPairedDevices"
        ];
        for (NSString *selectorName in deviceSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([device respondsToSelector:selector]) {
                typedef void (*SendRemoveMessage)(id, SEL);
                ((SendRemoveMessage)objc_msgSend)(device, selector);
                WMCompleteRemovalAfterVerification(address, selectorName, completion);
                return;
            }
        }

        Class coordinatorClass = NSClassFromString(@"IOBluetoothCoreBluetoothCoordinator");
        SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
        if (coordinatorClass != Nil &&
            [coordinatorClass respondsToSelector:sharedSelector] &&
            [device respondsToSelector:@selector(classicPeer)]) {
            typedef id (*SendIdMessage)(id, SEL);
            typedef void (*SendPeerMessage)(id, SEL, id);
            id coordinator = ((SendIdMessage)objc_msgSend)((id)coordinatorClass, sharedSelector);
            id peer = [device classicPeer];
            NSArray<NSString *> *coordinatorSelectors = @[
                @"unpairPeer:",
                @"removePeer:",
                @"forgetPeer:"
            ];
            for (NSString *selectorName in coordinatorSelectors) {
                SEL selector = NSSelectorFromString(selectorName);
                if (coordinator != nil && peer != nil && [coordinator respondsToSelector:selector]) {
                    ((SendPeerMessage)objc_msgSend)(coordinator, selector, peer);
                    WMCompleteRemovalAfterVerification(address, selectorName, completion);
                    return;
                }
            }
        }

        if (address.length > 0 && !WMPairedDevicesContainAddress(address)) {
            completion(kIOReturnSuccess, @"paired-device list update");
            return;
        }

        completion(
            kIOReturnUnsupported,
            @"macOS did not expose an IOBluetooth/CoreBluetooth unpair selector for this device."
        );
    });
}

@end

@interface IOBluetoothDevicePair (WiiMacMotePrivate)
- (void)setUserDefinedPincode:(BOOL)enabled;
- (NSUInteger)currentPairingType;
@end

@interface WMPairingBridge ()
@property (nonatomic, strong, readwrite) IOBluetoothDevice *device;
@property (nonatomic, strong, nullable) IOBluetoothDevicePair *pairingAgent;
@property (nonatomic, copy) WMPairingLogHandler logHandler;
@property (nonatomic, copy) WMPairingCompletion completion;
@property (nonatomic, assign) BOOL finished;
@end

@implementation WMPairingBridge

- (instancetype)initWithDevice:(IOBluetoothDevice *)device
                    logHandler:(WMPairingLogHandler)logHandler
                     completion:(WMPairingCompletion)completion {
    self = [super init];
    if (self) {
        _device = device;
        _logHandler = [logHandler copy];
        _completion = [completion copy];
    }
    return self;
}

- (IOReturn)start {
    if (self.pairingAgent != nil) {
        return kIOReturnBusy;
    }

    IOBluetoothDevicePair *agent = [IOBluetoothDevicePair pairWithDevice:self.device];
    if (agent == nil) {
        return kIOReturnNoMemory;
    }

    if (![agent respondsToSelector:@selector(setUserDefinedPincode:)]) {
        [self finish:kIOReturnUnsupported detail:@"macOS no longer exposes the custom-PIN pairing selector."];
        return kIOReturnUnsupported;
    }

    self.pairingAgent = agent;
    agent.delegate = self;
    [agent setUserDefinedPincode:YES];
    self.logHandler(@"Pairing agent started with binary-PIN mode.");

    IOReturn result = [agent start];
    if (result != kIOReturnSuccess) {
        [agent stop];
        self.pairingAgent = nil;
    }
    return result;
}

- (void)cancel {
    [self.pairingAgent stop];
    self.pairingAgent = nil;
}

- (void)devicePairingPINCodeRequest:(id)sender {
    IOBluetoothDevicePair *pair = (IOBluetoothDevicePair *)sender;
    IOBluetoothHostController *controller = [IOBluetoothHostController defaultController];
    NSString *addressString = [controller addressAsString];

    if (controller == nil || addressString.length == 0) {
        [self finish:kIOReturnNotReady detail:@"The Mac Bluetooth controller address is unavailable."];
        return;
    }

    if (![self.device respondsToSelector:@selector(classicPeer)] ||
        ![pair respondsToSelector:@selector(currentPairingType)]) {
        [self finish:kIOReturnUnsupported detail:@"Required private pairing selectors are unavailable on this macOS release."];
        return;
    }

    BluetoothDeviceAddress controllerAddress;
    memset(&controllerAddress, 0, sizeof(controllerAddress));
    IOBluetoothNSStringToDeviceAddress(addressString, &controllerAddress);

    BluetoothPINCode code;
    memset(&code, 0, sizeof(code));
    for (int index = 0; index < 6; index++) {
        code.data[index] = controllerAddress.data[5 - index];
    }

    uint64_t key = 0;
    memcpy(&key, code.data, sizeof(key));

    Class coordinatorClass = NSClassFromString(@"IOBluetoothCoreBluetoothCoordinator");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    SEL pairSelector = NSSelectorFromString(@"pairPeer:forType:withKey:");

    if (coordinatorClass == Nil || ![coordinatorClass respondsToSelector:sharedSelector]) {
        [self finish:kIOReturnUnsupported detail:@"The macOS Bluetooth pairing coordinator is unavailable."];
        return;
    }

    typedef id (*SendIdMessage)(id, SEL);
    typedef void (*SendPairMessage)(id, SEL, id, NSUInteger, NSNumber *);

    id coordinator = ((SendIdMessage)objc_msgSend)((id)coordinatorClass, sharedSelector);
    id peer = [self.device classicPeer];
    if (coordinator == nil || peer == nil || ![coordinator respondsToSelector:pairSelector]) {
        [self finish:kIOReturnUnsupported detail:@"The Bluetooth pairing coordinator rejected the Wii Remote peer."];
        return;
    }

    NSUInteger pairingType = [pair currentPairingType];
    self.logHandler([NSString stringWithFormat:@"Sending six-byte PIN using host controller %@.", addressString]);
    ((SendPairMessage)objc_msgSend)(coordinator, pairSelector, peer, pairingType, @(key));
}

- (void)devicePairingFinished:(id)sender error:(IOReturn)error {
    [self.pairingAgent stop];
    self.pairingAgent = nil;

    NSString *detail = nil;
    if (error != kIOReturnSuccess) {
        char *message = mach_error_string(error);
        if (message != NULL) {
            detail = [NSString stringWithUTF8String:message];
        }
    }
    [self finish:error detail:detail];
}

- (void)finish:(IOReturn)result detail:(NSString * _Nullable)detail {
    if (self.finished) {
        return;
    }
    self.finished = YES;
    [self.pairingAgent stop];
    self.pairingAgent = nil;

    WMPairingCompletion completion = self.completion;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(result, detail);
    });
}

@end
