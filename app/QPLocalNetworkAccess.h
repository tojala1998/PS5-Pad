#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger,QPLocalAccessState) {
    QPLocalAccessChecking, QPLocalAccessAllowed, QPLocalAccessWaiting, QPLocalAccessFailed
};
@interface QPLocalNetworkAccess : NSObject
@property(nonatomic,copy) void (^changed)(QPLocalAccessState state);
- (void)request;
- (void)cancel;
@end
