//
//  CDNPerformanceMonitor.m
//  CDNPerformanceMonitor
//
//  Created by 陈栋楠 on 2018/10/13.
//  Copyright © 2018 陈栋楠. All rights reserved.
//

#import "CDNPerformanceMonitor.h"
#import <libkern/OSAtomic.h>
#import <execinfo.h>

#include <stdio.h>
#include <stdlib.h>
#include <execinfo.h>
#import <UIKit/UIKit.h>

#import "CDNMachThreadBacktrace.h"
#import "UIDevice+afm_Hardware.h"

static NSString *const CDNPerformanceLogFilesDirectory = @"CDNPerformanceLogFilesDirectory";

dispatch_queue_t cdn_performance_monitor_queue() {
    static dispatch_queue_t cdn_performance_monitor_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cdn_performance_monitor_queue = dispatch_queue_create("com.chendongnan.cdn_performance_monitor_queue", NULL);
    });
    return cdn_performance_monitor_queue;
}

dispatch_queue_t cdn_performance_monitor_logs_queue() {
    static dispatch_queue_t cdn_performance_monitor_logs_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cdn_performance_monitor_logs_queue = dispatch_queue_create("com.chendongnan.cdn_performance_monitor_logs_queue", NULL);
    });
    return cdn_performance_monitor_logs_queue;
}

@interface CDNPerformanceMonitorLogsFileManager : NSObject

+ (NSString *)logsDirectory;

+ (NSString *)timeStamp;

+ (NSString *)logFileName;

+ (void)writeLogsToLogDirectory:(NSString *)logs;


@end

@implementation CDNPerformanceMonitorLogsFileManager

/** log存放文件夹 */
+ (NSString *)logsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *logsDirectory = [documentsDirectory stringByAppendingPathComponent:CDNPerformanceLogFilesDirectory];
     NSFileManager* fileManager = [NSFileManager defaultManager];
     // 该用户的目录是否存在，若不存在则创建相应的目录
    BOOL isDirectory = NO;
    BOOL isExisting = [fileManager fileExistsAtPath:logsDirectory isDirectory:&isDirectory];
    
    if (!(isExisting && isDirectory)) {
        BOOL createDirectory = [fileManager createDirectoryAtPath:logsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        if (!createDirectory) {
            NSLog(@"卡顿i监控log文件目录创建失败");
        }
    }
    return logsDirectory;
}

+ (void)writeLogsToLogDirectory:(NSString *)logs {
    dispatch_async(cdn_performance_monitor_queue(), ^{
        NSData *logsData = [logs dataUsingEncoding:NSUTF8StringEncoding];
        if (logsData) {
            NSString *logFileName = [CDNPerformanceMonitorLogsFileManager logFileName];
            NSString *filePath = [[CDNPerformanceMonitorLogsFileManager logsDirectory] stringByAppendingString:logFileName];
            BOOL result = [logsData writeToFile:filePath atomically:YES];
            if (result != YES) {
                NSLog(@"%s : 保存卡顿日志失败",__FUNCTION__);
            }
        }
    });
}

@end

@interface CDNPerformanceMonitor () {
@private
    NSInteger _timeoutCount;
    CFRunLoopObserverRef _runLoopObserver;
}

@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, assign) CFRunLoopActivity runLoopActivity;

@end

@implementation CDNPerformanceMonitor

static void runLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void* info) {
    CDNPerformanceMonitor *performanceMonitor = (__bridge CDNPerformanceMonitor *)info;
    performanceMonitor.runLoopActivity = activity;
    dispatch_semaphore_signal(performanceMonitor.semaphore);
}

-(void)dealloc {
    [self stopMonitoring];
}

- (instancetype)init {
    if (self = [super init]) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.logsEnabled = YES;
}

#pragma mark - Public Methods

+ (instancetype)sharedInstance {
    static id __sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __sharedInstance = [[[self class] alloc] init];
    });
    return __sharedInstance;
}

- (void)stopMonitoring {
    if (!_runLoopObserver) {
        return;
    }
    CFRunLoopRemoveObserver(CFRunLoopGetMain(), _runLoopObserver, kCFRunLoopCommonModes);
    CFRelease(_runLoopObserver);
    _runLoopObserver = NULL;
}

- (void)startMonitoring {
    if (_runLoopObserver) {
        return;
    }
    
    self.semaphore = dispatch_semaphore_create(0);
    // 注册RunLoop的状态监听
    /*
     typedef struct {
     CFIndex    version;
     void *    info;
     const void *(*retain)(const void *info);
     void    (*release)(const void *info);
     CFStringRef    (*copyDescription)(const void *info);
     } CFRunLoopObserverContext;
     */
    
    CFRunLoopObserverContext context = {
        0,
        (__bridge void*)self,
        NULL,
        NULL
    };
    
    _runLoopObserver = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopAllActivities, YES, 0, &runLoopObserverCallBack, &context);
    
    CFRunLoopAddObserver(CFRunLoopGetMain(), _runLoopObserver, kCFRunLoopCommonModes);
    
    //在子线程监控时长
    dispatch_async(cdn_performance_monitor_queue(), ^{
        while (YES) {
            //假设连续5次超时100ms认为卡顿（或者单次超时500ms）
            long st = dispatch_semaphore_wait(self.semaphore, dispatch_time(DISPATCH_TIME_NOW, 500 *NSEC_PER_MSEC));
            if (st != 0) {
                if (!_runLoopObserver) {
                    _timeoutCount = 0;
                    self.semaphore = 0;
                    self.runLoopActivity = 0;
                    return;
                }
                
                if (self.runLoopActivity == kCFRunLoopBeforeSources || self.runLoopActivity == kCFRunLoopAfterWaiting) {
                    if (++_timeoutCount < 5) {
                        continue;
                    }
                    [self handleCallbacksStackForMainThreadStucked];
                }
            }
            _timeoutCount = 0;
        }
    });
    
}


#pragma mark  - privateMethods
- (void)handleCallbacksStackForMainThreadStucked {
    NSString *backtraceLogs = [self formatBacktraceLogsForAllThreads];
    [CDNPerformanceMonitorLogsFileManager writeLogsToLogDirectory:backtraceLogs];
}


- (NSString *)formatBacktraceLogsForAllThreads {
    //1.获取所有线程
    mach_msg_type_number_t threadCount;
    thread_act_array_t threadList;
    kern_return_t kret;
    
    kret = task_threads(mach_task_self(), &threadList, &threadCount);
    if (kret != KERN_SUCCESS) {
        if (self.logsEnabled) {
            NSLog(@"获取线程列表失败: %s\n",mach_error_string(kret));
        }
        //获取线程列表失败，运行中的线程的调用栈将不精确，没有收集的必要，直接返回空
        return nil;
    }
    //2. 挂起所有线程，保证call stack信息的精确性
    thread_t selfThread = mach_task_self();
    for (int i = 0; i < threadCount; ++i) {
        if (threadList[i] != selfThread) {
            thread_suspend(threadList[i]);
        }
    }
    //3.获取所有线程的backtrace信息
    NSMutableArray *backTracesArray = [NSMutableArray array];
    for (int i = 0; i < threadCount; ++i) {
        thread_t temThread = threadList[i];
        NSString *backTrace = [self formatBacktraceForThread:temThread];
        if (backTrace) {
            [backTracesArray addObject:backTrace];
        }
    }
    
    //4.激活被挂起的线程
    for (int i = 0; i < threadCount; ++i) {
        thread_resume(threadList[i]);
    }
    
    //5. 格式化输出backtrace log信息,写入日志文件
    NSMutableString *logs = nil;
    if (backTracesArray.count) {
        NSString *timeStamp = [CDNPerformanceMonitorLogsFileManager timeStamp];
        logs = [[NSMutableString alloc] initWithCapacity:0];
        [logs appendFormat:@"\n**********************\n"];
        [logs appendFormat:@"Time: %@\n", timeStamp];
        UIDevice *device = [UIDevice currentDevice];
        [logs appendFormat:@"Device : %@, %@\n\n", device.platformString, device.systemVersion];
        for(NSInteger idx = 0; idx < backTracesArray.count; idx++) {
            [logs appendFormat:@"%@", backTracesArray[idx]];
            [logs appendFormat:@"\n\n\n"];
        }
        [logs appendFormat:@"\n**************************************\n\n\n"];
    }
    if (self.logsEnabled) {
        NSLog(@"%@", logs);
    }
    
    return logs;
}

- (NSString * _Nonnull)formatBacktraceForThread:(thread_t)thread {
    int const maxStackDepth = 128;
    
    void **backtraceStack = calloc(maxStackDepth, sizeof(void *));
    int backtraceCount = sxd_backtraceForMachThread(thread, backtraceStack, maxStackDepth);
    char **backtraceStackSymbols = backtrace_symbols(backtraceStack, backtraceCount);
    
    NSMutableString *stackTrace = [NSMutableString string];
    for (int i = 0; i < backtraceCount; ++i) {
        char *currentStackInfo = backtraceStackSymbols[i];
        [stackTrace appendString:[NSString stringWithUTF8String:currentStackInfo]];
        [stackTrace appendFormat:@"\n"];
    }
    return stackTrace;
}

@end
