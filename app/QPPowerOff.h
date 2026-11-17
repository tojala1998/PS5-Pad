#import <Foundation/Foundation.h>
@interface QPPowerOff : NSObject
@property(nonatomic,readonly) BOOL available;
@property(nonatomic,copy) void (^completed)(NSString *message);
- (void)requestAt:(NSString *)host confirmed:(BOOL)confirmed;
- (void)cancel;
@end
