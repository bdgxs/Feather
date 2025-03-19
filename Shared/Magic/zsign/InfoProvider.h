// InfoProvider.m
    
    #import "InfoProvider.h"
    
    @interface InfoProvider ()
    
    @property (nonatomic, strong) UIButton *floatingButton;
    @property (nonatomic, strong) UIWindow *infoWindow;
    
    @end
    
    @implementation InfoProvider
    
    + (instancetype)sharedProvider {
        static InfoProvider *sharedProvider = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sharedProvider = [[InfoProvider alloc] init];
        });
        return sharedProvider;
    }
    
    - (instancetype)init {
        self = [super init];
        if (self) {
            [self setupFloatingButton];
        }
        return self;
    }
    
    - (void)setupFloatingButton {
        self.floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.floatingButton.frame = CGRectMake(20, 60, 60, 60);
        [self.floatingButton setTitle:@"Info" forState:UIControlStateNormal];
        self.floatingButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
        self.floatingButton.layer.cornerRadius = 30;
        self.floatingButton.clipsToBounds = YES;
        [self.floatingButton addTarget:self action:@selector(toggleInfo) forControlEvents:UIControlEventTouchUpInside];
        self.floatingButton.windowLevel = UIWindowLevelAlert + 1;
    
        // Find the key window and add the button
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            [keyWindow addSubview:self.floatingButton];
        }
    }
    
    - (void)toggleInfo {
        if (self.infoWindow) {
            [self hideInfo];
        } else {
            [self showInfo];
        }
    }
    
    - (void)showInfo {
        CPUInfo *cpuInfo = getCPUInfo();
        MemoryInfo *memInfo = getMemoryInfo();
    
        self.infoWindow = [[UIWindow alloc] initWithFrame:CGRectMake(80, 80, 250, 200)];
        self.infoWindow.windowLevel = UIWindowLevelAlert;
        self.infoWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
        self.infoWindow.layer.cornerRadius = 10;
        self.infoWindow.clipsToBounds = YES;
    
        UILabel *cpuLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 230, 80)];
        cpuLabel.numberOfLines = 0;
        cpuLabel.textColor = [UIColor whiteColor];
        cpuLabel.font = [UIFont systemFontOfSize:14];
        cpuLabel.text = [NSString stringWithFormat:@"Model: %s\nBrand: %s\nCores: %u\nThreads: %u", cpuInfo->model, cpuInfo->cpuBrand, cpuInfo->coreCount, cpuInfo->threadCount];
        [self.infoWindow addSubview:cpuLabel];
    
        UILabel *memLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 100, 230, 80)];
        memLabel.numberOfLines = 0;
        memLabel.textColor = [UIColor whiteColor];
        memLabel.font = [UIFont systemFontOfSize:14];
        memLabel.text = [NSString stringWithFormat:@"Total Memory: %llu bytes\nFree Memory: %llu bytes", memInfo->totalMemory, memInfo->freeMemory];
        [self.infoWindow addSubview:memLabel];
    
        [self.infoWindow makeKeyAndVisible];
    
        freeCPUInfo(cpuInfo);
        freeMemoryInfo(memInfo);
    }
    
    - (void)hideInfo {
        [self.infoWindow removeFromSuperview];
        self.infoWindow = nil;
    }
    
    @end