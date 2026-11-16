#import <Foundation/Foundation.h>
#import "PMCP.h"

@interface QPConnection : NSObject
@property(nonatomic,copy) void (^changed)(void);
@property(nonatomic,readonly) BOOL ready;
@property(nonatomic,readonly) BOOL padReady;
@property(nonatomic,readonly) BOOL connecting;
@property(nonatomic,readonly,copy) NSString *message;
@property(nonatomic,readonly) NSInteger latency;
@property(nonatomic,readonly) int32_t padHandle;
@property(nonatomic,readonly) BOOL supportsControl;
@property(nonatomic,readonly) BOOL controlBusy;
@property(nonatomic,readonly) BOOL vlcInstalled;
@property(nonatomic,readonly) BOOL kodiInstalled;
@property(nonatomic,readonly) NSInteger otherController;
@property(nonatomic,readonly) NSInteger userStatus;
@property(nonatomic,readonly) NSUInteger initializationCount;
@property(nonatomic,copy) void (^completed)(NSString *action, int32_t status);
- (void)connectTo:(NSString *)host;
- (void)disconnect:(NSString *)reason;
- (void)setState:(QPState)state;
- (void)releaseControls;
- (void)checkController;
- (void)initializeController;
- (void)launchVLC;
- (void)launchKodi;
- (void)loadServiceAt:(NSString *)host;
@end
