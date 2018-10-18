//
//  CDNMachThreadBacktrace.h
//  CDNPerformanceMonitor
//
//  Created by 陈栋楠 on 2018/10/13.
//  Copyright © 2018 陈栋楠. All rights reserved.
//

#ifndef CDNMachThreadBacktrace_h
#define CDNMachThreadBacktrace_h

#include <stdio.h>
#import <mach/mach.h>


/**
 *  fill a backtrace call stack array of given thread
 *
 *  @param thread   mach thread for tracing
 *  @param stack    caller space for saving stack trace info
 *  @param maxCount max stack array count
 *
 *  @return call stack address array
 */



int sxd_backtraceForMachThread(thread_t thread, void ** stack,int maxCount);

#endif /* CDNMachThreadBacktrace_h */
