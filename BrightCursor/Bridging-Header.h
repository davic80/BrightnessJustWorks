// BrightCursor Bridging Header
// Declares private/semi-private APIs needed for display brightness control.
// These are resolved at link time against system frameworks — no additional
// dylib is needed.

#pragma once

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/i2c/IOI2CInterface.h>
#import <CoreGraphics/CoreGraphics.h>

// ---------------------------------------------------------------------------
// IOAVService — Apple Silicon DDC/CI over DisplayPort / USB-C
// Present in IOKit on macOS 11+. Used to send I2C commands to external
// displays connected via Thunderbolt/USB-C on Apple Silicon Macs.
// ---------------------------------------------------------------------------
typedef CFTypeRef IOAVService;

extern IOAVService IOAVServiceCreate(CFAllocatorRef allocator);
extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn    IOAVServiceReadI2C(IOAVService service,
                                     uint32_t chipAddress,
                                     uint32_t offset,
                                     void * _Nonnull outputBuffer,
                                     uint32_t outputBufferSize);
extern IOReturn    IOAVServiceWriteI2C(IOAVService service,
                                      uint32_t chipAddress,
                                      uint32_t dataAddress,
                                      void * _Nonnull inputBuffer,
                                      uint32_t inputBufferSize);

// ---------------------------------------------------------------------------
// CoreDisplay — display info dictionary (EDID, product name, serial)
// Used to match a CGDirectDisplayID to an IOAVService entry in IORegistry.
// ---------------------------------------------------------------------------
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID);

// ---------------------------------------------------------------------------
// DisplayServices — internal/Apple display brightness (built-in panel,
// Apple Studio Display, Pro Display XDR).
// Returns 0 on success. Brightness value: 0.0 (off) – 1.0 (max).
// ---------------------------------------------------------------------------
extern int DisplayServicesGetBrightness(CGDirectDisplayID display,
                                        float * _Nonnull brightness);
extern int DisplayServicesSetBrightness(CGDirectDisplayID display,
                                        float brightness);

// ---------------------------------------------------------------------------
// CGSServiceForDisplayNumber — resolves a CGDirectDisplayID to an io_service_t
// for the underlying framebuffer (Intel path, kept for completeness).
// ---------------------------------------------------------------------------
extern void CGSServiceForDisplayNumber(CGDirectDisplayID display,
                                       io_service_t * _Nonnull service);

// ---------------------------------------------------------------------------
// OSDManager — shows the native macOS brightness overlay (chiclet indicator).
// Declared via XPC / OSDUIHelper.xpc private protocol.
// ---------------------------------------------------------------------------
@class NSString;

@protocol OSDUIHelperProtocol
- (void)showImage:(long long)arg1
        onDisplayID:(unsigned int)arg2
           priority:(unsigned int)arg3
       msecUntilFade:(unsigned int)arg4
     filledChiclets:(unsigned int)arg5
      totalChiclets:(unsigned int)arg6
             locked:(BOOL)arg7;
- (void)showImage:(long long)arg1
        onDisplayID:(unsigned int)arg2
           priority:(unsigned int)arg3
       msecUntilFade:(unsigned int)arg4;
- (void)showImage:(long long)arg1
        onDisplayID:(unsigned int)arg2
           priority:(unsigned int)arg3
       msecUntilFade:(unsigned int)arg4
           withText:(NSString *)arg5;
@end

@class NSXPCConnection;

@interface OSDManager : NSObject <OSDUIHelperProtocol>
{
    id <OSDUIHelperProtocol> _proxyObject;
    NSXPCConnection *connection;
}
+ (id)sharedManager;
@property(retain) NSXPCConnection *connection;
- (void)showImage:(long long)arg1
        onDisplayID:(unsigned int)arg2
           priority:(unsigned int)arg3
       msecUntilFade:(unsigned int)arg4
     filledChiclets:(unsigned int)arg5
      totalChiclets:(unsigned int)arg6
             locked:(BOOL)arg7;
- (void)showImage:(long long)arg1
        onDisplayID:(unsigned int)arg2
           priority:(unsigned int)arg3
       msecUntilFade:(unsigned int)arg4;
- (void)showImage:(long long)arg1
        onDisplayID:(unsigned int)arg2
           priority:(unsigned int)arg3
       msecUntilFade:(unsigned int)arg4
           withText:(NSString *)arg5;
@property(readonly) id <OSDUIHelperProtocol> remoteObjectProxy;
@end
