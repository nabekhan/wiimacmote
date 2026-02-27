
import Foundation
import IOKit
import IOKit.hid

class TestHID {
    var manager: IOHIDManager?
    
    func setup() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    }
}
