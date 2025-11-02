#import "SmartCollectionView.h"
#import <React/RCTLog.h>
#import <React/RCTUIManager.h>
#import <React/RCTBridge.h>
#import <React/UIView+React.h>
#import <React/RCTShadowView.h>
#import "SmartCollectionViewLocalData.h"
#import "SmartCollectionViewWrapperView.h"
#import "SmartCollectionViewShadowView.h"

// Debug logging helper
#ifdef DEBUG
#define SCVLog(fmt, ...) NSLog(@"[SCV] " fmt, ##__VA_ARGS__)
#else
#define SCVLog(fmt, ...)
#endif

@interface SmartCollectionView ()

@property (nonatomic, strong) SmartCollectionViewLocalData *localData;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *childViewRegistry;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SmartCollectionViewWrapperView *> *indexToWrapper;
@property (nonatomic, strong) NSMutableArray<SmartCollectionViewWrapperView *> *wrapperReusePool;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *renderedIndices; // Track which indices JS has rendered

- (NSInteger)itemCount;
- (CGSize)sizeForItemAtIndex:(NSInteger)index;
- (UIView *)viewForItemAtIndex:(NSInteger)index;
- (CGSize)metadataSizeForItemAtIndex:(NSInteger)index;
- (SmartCollectionViewWrapperView *)dequeueWrapper;
- (void)recycleWrapper:(SmartCollectionViewWrapperView *)wrapper;

@end

@implementation SmartCollectionView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit
{
    _virtualItems = [NSMutableArray array];
    _layoutCache = [NSMutableDictionary dictionary];
    _cumulativeOffsets = [NSMutableArray array];
    _mountedIndices = [NSMutableSet set];
    _childViewRegistry = [NSMutableDictionary dictionary];
    _indexToWrapper = [NSMutableDictionary dictionary];
    _wrapperReusePool = [NSMutableArray array];
    _renderedIndices = [NSMutableSet set];
    
    // Default values
    _initialNumToRender = 10;
    _maxToRenderPerBatch = 10;
    _overscanCount = 5;
    _overscanLength = 1.0;
    _horizontal = YES;
    _estimatedItemSize = CGSizeMake(100, 80);
    _totalItemCount = 0;
    _needsFullRecompute = YES;
    _mountedCount = 0;
    _scrollOffset = 0;
    _contentSize = CGSizeZero;
    
    // Create scroll view
    _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scrollView.delegate = self;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.bounces = YES;
    _scrollView.scrollEnabled = YES;
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_scrollView];
    
    // Create container view for items
    _containerView = [[UIView alloc] initWithFrame:CGRectZero];
    [_scrollView addSubview:_containerView];
    
    SCVLog(@"SmartCollectionView initialized with scrollView");
    // BREAKPOINT: Set breakpoint here to check reactTag after initialization
    // Note: reactTag might not be set immediately, check again in didMoveToWindow
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    // BREAKPOINT: Set breakpoint here - reactTag should be set by now
    SCVLog(@"didMoveToWindow - view in window: %@, reactTag: %@", self.window ? @"YES" : @"NO", self.reactTag);
    
    // Sync props to shadow view once we have a reactTag
    if (self.window && self.reactTag) {
        [self syncPropsToShadowView];
    }
}

- (void)didAddSubview:(UIView *)subview
{
    [super didAddSubview:subview];
    
    // BREAKPOINT: Set breakpoint here to see when React Native adds children
    // Diagnostic: Log when any subview is added (including our internal ones)
    SCVLog(@"didAddSubview: %@ (tag: %@, isReactChild: %@, my tag: %@)", NSStringFromClass([subview class]), subview.reactTag, subview.reactTag ? @"YES" : @"NO", self.reactTag);
    
    // If this is a React child (has reactTag), register it
    if (subview.reactTag && subview != _scrollView && subview != _containerView) {
        NSInteger index = [self.reactSubviews indexOfObject:subview];
        if (index != NSNotFound) {
            SCVLog(@"✅ didAddSubview: Registering React child at index %ld, tag: %@", (long)index, subview.reactTag);
            [self registerChildView:subview atIndex:index];
        }
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    SCVLog(@"layoutSubviews called, bounds: %@, reactSubviews count: %lu", NSStringFromCGRect(self.bounds), (unsigned long)self.reactSubviews.count);
    
    // Diagnostic: Log reactSubviews to see what React Native thinks our children are
    if (self.reactSubviews.count > 0) {
        for (NSInteger i = 0; i < self.reactSubviews.count; i++) {
            UIView *subview = self.reactSubviews[i];
            SCVLog(@"  reactSubviews[%ld]: %@ (tag: %@)", (long)i, NSStringFromClass([subview class]), subview.reactTag);
        }
    }
    
    // Update scroll view frame
    _scrollView.frame = self.bounds;
    
    // Recompute layout if bounds changed
    if ([self itemCount] > 0 && _needsFullRecompute) {
        [self recomputeLayout];
    }
    
    // Request items if needed after layout
    [self requestItemsForVisibleRange];
}

- (void)addVirtualItem:(UIView *)item atIndex:(NSInteger)index
{
    if (index >= 0 && index <= _virtualItems.count) {
        NSNumber *reactTag = item.reactTag;
        if (reactTag != nil) {
            _childViewRegistry[reactTag] = item;
        }

        if (item.superview != nil) {
            [item removeFromSuperview];
        }

        [_virtualItems insertObject:item atIndex:index];
        _needsFullRecompute = YES;
        
        SCVLog(@"Added virtual item at index %ld, total items: %ld", (long)index, (long)_virtualItems.count);
        SCVLog(@"Child tag %@ initial frame %@", item.reactTag, NSStringFromCGRect(item.frame));
        
        [self recomputeLayout];
    }
}

- (void)removeVirtualItem:(UIView *)item
{
    NSInteger index = [_virtualItems indexOfObject:item];
    if (index != NSNotFound) {
        [_virtualItems removeObjectAtIndex:index];
        NSNumber *reactTag = item.reactTag;
        if (reactTag != nil) {
            [_childViewRegistry removeObjectForKey:reactTag];
        }
        [_mountedIndices removeObject:@(index)];
        _needsFullRecompute = YES;
        
        SCVLog(@"Removed virtual item at index %ld, total items: %ld", (long)index, (long)_virtualItems.count);
        
        [self recomputeLayout];
    }
}

- (void)registerChildView:(UIView *)view atIndex:(NSInteger)index
{
    SCVLog(@"registerChildView: view tag %@ at index %ld", view.reactTag, (long)index);
    
    // Mark this index as rendered
    [_renderedIndices addObject:@(index)];
    
    // Also add to registry immediately by reactTag
    if (view.reactTag != nil) {
        _childViewRegistry[view.reactTag] = view;
        SCVLog(@"Added to childViewRegistry: tag %@", view.reactTag);
    }
    
    [self addVirtualItem:view atIndex:index];
}

- (void)unregisterChildView:(UIView *)view
{
    [self removeVirtualItem:view];
}

- (void)updateWithLocalData:(SmartCollectionViewLocalData *)localData
{
    // BREAKPOINT: Set breakpoint here - this confirms localData arrived from manager
    SCVLog(@"🔥🔥🔥 updateWithLocalData CALLED - version %ld, items %lu, my tag: %@", (long)localData.version, (unsigned long)localData.items.count, self.reactTag);
    dispatch_async(dispatch_get_main_queue(), ^{
        self.localData = localData;
        SCVLog(@"✅ Received local data version %ld, items %lu", (long)localData.version, (unsigned long)localData.items.count);
        if (localData.items.count > 0) {
            SmartCollectionViewItemMetadata *first = localData.items.firstObject;
            SCVLog(@"First metadata tag %@ size %@", first.reactTag, NSStringFromCGSize(first.size));
            NSInteger sampleCount = MIN(5, localData.items.count);
            for (NSInteger i = 0; i < sampleCount; i++) {
                SmartCollectionViewItemMetadata *meta = localData.items[i];
                SCVLog(@"Metadata[%ld] tag %@ size %@ version %ld", (long)i, meta.reactTag, NSStringFromCGSize(meta.size), (long)meta.version);
            }
        }
        
        // Log all registered child views
        SCVLog(@"ChildViewRegistry has %lu entries:", (unsigned long)self->_childViewRegistry.count);
        for (NSNumber *tag in self->_childViewRegistry.allKeys) {
            UIView *view = self->_childViewRegistry[tag];
            SCVLog(@"  Tag %@ -> view frame: %@", tag, NSStringFromCGRect(view.frame));
        }
        
        self->_needsFullRecompute = YES;
        [self recomputeLayout];
    });
}

- (NSInteger)itemCount
{
    // Use totalItemCount if set, otherwise fall back to rendered items
    if (_totalItemCount > 0) {
        return _totalItemCount;
    }
    NSInteger metadataCount = self.localData ? self.localData.items.count : 0;
    return MAX(_virtualItems.count, metadataCount);
}

- (CGSize)metadataSizeForItemAtIndex:(NSInteger)index
{
    if (self.localData) {
        SCVLog(@"metadataSizeForItemAtIndex %ld: localData.items.count=%lu", (long)index, (unsigned long)self.localData.items.count);
        if (index < self.localData.items.count) {
            SmartCollectionViewItemMetadata *metadata = self.localData.items[index];
            SCVLog(@"Metadata[%ld] tag %@ size %@", (long)index, metadata.reactTag, NSStringFromCGSize(metadata.size));
            return metadata.size;
        } else {
            SCVLog(@"Index %ld out of bounds for localData (count %lu)", (long)index, (unsigned long)self.localData.items.count);
        }
    } else {
        SCVLog(@"metadataSizeForItemAtIndex %ld: localData is nil", (long)index);
    }
    return CGSizeZero;
}

- (CGSize)sizeForItemAtIndex:(NSInteger)index
{
    CGSize metadataSize = [self metadataSizeForItemAtIndex:index];
    if (!CGSizeEqualToSize(metadataSize, CGSizeZero)) {
        SCVLog(@"sizeForItemAtIndex %ld: using metadata size %@", (long)index, NSStringFromCGSize(metadataSize));
        return metadataSize;
    }

    if (index < _virtualItems.count) {
        UIView *item = _virtualItems[index];
        CGSize actualSize = [self actualSizeForItem:item];
        if (!CGSizeEqualToSize(actualSize, CGSizeZero)) {
            SCVLog(@"sizeForItemAtIndex %ld: using actual size %@", (long)index, NSStringFromCGSize(actualSize));
            return actualSize;
        }
    }
    
    SCVLog(@"sizeForItemAtIndex %ld: using estimated size %@", (long)index, NSStringFromCGSize(_estimatedItemSize));
    return _estimatedItemSize;
}

- (UIView *)viewForItemAtIndex:(NSInteger)index
{
    SCVLog(@"viewForItemAtIndex %ld", (long)index);
    
    if (self.localData && index < self.localData.items.count) {
        SmartCollectionViewItemMetadata *metadata = self.localData.items[index];
        SCVLog(@"Looking for view with reactTag %@ in registry (count: %lu)", metadata.reactTag, (unsigned long)_childViewRegistry.count);
        
        // Log all registered tags
        for (NSNumber *tag in _childViewRegistry.allKeys) {
            SCVLog(@"  Registered tag: %@", tag);
        }
        
        UIView *view = _childViewRegistry[metadata.reactTag];
        if (view) {
            SCVLog(@"Found view for index %ld with tag %@", (long)index, metadata.reactTag);
            return view;
        } else {
            SCVLog(@"No view found for tag %@", metadata.reactTag);
        }
    } else {
        if (!self.localData) {
            SCVLog(@"viewForItemAtIndex %ld: localData is nil", (long)index);
        } else {
            SCVLog(@"viewForItemAtIndex %ld: index out of bounds (localData.items.count=%lu)", (long)index, (unsigned long)self.localData.items.count);
        }
    }

    if (index < _virtualItems.count) {
        SCVLog(@"viewForItemAtIndex %ld: using virtualItems[%ld]", (long)index, (long)index);
        return _virtualItems[index];
    }
    
    SCVLog(@"viewForItemAtIndex %ld: returning nil", (long)index);
    return nil;
}

- (void)recomputeLayout
{
    if (_needsFullRecompute) {
        [self performFullLayoutRecompute];
        _needsFullRecompute = NO;
    } else {
        [self performIncrementalLayoutUpdate];
    }
    
    [self mountVisibleItemsWithBatching];
    
    // After layout recompute, check if we need more items
    [self requestItemsForVisibleRange];
}

- (void)performFullLayoutRecompute
{
    SCVLog(@"Performing full layout recompute for %ld items, horizontal: %@", (long)[self itemCount], _horizontal ? @"YES" : @"NO");
    SCVLog(@"Bounds: %@", NSStringFromCGRect(self.bounds));
    SCVLog(@"localData: %@, items count: %lu", self.localData ? @"exists" : @"nil", (unsigned long)(self.localData ? self.localData.items.count : 0));
    
    // If localData is nil, we can't compute proper sizes - wait for it to arrive via setLocalData
    if (!self.localData || self.localData.items.count == 0) {
        SCVLog(@"WARNING: localData is nil or empty, cannot compute layout. Will retry when localData arrives.");
        return;
    }
    
    // CURRENTLY: Horizontal list/grid layout only
    // TODO: When adding vertical list or grid layouts, refactor into separate methods:
    //   - performHorizontalLayoutRecompute (current implementation)
    //   - performVerticalLayoutRecompute (future)
    //   - performHorizontalGridLayoutRecompute (future)
    //   - performVerticalGridLayoutRecompute (future)
    
    // For now, assert horizontal layout (POC scope)
    if (!_horizontal) {
        SCVLog(@"ERROR: Vertical layout not yet supported. Only horizontal layout is implemented.");
        return;
    }
    
    [self performHorizontalLayoutRecompute];
}

#pragma mark - Horizontal Layout (Current Implementation)

- (void)performHorizontalLayoutRecompute
{
    // Clear existing cache
    [_layoutCache removeAllObjects];
    [_cumulativeOffsets removeAllObjects];
    
    // First pass: calculate actual item sizes and find max height
    CGFloat maxHeight = 0;
    NSMutableArray *actualSizes = [NSMutableArray array];
    
    // Use the maximum of virtualItems count and localData items count
    NSInteger itemCount = [self itemCount];
    if (self.localData) {
        itemCount = MAX(itemCount, self.localData.items.count);
    }

    for (NSInteger i = 0; i < itemCount; i++) {
        CGSize itemSize = [self sizeForItemAtIndex:i];
        [actualSizes addObject:[NSValue valueWithCGSize:itemSize]];
        
        if (itemSize.height > maxHeight) {
            maxHeight = itemSize.height;
        }
        
        SCVLog(@"Measured item %ld actual size %@", (long)i, NSStringFromCGSize(itemSize));
    }
    
    SCVLog(@"Max height calculated: %.2f", maxHeight);
    
    // Second pass: calculate frames with actual sizes (horizontal layout)
    CGFloat currentOffset = 0;
    
    for (NSInteger i = 0; i < itemCount; i++) {
        CGSize itemSize = (i < actualSizes.count) ? [actualSizes[i] CGSizeValue] : _estimatedItemSize;
        
        // Horizontal layout: items positioned side by side, all same height (max)
        CGRect frame = CGRectMake(currentOffset, 0, itemSize.width, maxHeight);
        currentOffset += itemSize.width;
        
        SCVLog(@"Item %ld -> size %@ frame %@ (horizontal, x: %.2f, y: %.2f, w: %.2f, h: %.2f)", 
               (long)i, NSStringFromCGSize(itemSize), NSStringFromCGRect(frame),
               frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
        
        _layoutCache[@(i)] = [NSValue valueWithCGRect:frame];
        [_cumulativeOffsets addObject:@(currentOffset)];
    }
    
    [self updateContentSize];
    
    // Update scroll view content size
    _scrollView.contentSize = _contentSize;
    _containerView.frame = CGRectMake(0, 0, _contentSize.width, _contentSize.height);
    
    // Update SmartCollectionView height to match max item height
    CGRect newFrame = self.frame;
    newFrame.size.height = maxHeight;
    self.frame = newFrame;
    
    SCVLog(@"Updated scrollView.contentSize %@", NSStringFromCGSize(_contentSize));
    SCVLog(@"Updated SCV frame %@", NSStringFromCGRect(self.frame));
    
    _lastComputedRange = NSMakeRange(0, itemCount);
}

// TODO: Future layout implementations
// - (void)performVerticalLayoutRecompute { ... }
// - (void)performHorizontalGridLayoutRecompute { ... }
// - (void)performVerticalGridLayoutRecompute { ... }

- (CGSize)actualSizeForItem:(UIView *)item
{
    // Force layout to get actual size
    [item setNeedsLayout];
    [item layoutIfNeeded];
    
    // Get the actual size from the item's intrinsic content size or frame
    CGSize size = item.frame.size;
    
    // If frame is zero, use estimated size
    if (size.width == 0 || size.height == 0) {
        size = _estimatedItemSize;
    }
    
    return size;
}

- (void)performIncrementalLayoutUpdate
{
    NSRange visibleRange = [self computeRangeToLayout];
    
    // Find intersection with last computed range
    NSRange intersection = NSIntersectionRange(visibleRange, _lastComputedRange);
    
    if (intersection.length == 0) {
        // No overlap, recompute buffer range
        [self recomputeRange:visibleRange];
    } else {
        // Partial overlap, recompute only new items
        NSRange newRange = NSMakeRange(NSMaxRange(intersection), 
                                     NSMaxRange(visibleRange) - NSMaxRange(intersection));
        if (newRange.length > 0) {
            [self recomputeRange:newRange];
        }
    }
    
    _lastComputedRange = visibleRange;
}

- (void)recomputeRange:(NSRange)range
{
    // CURRENTLY: Horizontal layout only
    // TODO: When adding other layouts, extract horizontal-specific logic
    
    CGFloat currentOffset = 0;
    
    // Calculate offset for items before this range (horizontal layout)
    for (NSInteger i = 0; i < range.location; i++) {
        CGSize itemSize = [self estimatedSizeForItemAtIndex:i];
        currentOffset += itemSize.width; // Horizontal: accumulate width
    }
    
    NSInteger totalCount = [self itemCount];
    for (NSInteger i = range.location; i < NSMaxRange(range); i++) {
        if (i < totalCount) {
            CGSize itemSize = [self estimatedSizeForItemAtIndex:i];
            
            // Horizontal layout: items side by side
            CGRect frame = CGRectMake(currentOffset, 0, itemSize.width, self.bounds.size.height);
            currentOffset += itemSize.width;
            
            _layoutCache[@(i)] = [NSValue valueWithCGRect:frame];
        }
    }
}

- (NSRange)computeRangeToLayout
{
    // CURRENTLY: Horizontal layout only (uses width-based overscan)
    // TODO: When adding vertical layouts, extract direction-specific logic
    
    NSRange visibleRange = [self visibleItemRange];
    
    // Expand by overscanCount or overscanLength (horizontal layout)
    NSInteger buffer = _overscanCount;
    if (_overscanLength > 0) {
        CGFloat viewportWidth = self.bounds.size.width;
        CGFloat averageItemWidth = _estimatedItemSize.width;
        buffer = (NSInteger)(_overscanLength * viewportWidth / averageItemWidth);
    }
    
    NSInteger itemCount = [self itemCount];
    NSInteger start = MAX(0, visibleRange.location - buffer);
    NSInteger end = MIN(itemCount, NSMaxRange(visibleRange) + buffer);
    
    return NSMakeRange(start, end - start);
}

- (CGSize)estimatedSizeForItemAtIndex:(NSInteger)index
{
    return [self sizeForItemAtIndex:index];
}

- (void)mountVisibleItemsWithBatching
{
    NSRange rangeToMount = [self computeRangeToLayout];
    NSMutableArray *itemsToMount = [NSMutableArray array];
    
    for (NSInteger i = rangeToMount.location; i < NSMaxRange(rangeToMount); i++) {
        if (![_mountedIndices containsObject:@(i)]) {
            [itemsToMount addObject:@(i)];
        } else {
            SCVLog(@"Index %ld already mounted", (long)i);
        }
    }
    
    [self mountItemsBatched:itemsToMount batchSize:_maxToRenderPerBatch];
}

- (void)mountItemsBatched:(NSArray *)items batchSize:(NSInteger)size
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger end = MIN(self.mountedCount + size, items.count);
        
        for (NSInteger i = self.mountedCount; i < end; i++) {
            NSNumber *indexNumber = items[i];
            NSInteger index = [indexNumber integerValue];
            [self mountItemAtIndex:index];
        }
        
        self.mountedCount = end;
        
        if (end < items.count) {
            [self mountItemsBatched:items batchSize:size];
        }
    });
}

- (void)mountItemAtIndex:(NSInteger)index
{
    if (index < 0) {
        return;
    }

    UIView *item = [self viewForItemAtIndex:index];
    if (item) {
        NSValue *frameValue = _layoutCache[@(index)];
        
        if (frameValue) {
            CGRect frame = [frameValue CGRectValue];
            SCVLog(@"Mounting index %ld frame %@ metadata %@", (long)index, NSStringFromCGRect(frame), NSStringFromCGSize([self metadataSizeForItemAtIndex:index]));
            SCVLog(@"Wrapper will be at frame x=%.2f y=%.2f w=%.2f h=%.2f", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);

            SmartCollectionViewWrapperView *wrapper = _indexToWrapper[@(index)];
            if (!wrapper) {
                wrapper = [self dequeueWrapper];
                _indexToWrapper[@(index)] = wrapper;
            }

            wrapper.reactTag = item.reactTag;
            wrapper.frame = frame;

            if (wrapper.superview != _containerView) {
                [_containerView addSubview:wrapper];
                SCVLog(@"Added wrapper to containerView, containerView frame: %@", NSStringFromCGRect(_containerView.frame));
            }

            if (item.superview != wrapper) {
                [item removeFromSuperview];
                item.frame = wrapper.bounds;
                item.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [wrapper addSubview:item];
                SCVLog(@"Added React child to wrapper, child frame: %@", NSStringFromCGRect(item.frame));
            } else {
                item.frame = wrapper.bounds;
            }

            SCVLog(@"Mounted item %ld - wrapper frame: %@, wrapper in hierarchy: %@", 
                   (long)index, NSStringFromCGRect(wrapper.frame), wrapper.superview ? @"YES" : @"NO");
            [_mountedIndices addObject:@(index)];
        } else {
            SCVLog(@"No frame found for index %ld", (long)index);
        }
    } else {
        SCVLog(@"No view available to mount index %ld", (long)index);
    }
}

- (void)unmountItemAtIndex:(NSInteger)index
{
    if ([_mountedIndices containsObject:@(index)]) {
        SmartCollectionViewWrapperView *wrapper = _indexToWrapper[@(index)];
        if (wrapper) {
            UIView *item = wrapper.subviews.firstObject;
            if (item) {
                [item removeFromSuperview];
            }
            [wrapper removeFromSuperview];
            wrapper.reactTag = nil;
            [self recycleWrapper:wrapper];
            [_indexToWrapper removeObjectForKey:@(index)];
        }
        [_mountedIndices removeObject:@(index)];
    }
}

#pragma mark - UIScrollViewDelegate

#pragma mark - Request Items

- (BOOL)hasRenderedItemAtIndex:(NSInteger)index
{
    return [_renderedIndices containsObject:@(index)];
}

- (NSRange)expandRangeWithOverscan:(NSRange)range
{
    NSInteger start = MAX(0, (NSInteger)range.location - _overscanCount);
    NSInteger end = MIN([self itemCount] - 1, NSMaxRange(range) + _overscanCount);
    return NSMakeRange(start, end - start + 1);
}

- (void)requestItemsForVisibleRange
{
    if (_totalItemCount == 0) {
        return; // No items to request
    }
    
    NSRange visibleRange = [self visibleItemRange];
    if (visibleRange.length == 0) {
        return; // No visible items yet
    }
    
    NSRange rangeWithOverscan = [self expandRangeWithOverscan:visibleRange];
    
    // Find which indices we don't have rendered yet
    NSMutableArray<NSNumber *> *neededIndices = [NSMutableArray array];
    for (NSInteger i = rangeWithOverscan.location; i < NSMaxRange(rangeWithOverscan) && i < _totalItemCount; i++) {
        if (![self hasRenderedItemAtIndex:i]) {
            [neededIndices addObject:@(i)];
        }
    }
    
    if (neededIndices.count == 0) {
        return; // All needed items already rendered
    }
    
    // Limit batch size if configured
    if (_maxToRenderPerBatch > 0 && neededIndices.count > _maxToRenderPerBatch) {
        neededIndices = [[neededIndices subarrayWithRange:NSMakeRange(0, _maxToRenderPerBatch)] mutableCopy];
    }
    
    SCVLog(@"Requesting items: %@", neededIndices);
    
    if (self.onRequestItems) {
        self.onRequestItems(@{
            @"indices": neededIndices
        });
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    // CURRENTLY: Horizontal layout only (tracks X offset)
    // TODO: When adding vertical layouts, track Y offset as well
    _scrollOffset = scrollView.contentOffset.x; // Horizontal scroll offset
    SCVLog(@"Scroll offset %.2f", _scrollOffset);
    
    // Emit scroll event
    if (self.onScroll) {
        self.onScroll(@{
            @"contentOffset": @{
                @"x": @(scrollView.contentOffset.x),
                @"y": @(scrollView.contentOffset.y)
            },
            @"contentSize": @{
                @"width": @(scrollView.contentSize.width),
                @"height": @(scrollView.contentSize.height)
            },
            @"layoutMeasurement": @{
                @"width": @(scrollView.frame.size.width),
                @"height": @(scrollView.frame.size.height)
            }
        });
    }
    
    // Request items if needed and update visible items
    [self requestItemsForVisibleRange];
    [self updateVisibleItems];
    
    // Emit visible range change
    NSRange visibleRange = [self visibleItemRange];
    if (self.onVisibleRangeChange) {
        self.onVisibleRangeChange(@{
            @"first": @(visibleRange.location),
            @"last": @(NSMaxRange(visibleRange) - 1)
        });
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if (self.onScrollBeginDrag) {
        self.onScrollBeginDrag(@{
            @"contentOffset": @{
                @"x": @(scrollView.contentOffset.x),
                @"y": @(scrollView.contentOffset.y)
            },
            @"contentSize": @{
                @"width": @(scrollView.contentSize.width),
                @"height": @(scrollView.contentSize.height)
            },
            @"layoutMeasurement": @{
                @"width": @(scrollView.frame.size.width),
                @"height": @(scrollView.frame.size.height)
            }
        });
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (self.onScrollEndDrag) {
        self.onScrollEndDrag(@{
            @"contentOffset": @{
                @"x": @(scrollView.contentOffset.x),
                @"y": @(scrollView.contentOffset.y)
            },
            @"contentSize": @{
                @"width": @(scrollView.contentSize.width),
                @"height": @(scrollView.contentSize.height)
            },
            @"layoutMeasurement": @{
                @"width": @(scrollView.frame.size.width),
                @"height": @(scrollView.frame.size.height)
            }
        });
    }
    
    if (!decelerate && self.onScrollEndDecelerating) {
        self.onScrollEndDecelerating(@{
            @"contentOffset": @{
                @"x": @(scrollView.contentOffset.x),
                @"y": @(scrollView.contentOffset.y)
            },
            @"contentSize": @{
                @"width": @(scrollView.contentSize.width),
                @"height": @(scrollView.contentSize.height)
            },
            @"layoutMeasurement": @{
                @"width": @(scrollView.frame.size.width),
                @"height": @(scrollView.frame.size.height)
            }
        });
    }
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView
{
    if (self.onMomentumScrollBegin) {
        self.onMomentumScrollBegin(@{
            @"contentOffset": @{
                @"x": @(scrollView.contentOffset.x),
                @"y": @(scrollView.contentOffset.y)
            },
            @"contentSize": @{
                @"width": @(scrollView.contentSize.width),
                @"height": @(scrollView.contentSize.height)
            },
            @"layoutMeasurement": @{
                @"width": @(scrollView.frame.size.width),
                @"height": @(scrollView.frame.size.height)
            }
        });
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (self.onMomentumScrollEnd) {
        self.onMomentumScrollEnd(@{
            @"contentOffset": @{
                @"x": @(scrollView.contentOffset.x),
                @"y": @(scrollView.contentOffset.y)
            },
            @"contentSize": @{
                @"width": @(scrollView.contentSize.width),
                @"height": @(scrollView.contentSize.height)
            },
            @"layoutMeasurement": @{
                @"width": @(scrollView.frame.size.width),
                @"height": @(scrollView.frame.size.height)
            }
        });
    }
    
    if (self.onScrollEndDecelerating) {
        self.onScrollEndDecelerating(@{
            @"contentOffset": @{
                @"x": @(scrollView.contentOffset.x),
                @"y": @(scrollView.contentOffset.y)
            },
            @"contentSize": @{
                @"width": @(scrollView.contentSize.width),
                @"height": @(scrollView.contentSize.height)
            },
            @"layoutMeasurement": @{
                @"width": @(scrollView.frame.size.width),
                @"height": @(scrollView.frame.size.height)
            }
        });
    }
    
    // Request items after scrolling ends
    [self requestItemsForVisibleRange];
}

- (void)updateContentSize
{
    // CURRENTLY: Horizontal layout only
    // TODO: When adding vertical layouts, refactor into separate methods
    
    NSInteger count = [self itemCount];
    if (count == 0) {
        _contentSize = CGSizeZero;
        return;
    }
    
    // Horizontal layout: sum widths for content width
    CGFloat totalWidth = 0;
    for (NSInteger i = 0; i < count; i++) {
        CGSize itemSize = [self sizeForItemAtIndex:i];
        totalWidth += itemSize.width;
    }
    
    // Content size: width = sum of item widths, height = container height
    _contentSize = CGSizeMake(totalWidth, self.bounds.size.height);
    
    SCVLog(@"Updated content size %@ (horizontal layout)", NSStringFromCGSize(_contentSize));
}

- (CGFloat)getCumulativeOffsetAtIndex:(NSInteger)index
{
    if (index >= _cumulativeOffsets.count) {
        return 0;
    }
    return [_cumulativeOffsets[index] floatValue];
}

- (NSRange)visibleItemRange
{
    // CURRENTLY: Horizontal layout only (uses width-based visibility)
    // TODO: When adding vertical layouts, extract into separate method or add direction parameter
    
    if ([self itemCount] == 0) {
        return NSMakeRange(0, 0);
    }
    
    // Horizontal layout: use viewport width and horizontal scroll offset
    CGFloat viewportWidth = self.bounds.size.width;
    CGFloat startOffset = _scrollOffset;
    CGFloat endOffset = startOffset + viewportWidth;
    
    NSInteger startIndex = 0;
    NSInteger endIndex = [self itemCount];
    
    // Binary search for start index (based on cumulative X offsets)
    NSInteger left = 0, right = [self itemCount] - 1;
    while (left <= right) {
        NSInteger mid = (left + right) / 2;
        CGFloat offset = [self getCumulativeOffsetAtIndex:mid];
        if (offset < startOffset) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    startIndex = left;
    
    // Binary search for end index
    left = startIndex;
    right = [self itemCount] - 1;
    while (left <= right) {
        NSInteger mid = (left + right) / 2;
        CGFloat offset = [self getCumulativeOffsetAtIndex:mid];
        if (offset <= endOffset) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    endIndex = left;
    
    return NSMakeRange(startIndex, endIndex - startIndex);
}

- (void)updateVisibleItems
{
    NSRange visibleRange = [self visibleItemRange];
    NSRange rangeToMount = [self computeRangeToLayout];
    
    SCVLog(@"Visible range %@, rangeToMount %@", NSStringFromRange(visibleRange), NSStringFromRange(rangeToMount));
    
    // Unmount items outside the range
    NSMutableSet *indicesToUnmount = [NSMutableSet setWithSet:_mountedIndices];
    for (NSInteger i = rangeToMount.location; i < NSMaxRange(rangeToMount); i++) {
        [indicesToUnmount removeObject:@(i)];
    }
    
    for (NSNumber *indexNum in indicesToUnmount) {
        [self unmountItemAtIndex:[indexNum integerValue]];
    }
    
    // Mount items in the range
    for (NSInteger i = rangeToMount.location; i < NSMaxRange(rangeToMount); i++) {
        NSNumber *indexNumber = @(i);
        NSValue *frameValue = _layoutCache[indexNumber];
        CGRect frame = frameValue ? [frameValue CGRectValue] : CGRectZero;

        if ([_mountedIndices containsObject:indexNumber]) {
            SmartCollectionViewWrapperView *wrapper = _indexToWrapper[indexNumber];
            if (wrapper && !CGRectEqualToRect(wrapper.frame, frame) && !CGRectEqualToRect(frame, CGRectZero)) {
                SCVLog(@"Updating mounted wrapper for index %ld to frame %@", (long)i, NSStringFromCGRect(frame));
                wrapper.frame = frame;
                UIView *child = wrapper.subviews.firstObject;
                if (child) {
                    child.frame = wrapper.bounds;
                }
            }
        } else {
            [self mountItemAtIndex:i];
        }
    }
}

- (SmartCollectionViewWrapperView *)dequeueWrapper
{
    SmartCollectionViewWrapperView *wrapper = _wrapperReusePool.lastObject;
    if (wrapper) {
        [_wrapperReusePool removeLastObject];
        SCVLog(@"Reusing wrapper %@", wrapper);
    } else {
        wrapper = [[SmartCollectionViewWrapperView alloc] initWithFrame:CGRectZero];
        SCVLog(@"Creating new wrapper %@", wrapper);
    }
    return wrapper;
}

- (void)recycleWrapper:(SmartCollectionViewWrapperView *)wrapper
{
    if (!wrapper) {
        return;
    }
    [wrapper.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    wrapper.frame = CGRectZero;
    wrapper.reactTag = nil;
    [_wrapperReusePool addObject:wrapper];
    SCVLog(@"Recycled wrapper %@ (pool size %lu)", wrapper, (unsigned long)_wrapperReusePool.count);
}

- (void)setHorizontal:(BOOL)horizontal
{
    if (_horizontal == horizontal) {
        return;
    }

    _horizontal = horizontal;
    
    // Sync to shadow view for measureFunc
    [self syncPropsToShadowView];

    // Update scroll view configuration to reflect orientation
    _scrollView.alwaysBounceHorizontal = _horizontal;
    _scrollView.alwaysBounceVertical = !_horizontal;
    _scrollView.showsHorizontalScrollIndicator = _horizontal;
    _scrollView.showsVerticalScrollIndicator = !_horizontal;

    // Trigger a full recompute with the new orientation
    _needsFullRecompute = YES;
    [self recomputeLayout];
}

- (void)setEstimatedItemSize:(CGSize)estimatedItemSize
{
    if (CGSizeEqualToSize(_estimatedItemSize, estimatedItemSize)) {
        return;
    }
    
    _estimatedItemSize = estimatedItemSize;
    
    // Sync to shadow view for measureFunc
    [self syncPropsToShadowView];
}

- (void)syncPropsToShadowView
{
    // Access shadow view via UIManager and sync props
    // Note: Props are synced from manager when they're set via RCT_EXPORT_VIEW_PROPERTY
    // This method can be called to force sync if needed, but for now we'll rely on
    // the shadow view's default values and props being set directly via the manager
    // TODO: Implement proper prop sync from view to shadow view if needed
    // For now, shadow view defaults to horizontal=YES and uses estimatedItemSize from init
    
    if (!self.reactTag) {
        return;
    }
    
    // Props sync will be handled via manager's prop setters if needed
    // Shadow view already has defaults that match our initial values
    SCVLog(@"syncPropsToShadowView called (props synced via manager)");
}

@end