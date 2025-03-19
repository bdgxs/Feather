// Tweak.xm

    #import <UIKit/UIKit.h>
    #import "cpux_lib.h"

    static UIWindow *infoWindow = nil;
    static UIButton *floatingButton = nil;

    %hook UIWindow

    - (void)makeKeyAndVisible {
        %orig;

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [self setupFloatingButton];
        });
    }

    - (void)setupFloatingButton {
        floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
        floatingButton.frame = CGRectMake(20, 60, 60, 60);
        [floatingButton setTitle:@"Info" forState:UIControlStateNormal];
        floatingButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
        floatingButton.layer.cornerRadius = 30;
        floatingButton.clipsToBounds = YES;
        [floatingButton addTarget:self action:@selector(toggleInfo) forControlEvents:UIControlEventTouchUpInside];
        floatingButton.windowLevel = UIWindowLevelAlert + 1;

        // Find the key window and add the button
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            [keyWindow addSubview:floatingButton];
        }
    }

    - (void)toggleInfo {
        if (infoWindow) {
            [self hideInfo];
        } else {
            [self showInfo];
        }
    }

    - (void)showInfo {
        CPUInfo *cpuInfo = getCPUInfo();
        MemoryInfo *memInfo = getMemoryInfo();

        infoWindow = [[UIWindow alloc] initWithFrame:CGRectMake(80, 80, 250, 200)];
        infoWindow.windowLevel = UIWindowLevelAlert;
        infoWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.8];
        infoWindow.layer.cornerRadius = 10;
        infoWindow.clipsToBounds = YES;

        UILabel *cpuLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 230, 80)];
        cpuLabel.numberOfLines = 0;
        cpuLabel.textColor = [UIColor whiteColor];
        cpuLabel.font = [UIFont systemFontOfSize:14];
        cpuLabel.text = [NSString stringWithFormat:@"Model: %s\nBrand: %s\nCores: %u\nThreads: %u", cpuInfo->model, cpuInfo->cpuBrand, cpuInfo->coreCount, cpuInfo->threadCount];
        [infoWindow addSubview:cpuLabel];

        UILabel *memLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 100, 230, 80)];
        memLabel.numberOfLines = 0;
        memLabel.textColor = [UIColor whiteColor];
        memLabel.font = [UIFont systemFontOfSize:14];
        memLabel.text = [NSString stringWithFormat:@"Total Memory: %llu bytes\nFree Memory: %llu bytes", memInfo->totalMemory, memInfo->freeMemory];
        [infoWindow addSubview:memLabel];

        [infoWindow makeKeyAndVisible];

        freeCPUInfo(cpuInfo);
        freeMemoryInfo(memInfo);
    }

    - (void)hideInfo {
        [infoWindow removeFromSuperview];
        infoWindow = nil;
    }

    %end