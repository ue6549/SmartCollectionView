#import "SmartCollectionViewReusePool.h"
#import <React/RCTLog.h>

#ifdef DEBUG
//#define SCVReusePoolLog(fmt, ...) RCTLogInfo(@"[SCV-ReusePool] " fmt, ##__VA_ARGS__)
#define SCVReusePoolLog(fmt, ...)
#else
#define SCVReusePoolLog(fmt, ...)
#endif

@interface SmartCollectionViewReusePool ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<UIView *> *> *poolsByType;

@end

@implementation SmartCollectionViewReusePool

- (instancetype)init {
    self = [super init];
    if (self) {
        _poolsByType = [NSMutableDictionary dictionary];
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
    
    SCVReusePoolLog(@"Enqueued view for type '%@' (pool size: %ld)", itemType, (long)pool.count);
}

- (UIView *)dequeueViewForItemType:(NSString *)itemType {
    if (!itemType) {
        SCVReusePoolLog(@"Cannot dequeue: itemType is nil");
        return nil;
    }
    
    NSMutableArray<UIView *> *pool = _poolsByType[itemType];
    if (!pool || pool.count == 0) {
        SCVReusePoolLog(@"No view available for type '%@'", itemType);
        return nil;
    }
    
    // Remove and return the first view from the pool
    UIView *view = pool.firstObject;
    [pool removeObjectAtIndex:0];
    
    SCVReusePoolLog(@"Dequeued view for type '%@' (remaining in pool: %ld)", itemType, (long)pool.count);
    
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

@end

