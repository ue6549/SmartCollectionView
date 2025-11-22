#import "SmartCollectionViewReusePool.h"

// Enable metrics tracking (set to 1 to enable, 0 to disable)
// Metrics are enabled by default in DEBUG builds
#ifndef SCV_ENABLE_METRICS
#ifdef DEBUG
#define SCV_ENABLE_METRICS 1
#else
#define SCV_ENABLE_METRICS 0
#endif
#endif

@interface SmartCollectionViewReusePool ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<UIView *> *> *poolsByType;

#if SCV_ENABLE_METRICS
// Metrics for testing/debugging (only compiled if SCV_ENABLE_METRICS is 1)
@property (nonatomic, assign) NSInteger totalEnqueues;
@property (nonatomic, assign) NSInteger totalDequeues;
@property (nonatomic, assign) NSInteger successfulDequeues; // Dequeue returned a view (hit)
@property (nonatomic, assign) NSInteger failedDequeues; // Dequeue returned nil (miss)
@property (nonatomic, assign) NSInteger viewsCreated; // Track if we can infer this (not directly tracked, but can be calculated)
@property (nonatomic, assign) NSInteger lastStatsLogDequeueCount; // Track when to log stats periodically
@property (nonatomic, assign) NSInteger lastStatsLogEnqueueCount; // Track when to log stats periodically on enqueue
#endif

// Helper method to log statistics
- (void)logPoolStatistics;

@end

@implementation SmartCollectionViewReusePool

- (instancetype)init {
    self = [super init];
    if (self) {
        _poolsByType = [NSMutableDictionary dictionary];
#if SCV_ENABLE_METRICS
        _totalEnqueues = 0;
        _totalDequeues = 0;
        _successfulDequeues = 0;
        _failedDequeues = 0;
        _viewsCreated = 0;
        _lastStatsLogDequeueCount = 0;
        _lastStatsLogEnqueueCount = 0;
#endif
        SCVReusePoolLog(@"Initialized reuse pool");
    }
    return self;
}

- (void)enqueueView:(UIView *)view forItemType:(NSString *)itemType {
    if (!view || !itemType) {
        SCVReusePoolLog(@"Cannot enqueue: view or itemType is nil");
        return;
    }
    
    // Remove view from its current superview if it has one
    if (view.superview) {
        [view removeFromSuperview];
    }
    
    // Get or create pool for this type
    NSMutableArray<UIView *> *pool = _poolsByType[itemType];
    if (!pool) {
        pool = [NSMutableArray array];
        _poolsByType[itemType] = pool;
    }
    
    // Add to pool
    [pool addObject:view];
    
#if SCV_ENABLE_METRICS
    _totalEnqueues++;
    SCVReusePoolLog(@"Enqueued view for type '%@' (pool size: %ld, total enqueues: %ld)", itemType, (long)pool.count, (long)_totalEnqueues);
    
    // Log stats periodically (every 20 enqueues)
    if (_totalEnqueues % 20 == 0 || _totalEnqueues - _lastStatsLogEnqueueCount >= 20) {
        [self logPoolStatistics];
        _lastStatsLogEnqueueCount = _totalEnqueues;
    }
#else
    SCVReusePoolLog(@"Enqueued view for type '%@' (pool size: %ld)", itemType, (long)pool.count);
#endif
}

- (UIView *)dequeueViewForItemType:(NSString *)itemType {
    if (!itemType) {
        SCVReusePoolLog(@"Cannot dequeue: itemType is nil");
        return nil;
    }
    
#if SCV_ENABLE_METRICS
    _totalDequeues++;
#endif
    
    NSMutableArray<UIView *> *pool = _poolsByType[itemType];
    if (!pool || pool.count == 0) {
#if SCV_ENABLE_METRICS
        _failedDequeues++;
        SCVReusePoolLog(@"No view available for type '%@' (miss, total misses: %ld)", itemType, (long)_failedDequeues);
        // Log stats on miss (important event)
        [self logPoolStatistics];
#else
        SCVReusePoolLog(@"No view available for type '%@'", itemType);
#endif
        return nil;
    }
    
    // Remove and return the first view from the pool
    UIView *view = pool.firstObject;
    [pool removeObjectAtIndex:0];
    
#if SCV_ENABLE_METRICS
    _successfulDequeues++;
    SCVReusePoolLog(@"Dequeued view for type '%@' (hit, remaining in pool: %ld, total hits: %ld)", itemType, (long)pool.count, (long)_successfulDequeues);
    
    // Log stats periodically (every 10 dequeues) to track reuse behavior
    if (_totalDequeues % 10 == 0 || _totalDequeues - _lastStatsLogDequeueCount >= 10) {
        [self logPoolStatistics];
        _lastStatsLogDequeueCount = _totalDequeues;
    }
#else
    SCVReusePoolLog(@"Dequeued view for type '%@' (remaining in pool: %ld)", itemType, (long)pool.count);
#endif
    
    return view;
}

- (void)clear {
    NSInteger totalViews = [self poolSize];
    [_poolsByType removeAllObjects];
    SCVReusePoolLog(@"Cleared reuse pool (removed %ld views)", (long)totalViews);
}

- (NSInteger)poolSize {
    NSInteger total = 0;
    for (NSMutableArray<UIView *> *pool in _poolsByType.allValues) {
        total += pool.count;
    }
    return total;
}

- (NSInteger)poolSizeForItemType:(NSString *)itemType {
    if (!itemType) {
        return 0;
    }
    
    NSMutableArray<UIView *> *pool = _poolsByType[itemType];
    return pool ? pool.count : 0;
}

- (NSDictionary<NSString *, id> *)poolStatistics {
    NSMutableDictionary<NSString *, id> *stats = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *byType = [NSMutableDictionary dictionary];
    
    for (NSString *itemType in _poolsByType.allKeys) {
        NSInteger count = [self poolSizeForItemType:itemType];
        byType[itemType] = @(count);
    }
    
    stats[@"byType"] = [byType copy];
    stats[@"total"] = @([self poolSize]);
    stats[@"typeCount"] = @(_poolsByType.count);
    
#if SCV_ENABLE_METRICS
    // Metrics (only included if SCV_ENABLE_METRICS is 1)
    stats[@"totalEnqueues"] = @(_totalEnqueues);
    stats[@"totalDequeues"] = @(_totalDequeues);
    stats[@"successfulDequeues"] = @(_successfulDequeues);
    stats[@"failedDequeues"] = @(_failedDequeues);
    
    // Calculate hit rate
    CGFloat hitRate = _totalDequeues > 0 ? (CGFloat)_successfulDequeues / (CGFloat)_totalDequeues : 0.0;
    stats[@"hitRate"] = @(hitRate);
    stats[@"hitRatePercent"] = @(hitRate * 100.0);
    
    // Estimate views created (total dequeues - successful dequeues = views that had to be created)
    // This is an approximation since we don't track creation directly
    NSInteger estimatedViewsCreated = _totalDequeues - _successfulDequeues;
    stats[@"estimatedViewsCreated"] = @(estimatedViewsCreated);
#else
    // Metrics disabled
    stats[@"metricsEnabled"] = @NO;
#endif
    
    return [stats copy];
}

- (void)logPoolStatistics {
    NSDictionary<NSString *, id> *stats = [self poolStatistics];
    
#if SCV_ENABLE_METRICS
    NSInteger total = [stats[@"total"] integerValue];
    NSInteger totalEnqueues = [stats[@"totalEnqueues"] integerValue];
    NSInteger totalDequeues = [stats[@"totalDequeues"] integerValue];
    NSInteger successfulDequeues = [stats[@"successfulDequeues"] integerValue];
    NSInteger failedDequeues = [stats[@"failedDequeues"] integerValue];
    CGFloat hitRatePercent = [stats[@"hitRatePercent"] doubleValue];
    NSInteger estimatedViewsCreated = [stats[@"estimatedViewsCreated"] integerValue];
    
    NSDictionary<NSString *, NSNumber *> *byType = stats[@"byType"];
    NSMutableString *byTypeStr = [NSMutableString string];
    for (NSString *type in byType.allKeys) {
        [byTypeStr appendFormat:@"%@:%ld ", type, (long)[byType[type] integerValue]];
    }
    
    SCVReusePoolLog(@"📊 Pool Statistics: total=%ld, enqueues=%ld, dequeues=%ld, hits=%ld, misses=%ld, hitRate=%.1f%%, estimatedCreated=%ld, byType={%@}",
                     (long)total, (long)totalEnqueues, (long)totalDequeues, (long)successfulDequeues,
                     (long)failedDequeues, hitRatePercent, (long)estimatedViewsCreated, byTypeStr);
#else
    NSInteger total = [stats[@"total"] integerValue];
    NSDictionary<NSString *, NSNumber *> *byType = stats[@"byType"];
    NSMutableString *byTypeStr = [NSMutableString string];
    for (NSString *type in byType.allKeys) {
        [byTypeStr appendFormat:@"%@:%ld ", type, (long)[byType[type] integerValue]];
    }
    SCVReusePoolLog(@"📊 Pool Statistics: total=%ld, byType={%@}", (long)total, byTypeStr);
#endif
}

#if SCV_ENABLE_METRICS
- (void)resetMetrics {
    _totalEnqueues = 0;
    _totalDequeues = 0;
    _successfulDequeues = 0;
    _failedDequeues = 0;
    _viewsCreated = 0;
    _lastStatsLogDequeueCount = 0;
    _lastStatsLogEnqueueCount = 0;
    SCVReusePoolLog(@"Reset all metrics");
}
#else
- (void)resetMetrics {
    // No-op when metrics are disabled
    SCVReusePoolLog(@"resetMetrics called but metrics are disabled");
}
#endif

@end

