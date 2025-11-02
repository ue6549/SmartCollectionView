#import "SmartCollectionViewScheduler.h"
#import <React/RCTLog.h>

@implementation SmartCollectionViewScheduler

- (instancetype)initWithLayoutProvider:(id<SmartCollectionViewLayoutProvider>)layoutProvider {
    self = [super init];
    if (self) {
        _layoutProvider = layoutProvider;
        _virtualItems = [NSMutableArray array];
        _mountedIndices = [NSMutableSet set];
        _horizontal = YES;
        _initialNumToRender = 10;
        _maxToRenderPerBatch = 10;
        _overscanCount = 5;
        _needsLayoutRecompute = YES;
        _scrollOffset = 0;
        _contentSize = CGSizeZero;
        _viewport = CGSizeZero;
        
        NSLog(@"SmartCollectionViewScheduler initialized with layout provider: %@", layoutProvider.layoutType);
    }
    return self;
}

- (void)onScrollOffsetChange:(CGFloat)offset {
    _scrollOffset = offset;
    NSLog(@"SmartCollectionViewScheduler: Scroll offset changed to %.2f", offset);
}

- (void)onDataChange:(NSArray<UIView *> *)items {
    [_virtualItems removeAllObjects];
    [_virtualItems addObjectsFromArray:items];
    [_mountedIndices removeAllObjects];
    _needsLayoutRecompute = YES;
    
    NSLog(@"SmartCollectionViewScheduler: Data changed, %ld items", (long)items.count);
    [self recomputeLayoutIfNeeded];
}

- (void)onViewportChange:(CGSize)viewport {
    _viewport = viewport;
    _needsLayoutRecompute = YES;
    
    NSLog(@"SmartCollectionViewScheduler: Viewport changed to %@", NSStringFromCGSize(viewport));
    [self recomputeLayoutIfNeeded];
}

- (void)recomputeLayoutIfNeeded {
    if (!_needsLayoutRecompute || _virtualItems.count == 0) {
        return;
    }
    
    NSLog(@"SmartCollectionViewScheduler: Recomputing layout for %ld items", (long)_virtualItems.count);
    
    // Use layout provider to calculate content size
    _contentSize = [_layoutProvider contentSizeForItems:_virtualItems 
                                               viewport:_viewport 
                                         scrollDirection:_horizontal];
    
    _needsLayoutRecompute = NO;
    
    NSLog(@"SmartCollectionViewScheduler: Content size calculated: %@", NSStringFromCGSize(_contentSize));
}

- (NSRange)visibleItemRange {
    if (_virtualItems.count == 0) {
        return NSMakeRange(0, 0);
    }
    
    // Calculate visible range based on scroll offset and viewport
    CGFloat startOffset = _scrollOffset;
    CGFloat endOffset = _scrollOffset + (_horizontal ? _viewport.width : _viewport.height);
    
    NSInteger startIndex = 0;
    NSInteger endIndex = _virtualItems.count - 1;
    
    // Find start index
    CGFloat currentOffset = 0;
    for (NSInteger i = 0; i < _virtualItems.count; i++) {
        CGRect frame = [self frameForItemAtIndex:i];
        CGFloat itemSize = _horizontal ? frame.size.width : frame.size.height;
        
        if (currentOffset + itemSize > startOffset) {
            startIndex = i;
            break;
        }
        currentOffset += itemSize;
    }
    
    // Find end index
    currentOffset = 0;
    for (NSInteger i = 0; i < _virtualItems.count; i++) {
        CGRect frame = [self frameForItemAtIndex:i];
        CGFloat itemSize = _horizontal ? frame.size.width : frame.size.height;
        
        if (currentOffset > endOffset) {
            endIndex = i - 1;
            break;
        }
        currentOffset += itemSize;
    }
    
    NSRange visibleRange = NSMakeRange(startIndex, endIndex - startIndex + 1);
    NSLog(@"SmartCollectionViewScheduler: Visible range: %@", NSStringFromRange(visibleRange));
    
    return visibleRange;
}

- (NSRange)rangeToMount {
    NSRange visibleRange = [self visibleItemRange];
    
    // Expand range with overscan
    NSInteger startIndex = MAX(0, (NSInteger)visibleRange.location - _overscanCount);
    NSInteger endIndex = MIN(_virtualItems.count - 1, NSMaxRange(visibleRange) + _overscanCount);
    
    NSRange rangeToMount = NSMakeRange(startIndex, endIndex - startIndex + 1);
    NSLog(@"SmartCollectionViewScheduler: Range to mount: %@", NSStringFromRange(rangeToMount));
    
    return rangeToMount;
}

- (NSArray<NSNumber *> *)indicesToMount {
    NSRange rangeToMount = [self rangeToMount];
    NSMutableArray<NSNumber *> *indicesToMount = [NSMutableArray array];
    
    for (NSInteger i = rangeToMount.location; i < NSMaxRange(rangeToMount); i++) {
        if (![_mountedIndices containsObject:@(i)]) {
            [indicesToMount addObject:@(i)];
        }
    }
    
    NSLog(@"SmartCollectionViewScheduler: Indices to mount: %@", indicesToMount);
    return [indicesToMount copy];
}

- (NSArray<NSNumber *> *)indicesToUnmount {
    NSRange rangeToMount = [self rangeToMount];
    NSMutableArray<NSNumber *> *indicesToUnmount = [NSMutableArray array];
    
    for (NSNumber *indexNum in _mountedIndices) {
        NSInteger index = [indexNum integerValue];
        if (index < rangeToMount.location || index >= NSMaxRange(rangeToMount)) {
            [indicesToUnmount addObject:indexNum];
        }
    }
    
    NSLog(@"SmartCollectionViewScheduler: Indices to unmount: %@", indicesToUnmount);
    return [indicesToUnmount copy];
}

- (CGRect)frameForItemAtIndex:(NSInteger)index {
    if (index < 0 || index >= _virtualItems.count) {
        NSLog(@"SmartCollectionViewScheduler: Invalid index %ld for items count %ld", (long)index, (long)_virtualItems.count);
        return CGRectZero;
    }
    
    CGRect frame = [_layoutProvider layoutAttributesForItemAtIndex:index 
                                                             items:_virtualItems 
                                                          viewport:_viewport];
    
    NSLog(@"SmartCollectionViewScheduler: Frame for item %ld: %@", (long)index, NSStringFromCGRect(frame));
    return frame;
}

- (CGSize)getContentSize {
    [self recomputeLayoutIfNeeded];
    return _contentSize;
}

@end
