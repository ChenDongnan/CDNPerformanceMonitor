//
//  CDNPerformanceMonitor.h
//  CDNPerformanceMonitor
//
//  Created by 陈栋楠 on 2018/10/13.
//  Copyright © 2018 陈栋楠. All rights reserved.
//  基于NSRunloop监听主线程卡顿的工具类

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDNPerformanceMonitor : NSObject
@property (nonatomic, assign) BOOL logsEnabled;

+ (instancetype)sharedInstance;

/** 开启监听 */
- (void)startMonitoring;

/** 停止监听 */
- (void)stopMonitoring;
@end

NS_ASSUME_NONNULL_END
