#import "QPDiscovery.h"
#import "QPDiscoveryNet.h"
#import <ifaddrs.h>
#import <net/if.h>

@interface QPDiscoveryController () <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) UILabel *heading,*detail,*progress;
@property(nonatomic,strong) UIButton *scan,*manual;
@property(nonatomic,strong) UIImageView *hero;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *results;
@property(nonatomic,strong) NSOperationQueue *workers;
@property(nonatomic) NSUInteger generation,finished,total;
@property(nonatomic) BOOL scanning,limited;
@end

@implementation QPDiscoveryController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Add a console";
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=[UIColor colorWithWhite:.09 alpha:1];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    _hero=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"gamecontroller.fill"]];
    _hero.tintColor=[UIColor colorWithRed:.42 green:.65 blue:1 alpha:1]; _hero.contentMode=UIViewContentModeScaleAspectFit;
    _heading=[UILabel new]; _heading.text=@"Find your PS5"; _heading.font=[UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    _detail=[UILabel new]; _detail.text=@"Connect to the same Wi-Fi as your PS5 and start its PS5 Pad service. Then scan and choose your console.";
    _detail.font=[UIFont systemFontOfSize:15]; _detail.textColor=UIColor.secondaryLabelColor; _detail.numberOfLines=0;
    _progress=[UILabel new]; _progress.font=[UIFont systemFontOfSize:13]; _progress.textColor=UIColor.secondaryLabelColor; _progress.numberOfLines=0;
    _progress.text=@"Nothing is added until you choose a console.";
    for(UILabel *label in @[_heading,_detail,_progress]) label.textAlignment=NSTextAlignmentCenter;
    _scan=[UIButton buttonWithType:UIButtonTypeSystem]; [_scan setTitle:@"Scan Wi-Fi" forState:UIControlStateNormal];
    _scan.titleLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _scan.backgroundColor=_hero.tintColor; _scan.tintColor=UIColor.blackColor; _scan.layer.cornerRadius=14;
    [_scan addTarget:self action:@selector(startScan) forControlEvents:UIControlEventTouchUpInside];
    _manual=[UIButton buttonWithType:UIButtonTypeSystem]; [_manual setTitle:@"Enter address manually" forState:UIControlStateNormal];
    [_manual addTarget:self action:@selector(manualAddress) forControlEvents:UIControlEventTouchUpInside];
    _table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor=UIColor.clearColor; _table.dataSource=self; _table.delegate=self;
    _table.rowHeight=76; _table.tableFooterView=[UIView new];
    _spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _results=[NSMutableArray array]; _workers=[NSOperationQueue new]; _workers.maxConcurrentOperationCount=12;
    for(UIView *view in @[_hero,_heading,_detail,_scan,_manual,_progress,_table,_spinner]) [self.view addSubview:view];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopScan) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; CGFloat w=self.view.bounds.size.width;
    CGFloat y=self.view.safeAreaInsets.top+24,h=self.view.bounds.size.height-self.view.safeAreaInsets.bottom;
    _hero.frame=CGRectMake(w/2-38,y,76,48); _heading.frame=CGRectMake(20,y+67,w-40,40);
    _detail.frame=CGRectMake(28,y+118,w-56,76); _scan.frame=CGRectMake(28,y+214,w-56,52);
    _manual.frame=CGRectMake(28,y+273,w-56,44); _progress.frame=CGRectMake(30,y+329,w-60,62);
    _spinner.frame=CGRectMake(w/2-10,y+397,20,20);
    _table.frame=CGRectMake(16,y+426,w-32,fmax(0,h-y-426));
}
- (void)stopScan {
    _generation++; [_workers cancelAllOperations]; _scanning=NO;
    [_spinner stopAnimating]; [_scan setTitle:@"Scan again" forState:UIControlStateNormal];
}
- (void)close { [self stopScan]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [self stopScan]; }
- (void)dealloc { [_workers cancelAllOperations]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)startScan {
    if(_scanning) { [self stopScan]; _progress.text=@"Scan stopped. You can scan again anytime."; return; }
    struct ifaddrs *interfaces=NULL; uint32_t address=0,mask=0;
    if(!getifaddrs(&interfaces)) {
        for(struct ifaddrs *item=interfaces;item;item=item->ifa_next) {
            if(!item->ifa_addr || !item->ifa_netmask || item->ifa_addr->sa_family!=AF_INET ||
               !(item->ifa_flags&IFF_UP) || (item->ifa_flags&IFF_LOOPBACK) || strncmp(item->ifa_name,"en",2)) continue;
            address=ntohl(((struct sockaddr_in *)item->ifa_addr)->sin_addr.s_addr);
            mask=ntohl(((struct sockaddr_in *)item->ifa_netmask)->sin_addr.s_addr); break;
        }
        freeifaddrs(interfaces);
    }
    uint32_t first=0,last=0; int range=qp_scan_range(address,mask,&first,&last);
    if(!address || !range) { _progress.text=@"Join a Wi-Fi network, then try again. You can also enter your PS5’s address."; return; }
    [self stopScan]; NSUInteger generation=_generation; _scanning=YES; _limited=range==2; _finished=0; _total=last-first;
    [_results removeAllObjects]; [_table reloadData]; [_spinner startAnimating];
    [_scan setTitle:@"Stop scan" forState:UIControlStateNormal];
    _progress.text=@"Looking for PS5 Pad… Allow Local Network access if iOS asks, then scan again if needed.";
    __weak QPDiscoveryController *weakSelf=self;
    for(uint32_t ip=first;ip<=last;ip++) {
        if(ip==address) continue;
        [_workers addOperationWithBlock:^{
            int found=qp_probe(ip,9305,650);
            dispatch_async(dispatch_get_main_queue(),^{
                QPDiscoveryController *self=weakSelf; if(!self || generation!=self.generation || !self.scanning) return;
                self.finished++;
                if(found) {
                    struct in_addr addr={htonl(ip)}; char buffer[INET_ADDRSTRLEN]; inet_ntop(AF_INET,&addr,buffer,sizeof buffer);
                    [self.results addObject:@{@"host":[NSString stringWithUTF8String:buffer],@"busy":@(found==2)}]; [self.table reloadData];
                }
                if(self.finished==self.total) {
                    self.scanning=NO; [self.spinner stopAnimating]; [self.scan setTitle:@"Scan again" forState:UIControlStateNormal];
                    self.progress.text=self.results.count?@"Choose a console below to add it.":@"No PS5 Pad service found. Start it on your PS5, allow Local Network access, and try again. Another network? Enter its address.";
                    if(self.limited) self.progress.text=[self.progress.text stringByAppendingString:@" Scanned the nearest 254 addresses on this larger network."];
                } else if(self.finished%20==0) self.progress.text=[NSString stringWithFormat:@"Scanning Wi-Fi… %lu of %lu\n%lu console%@ found",(unsigned long)self.finished,(unsigned long)self.total,(unsigned long)self.results.count,self.results.count==1?@"":@"s"];
            });
        }];
    }
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return _results.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"console"];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"console"];
    NSDictionary *console=_results[indexPath.row]; cell.textLabel.text=[@"PS5 · " stringByAppendingString:console[@"host"]];
    cell.detailTextLabel.text=[console[@"busy"] boolValue]?@"PS5 Pad is connected in another app":@"PS5 Pad service available";
    cell.imageView.image=[UIImage systemImageNamed:@"gamecontroller"]; cell.imageView.tintColor=_hero.tintColor;
    cell.backgroundColor=UIColor.clearColor; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSString *host=_results[indexPath.row][@"host"];
    [self confirmHost:host verified:YES];
}
- (void)confirmHost:(NSString *)host verified:(BOOL)verified {
    [self stopScan];
    NSString *message=[NSString stringWithFormat:@"%@\n%@",host,verified?@"Add this console to PS5 Pad? The controller stays off until you turn it on.":@"This address has not been verified. Add it and connect when your PS5 Pad service is running?"];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Add your PS5" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add PS5" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        (void)action; void (^added)(NSString *)=self.added;
        [self dismissViewControllerAnimated:YES completion:^{ if(added) added(host); }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)manualAddress {
    [self stopScan];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"PS5 address" message:@"Enter the local IPv4 address shown on your console." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=@"IP address"; field.keyboardType=UIKeyboardTypeDecimalPad; field.autocorrectionType=UITextAutocorrectionTypeNo;}];
    [alert addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        (void)action; NSString *host=[alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        struct in_addr address;
        if(inet_pton(AF_INET,host.UTF8String,&address)!=1 || !ntohl(address.s_addr) || ntohl(address.s_addr)>=0xe0000000 || (ntohl(address.s_addr)>>24)==127) { self.progress.text=@"Enter a valid console IPv4 address."; return; }
        dispatch_async(dispatch_get_main_queue(),^{[self confirmHost:host verified:NO];});
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
