#import "SmartCollectionViewScheduler.h"
#import "SmartCollectionView.h"
#import "SmartCollectionViewLayoutCache.h"
#import "SmartCollectionViewLayoutSpec.h"
#import "SmartCollectionViewVisibilityTracker.h"
#import "SmartCollectionViewMountController.h"
#import "SmartCollectionViewEventBus.h"

@interface SmartCollectionViewScheduler ()

@property (nonatomic, weak, readwrite) SmartCollectionView *owner;
@property (nonatomic, strong, readwrite) SmartCollectionViewLayoutCache *layoutCache;
@property (nonatomic, strong, readwrite) SmartCollectionViewVisibilityTracker *visibilityTracker;
@property (nonatomic, strong, readwrite) SmartCollectionViewMountController *mountController;
@property (nonatomic, strong, readwrite) SmartCollectionViewEventBus *eventBus;

@property (nonatomic, copy) NSArray<NSNumber *> *cumulativeOffsets;
@property (nonatomic, strong) NSSet<NSNumber *> *renderedIndices;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *pendingRequestedIndices;

@end

@interface SmartCollectionView (SchedulerAccess)
- (NSInteger)itemCount;
- (CGSize)sizeForItemAtIndex:(NSInteger)index;
- (BOOL)hasRenderedItemAtIndex:(NSInteger)index;
@end

@implementation SmartCollectionViewScheduler

- (instancetype)initWithOwner:(SmartCollectionView *)owner
                  layoutCache:(SmartCollectionViewLayoutCache *)layoutCache
           visibilityTracker:(SmartCollectionViewVisibilityTracker *)visibilityTracker
             mountController:(SmartCollectionViewMountController *)mountController
                    eventBus:(SmartCollectionViewEventBus *)eventBus
{
    NSParameterAssert(owner);
    NSParameterAssert(layoutCache);
    NSParameterAssert(visibilityTracker);
    NSParameterAssert(mountController);
    NSParameterAssert(eventBus);

    self = [super init];
    if (self) {
        _owner = owner;
        _layoutCache = layoutCache;
        _visibilityTracker = visibilityTracker;
        _mountController = mountController;
        _eventBus = eventBus;
        _cumulativeOffsets = @[];
        _renderedIndices = [NSSet set];
        _pendingRequestedIndices = [NSMutableSet set];
        _initialNumToRender = 10;
        _maxToRenderPerBatch = 10;
        _overscanCount = 5;
        _overscanLength = 0;
        _shadowBufferMultiplier = 2.0; // Default: request 2x the mount range
        _horizontal = YES;
        _scrollOffset = CGPointZero;
        _viewportSize = CGSizeZero;
        _totalItemCount = 0;
    }
    return self;
}

- (void)updateCumulativeOffsets:(NSArray<NSNumber *> *)offsets
{
    self.cumulativeOffsets = offsets ?: @[];
}

- (void)updateRenderedIndices:(NSSet<NSNumber *> *)renderedIndices
{
    self.renderedIndices = renderedIndices ?: [NSSet set];
    // Clear from pending any indices that are now rendered
    if (renderedIndices.count > 0) {
        for (NSNumber *idx in renderedIndices) {
            [self.pendingRequestedIndices removeObject:idx];
        }
    }
}

- (void)notifyLayoutRecomputed
{
    // Placeholder for future scheduler logic (eviction, diffing, etc.)
}

- (NSRange)visibleRange
{
    NSInteger itemCount = [self.owner itemCount];
    if (itemCount <= 0) {
        return NSMakeRange(0, 0);
    }

    BOOL horizontal = self.isHorizontal;
    CGFloat viewportLength = horizontal ? self.viewportSize.width : self.viewportSize.height;
    if (viewportLength <= 0) {
        // Fallback to initial window when bounds are not established yet
        NSInteger length = MIN(5, itemCount);
        return NSMakeRange(0, length);
    }

    CGFloat startOffset = horizontal ? self.scrollOffset.x : self.scrollOffset.y;
    CGFloat endOffset = startOffset + viewportLength;

    NSInteger startIndex = 0;
    NSInteger endIndex = itemCount;

    // Binary search for start index using cumulative offsets if available
    if (self.cumulativeOffsets.count == itemCount) {
        NSInteger left = 0;
        NSInteger right = itemCount - 1;
        while (left <= right) {
            NSInteger mid = (left + right) / 2;
            CGFloat offset = [self.cumulativeOffsets[mid] doubleValue];
            if (offset < startOffset) {
                left = mid + 1;
            } else {
                right = mid - 1;
            }
        }
        startIndex = MAX(0, MIN(left, itemCount - 1));

        // Search for end index (first item whose start >= endOffset)
        left = startIndex;
        right = itemCount - 1;
        while (left <= right) {
            NSInteger mid = (left + right) / 2;
            CGFloat offset = [self.cumulativeOffsets[mid] doubleValue];
            if (offset < endOffset) {
                left = mid + 1;
            } else {
                right = mid - 1;
            }
        }
        endIndex = MAX(startIndex, MIN(left, itemCount));

        // Ensure items actually intersect viewport
        if (endIndex > startIndex) {
            NSInteger intersectLeft = startIndex;
            NSInteger intersectRight = endIndex - 1;
            NSInteger lastIntersectingIndex = startIndex - 1;
            while (intersectLeft <= intersectRight) {
                NSInteger mid = (intersectLeft + intersectRight) / 2;
                CGFloat itemStart = [self.cumulativeOffsets[mid] doubleValue];
                CGSize itemSize = [self.owner sizeForItemAtIndex:mid];
                CGFloat itemEnd = itemStart + (horizontal ? itemSize.width : itemSize.height);
                if (itemEnd > startOffset) {
                    lastIntersectingIndex = mid;
                    intersectLeft = mid + 1;
                } else {
                    intersectRight = mid - 1;
                }
            }
            if (lastIntersectingIndex >= startIndex) {
                endIndex = lastIntersectingIndex + 1;
            } else {
                endIndex = startIndex;
            }
        }
    } else {
        // Fallback: linear scan using layout cache if cumulative offsets are not available
        NSInteger firstCandidate = 0;
        NSInteger lastCandidate = itemCount - 1;
        for (NSInteger i = 0; i < itemCount; i++) {
            SmartCollectionViewLayoutSpec *spec = [self.layoutCache specForIndex:i];
            CGRect frame = spec ? spec.frame : CGRectZero;
            CGFloat itemStart = horizontal ? CGRectGetMinX(frame) : CGRectGetMinY(frame);
            CGFloat itemEnd = horizontal ? CGRectGetMaxX(frame) : CGRectGetMaxY(frame);
            if (itemEnd > startOffset) {
                firstCandidate = i;
                break;
            }
        }
        for (NSInteger i = firstCandidate; i < itemCount; i++) {
            SmartCollectionViewLayoutSpec *spec = [self.layoutCache specForIndex:i];
            CGRect frame = spec ? spec.frame : CGRectZero;
            CGFloat itemStart = horizontal ? CGRectGetMinX(frame) : CGRectGetMinY(frame);
            if (itemStart >= endOffset) {
                lastCandidate = MAX(firstCandidate, i - 1);
                break;
            }
        }
        startIndex = firstCandidate;
        endIndex = MIN(itemCount, lastCandidate + 1);
    }

    if (startIndex >= endIndex) {
        startIndex = MAX(0, MIN(startIndex, itemCount - 1));
        endIndex = startIndex;
    }

    return NSMakeRange(startIndex, endIndex - startIndex);
}

- (NSRange)rangeToMount
{
    NSRange visibleRange = [self visibleRange];
    NSInteger itemCount = [self.owner itemCount];
    if (visibleRange.length == 0 || itemCount == 0) {
        return NSMakeRange(0, 0);
    }

    NSInteger bufferCount = self.overscanCount;
    if (self.overscanLength > 0) {
        CGFloat viewportLength = self.isHorizontal ? self.viewportSize.width : self.viewportSize.height;
        CGFloat averageItemLength = self.isHorizontal ? self.owner.estimatedItemSize.width : self.owner.estimatedItemSize.height;
        if (viewportLength > 0 && averageItemLength > 0) {
            NSInteger computed = (NSInteger)(self.overscanLength * viewportLength / averageItemLength);
            bufferCount = MAX(bufferCount, MIN(computed, 100));
        }
    }

    NSInteger start = (NSInteger)visibleRange.location - bufferCount;
    NSInteger end = NSMaxRange(visibleRange) + bufferCount;
    start = MAX(0, start);
    end = MIN(itemCount, end);

    if (start > end) {
        start = visibleRange.location;
        end = NSMaxRange(visibleRange);
    }

    return NSMakeRange(start, end - start);
}

- (NSRange)rangeToRequest
{
    // Request range is larger than mount range (shadow buffer)
    // This allows JS to render more items than we mount, reducing mount latency
    NSRange mountRange = [self rangeToMount];
    NSInteger itemCount = [self.owner itemCount];
    
    if (mountRange.length == 0 || itemCount == 0) {
        return NSMakeRange(0, 0);
    }
    
    // Calculate buffer extension based on multiplier
    NSInteger bufferExtension = (NSInteger)(mountRange.length * (self.shadowBufferMultiplier - 1.0));
    NSInteger start = MAX(0, (NSInteger)mountRange.location - bufferExtension);
    NSInteger end = MIN(itemCount, NSMaxRange(mountRange) + bufferExtension);
    
    if (start > end) {
        start = mountRange.location;
        end = NSMaxRange(mountRange);
    }
    
    return NSMakeRange(start, end - start);
}

- (void)requestItemsIfNeeded
{
    if (self.totalItemCount <= 0) {
        return;
    }

    NSRange visibleRange = [self visibleRange];
    if (visibleRange.length == 0) {
        return;
    }

    // Use rangeToRequest (larger shadow buffer) instead of rangeToMount
    NSRange requestRange = [self rangeToRequest];
    NSMutableArray<NSNumber *> *needed = [NSMutableArray array];
    NSInteger upperBound = MIN(self.totalItemCount, NSMaxRange(requestRange));
    for (NSInteger index = requestRange.location; index < upperBound; index++) {
        NSNumber *num = @(index);
        BOOL notRendered = ![self.renderedIndices containsObject:num] && ![self.owner hasRenderedItemAtIndex:index];
        BOOL notPending = ![self.pendingRequestedIndices containsObject:num];
        if (notRendered && notPending) {
            [needed addObject:@(index)];
        }
    }

    if (needed.count == 0) {
        return;
    }

    if (self.maxToRenderPerBatch > 0 && needed.count > self.maxToRenderPerBatch) {
        needed = [[needed subarrayWithRange:NSMakeRange(0, self.maxToRenderPerBatch)] mutableCopy];
    }

    [self.eventBus emitRequestItems:needed];
    // Mark as pending
    for (NSNumber *n in needed) {
        [self.pendingRequestedIndices addObject:n];
    }
}

- (void)noteItemsRequested:(NSArray<NSNumber *> *)indices
{
    for (NSNumber *n in indices) {
        [self.pendingRequestedIndices addObject:n];
    }
}

@end
