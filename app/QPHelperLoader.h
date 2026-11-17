#import <Foundation/Foundation.h>
@interface QPHelperLoader : NSObject
@property(nonatomic,copy) void (^progress)(NSString *message);
@property(nonatomic,copy) void (^completed)(NSString *error);
- (void)start:(NSString *)host image:(NSData *)image;
- (void)cancel;
@end
