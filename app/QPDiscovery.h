#import <UIKit/UIKit.h>
@interface QPDiscoveryController : UIViewController
@property(nonatomic,copy) void (^added)(NSString *host);
@end
