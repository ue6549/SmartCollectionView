#import "SmartCollectionViewEventBus.h"
#import "SmartCollectionView.h"
#import <QuartzCore/QuartzCore.h>

static const NSTimeInterval kDefaultScrollThrottleMs = 16.0;   // ~60fps
static const NSTimeInterval kDefaultRangeThrottleMs = 120.0;    // coarse updates

@interface SmartCollectionViewEventBus ()

@property (nonatomic, weak, readwrite) SmartCollectionView *owner;
@property (nonatomic, assign) NSTimeInterval lastScrollDispatch;
@property (nonatomic, assign) NSTimeInterval lastRangeDispatch;
@property (nonatomic, assign) BOOL scrollDispatchScheduled;
@property (nonatomic, assign) BOOL rangeDispatchScheduled;
@property (nonatomic, strong) NSDictionary *pendingScrollPayload;
@property (nonatomic, strong) NSDictionary *pendingRangePayload;

@end

@implementation SmartCollectionViewEventBus

- (instancetype)initWithOwner:(SmartCollectionView *)owner
{
    NSParameterAssert(owner != nil);
    self = [super init];
    if (self) {
        _owner = owner;
        _scrollEventThrottle = kDefaultScrollThrottleMs;
        _rangeEventThrottle = kDefaultRangeThrottleMs;
        _lastScrollDispatch = 0;
        _lastRangeDispatch = 0;
        _scrollDispatchScheduled = NO;
        _rangeDispatchScheduled = NO;
    }
    return self;
}

#pragma mark - Public API

- (void)emitScrollWithOffset:(CGPoint)offset
                    velocity:(CGPoint)velocity
                     content:(CGSize)contentSize
                     visible:(CGSize)visibleSize
{
    if (!self.owner.onScroll) {
        self.lastScrollDispatch = CACurrentMediaTime();
        return;
    }

    self.pendingScrollPayload = @{
        @"contentOffset": @{ @"x": @(offset.x), @"y": @(offset.y) },
        @"velocity": @{ @"x": @(velocity.x), @"y": @(velocity.y) },
        @"contentSize": @{ @"width": @(contentSize.width), @"height": @(contentSize.height) },
        @"layoutMeasurement": @{ @"width": @(visibleSize.width), @"height": @(visibleSize.height) }
    };

    NSTimeInterval now = CACurrentMediaTime();
    NSTimeInterval throttleSeconds = MAX(self.scrollEventThrottle, 0.0) / 1000.0;
    if (throttleSeconds <= 0 || (self.lastScrollDispatch == 0) || (now - self.lastScrollDispatch >= throttleSeconds)) {
        [self dispatchScrollPayload];
    } else if (!self.scrollDispatchScheduled) {
        self.scrollDispatchScheduled = YES;
        NSTimeInterval delay = throttleSeconds - (now - self.lastScrollDispatch);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.scrollDispatchScheduled = NO;
            [self dispatchScrollPayload];
        });
    }
}

- (void)emitVisibleRange:(NSRange)range
{
    if (!self.owner.onVisibleRangeChange) {
        self.lastRangeDispatch = CACurrentMediaTime();
        return;
    }

    NSUInteger lastIndex = (range.length == 0) ? range.location : (NSMaxRange(range) - 1);
    self.pendingRangePayload = @{
        @"first": @(range.location),
        @"last": @(lastIndex)
    };

    NSTimeInterval now = CACurrentMediaTime();
    NSTimeInterval throttleSeconds = MAX(self.rangeEventThrottle, 0.0) / 1000.0;
    if (throttleSeconds <= 0 || (self.lastRangeDispatch == 0) || (now - self.lastRangeDispatch >= throttleSeconds)) {
        [self dispatchRangePayload];
    } else if (!self.rangeDispatchScheduled) {
        self.rangeDispatchScheduled = YES;
        NSTimeInterval delay = throttleSeconds - (now - self.lastRangeDispatch);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.rangeDispatchScheduled = NO;
            [self dispatchRangePayload];
        });
    }
}

- (void)emitRequestItems:(NSArray<NSNumber *> *)indices
{
    if (!self.owner.onRequestItems || indices.count == 0) {
        return;
    }

    self.owner.onRequestItems(@{ @"indices": indices });
}

- (void)emitScrollBeginDrag
{
    if (self.owner.onScrollBeginDrag) {
        self.owner.onScrollBeginDrag([self baseScrollPayload]);
    }
}

- (void)emitScrollEndDrag
{
    if (self.owner.onScrollEndDrag) {
        self.owner.onScrollEndDrag([self baseScrollPayload]);
    }
}

- (void)emitMomentumScrollBegin
{
    if (self.owner.onMomentumScrollBegin) {
        self.owner.onMomentumScrollBegin([self baseScrollPayload]);
    }
}

- (void)emitMomentumScrollEnd
{
    if (self.owner.onMomentumScrollEnd) {
        self.owner.onMomentumScrollEnd([self baseScrollPayload]);
    }
}

- (void)emitScrollEndDecelerating
{
    if (self.owner.onScrollEndDecelerating) {
        self.owner.onScrollEndDecelerating([self baseScrollPayload]);
    }
}

#pragma mark - Helpers

- (NSDictionary *)baseScrollPayload
{
    UIScrollView *scrollView = self.owner.scrollView;
    if (!scrollView) {
        return @{};
    }

    return @{
        @"contentOffset": @{ @"x": @(scrollView.contentOffset.x), @"y": @(scrollView.contentOffset.y) },
        @"contentSize": @{ @"width": @(scrollView.contentSize.width), @"height": @(scrollView.contentSize.height) },
        @"layoutMeasurement": @{ @"width": @(scrollView.bounds.size.width), @"height": @(scrollView.bounds.size.height) }
    };
}

- (void)dispatchScrollPayload
{
    if (!self.owner.onScroll || !self.pendingScrollPayload) {
        return;
    }
    self.lastScrollDispatch = CACurrentMediaTime();
    self.owner.onScroll(self.pendingScrollPayload);
}

- (void)dispatchRangePayload
{
    if (!self.owner.onVisibleRangeChange || !self.pendingRangePayload) {
        return;
    }
    self.lastRangeDispatch = CACurrentMediaTime();
    self.owner.onVisibleRangeChange(self.pendingRangePayload);
}

@end
