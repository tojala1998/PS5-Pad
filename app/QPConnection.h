#import <Foundation/Foundation.h>
#import "PMCP.h"

typedef NS_ENUM(NSInteger, QPConnectionFailure) { QPConnectionFailureNone, QPConnectionFailureUnavailable, QPConnectionFailureOther };

@interface QPConnection : NSObject
@property(nonatomic,copy) void (^changed)(void);
/* A matching successful controller-report ACK, not proof of app/profile routing. */
@property(nonatomic,copy) void (^inputAcknowledged)(uint32_t buttons);
@property(nonatomic,copy) void (^inputFeedbackReset)(void);
@property(nonatomic,readonly) BOOL ready;
@property(nonatomic,readonly) QPConnectionFailure failureKind;
@property(nonatomic,readonly) BOOL controllerChecked;
@property(nonatomic,readonly) BOOL padReady;
@property(nonatomic,readonly) BOOL supportsOwnership,profileAssigned,waitingForProfile,monitorReady,supportsTextInput;
@property(nonatomic,readonly) BOOL connecting;
@property(nonatomic,readonly,copy) NSString *message;
@property(nonatomic,readonly) NSInteger latency;
@property(nonatomic,readonly) int32_t padHandle;
@property(nonatomic,readonly) BOOL supportsControl;
@property(nonatomic,readonly) BOOL supportsDisconnectController;
@property(nonatomic,readonly) BOOL disconnectingController;
@property(nonatomic,readonly) BOOL controlBusy;
@property(nonatomic,readonly) BOOL vlcInstalled;
@property(nonatomic,readonly) BOOL kodiInstalled;
@property(nonatomic,readonly) NSInteger otherController;
@property(nonatomic,readonly) NSInteger userStatus;
@property(nonatomic,readonly) NSUInteger initializationCount;
@property(nonatomic,copy) void (^completed)(NSString *action, int32_t status);
- (void)connectTo:(NSString *)host;
- (void)connectTo:(NSString *)host timeout:(NSTimeInterval)timeout;
- (void)disconnect:(NSString *)reason;
- (void)limitConnectWait:(NSTimeInterval)timeout;
- (void)setState:(QPState)state;
- (void)releaseControls;
- (void)checkController;
- (void)initializeController;
- (void)disconnectController;
@property(nonatomic,readonly) BOOL supportsLiveKeyboard,keyboardConnected,keyboardActive,keyboardClosing;
@property(nonatomic,readonly,copy) NSString *keyboardMessage;
- (void)openKeyboard;
- (void)updateKeyboardText:(NSString *)text;
- (void)closeKeyboardWithEnter:(BOOL)enter;
- (void)typeText:(NSString *)text;
- (void)launchVLC;
- (void)launchKodi;
- (void)loadServiceAt:(NSString *)host;
@end
