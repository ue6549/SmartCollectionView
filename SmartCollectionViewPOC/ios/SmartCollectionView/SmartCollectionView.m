#import "SmartCollectionView.h"
#import <React/RCTLog.h>
#import <React/RCTUIManager.h>
#import <React/RCTBridge.h>
#import <React/RCTBridge+Private.h>
#import <React/UIView+React.h>
#import <React/RCTShadowView.h>
#import <yoga/Yoga.h>
#import <float.h>
#import "SmartCollectionViewLocalData.h"
#import "SmartCollectionViewWrapperView.h"
#import "SmartCollectionViewShadowView.h"
#import "SmartCollectionViewLayoutCache.h"
#import "SmartCollectionViewLayoutSpec.h"
#import "SmartCollectionViewVisibilityTracker.h"
#import "SmartCollectionViewMountController.h"
#import "SmartCollectionViewEventBus.h"
#import "SmartCollectionViewScheduler.h"
#import "SmartCollectionViewReusePool.h"

// Debug logging helper
#ifdef DEBUG
//#define SCVLog(fmt, ...) NSLog(@"[SCV] " fmt, ##__VA_ARGS__)
//#else
#define SCVLog(fmt, ...)
#endif

@interface SmartCollectionView ()

@property (nonatomic, strong) SmartCollectionViewLocalData *localData;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *childViewRegistry;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SmartCollectionViewWrapperView *> *indexToWrapper;
@property (nonatomic, strong) NSMutableArray<SmartCollectionViewWrapperView *> *wrapperReusePool;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *renderedIndices; // Track which indices JS has rendered
@property (nonatomic, assign) BOOL isUpdatingVisibleItems;
@property (nonatomic, strong, readwrite) SmartCollectionViewLayoutCache *layoutCache;
@property (nonatomic, strong, readwrite) SmartCollectionViewVisibilityTracker *visibilityTracker;
@property (nonatomic, strong, readwrite) SmartCollectionViewMountController *mountController;
@property (nonatomic, strong, readwrite) SmartCollectionViewEventBus *eventBus;
@property (nonatomic, strong, readwrite) SmartCollectionViewScheduler *scheduler;
@property (nonatomic, strong, readwrite) SmartCollectionViewReusePool *reusePool;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *appliedIndicesThisTick;
@property (nonatomic, assign) BOOL hasScrolled; // Track if user has scrolled (to switch from initial to scroll props)

- (NSInteger)itemCount;
- (CGSize)sizeForItemAtIndex:(NSInteger)index;
- (UIView *)viewForItemAtIndex:(NSInteger)index;
- (CGSize)metadataSizeForItemAtIndex:(NSInteger)index;
- (SmartCollectionViewWrapperView *)dequeueWrapper;
- (void)recycleWrapper:(SmartCollectionViewWrapperView *)wrapper;
- (void)ensureWrapperPoolCapacity;
- (NSInteger)estimatedItemsPerViewport;

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
    _layoutCache = [[SmartCollectionViewLayoutCache alloc] init];
    _cumulativeOffsets = [NSMutableArray array];
    _childViewRegistry = [NSMutableDictionary dictionary];
    _indexToWrapper = [NSMutableDictionary dictionary];
    _wrapperReusePool = [NSMutableArray array];
    _renderedIndices = [NSMutableSet set];
    __weak typeof(self) weakSelf = self;
    _visibilityTracker = [[SmartCollectionViewVisibilityTracker alloc] initWithSizeProvider:^CGSize(NSInteger index) {
        return [weakSelf sizeForItemAtIndex:index];
    }];
    _visibilityTracker.horizontal = YES;
    _eventBus = [[SmartCollectionViewEventBus alloc] initWithOwner:self];
    
    // Default values
    _initialNumToRender = 10;
    _maxToRenderPerBatch = 10;
    _overscanCount = 5;
    _overscanLength = 1.0;
    _shadowBufferMultiplier = 2.0; // Default: request 2x the mount range
    _initialMaxToRenderPerBatch = 0; // 0 = use maxToRenderPerBatch
    _initialOverscanCount = 0; // 0 = use overscanCount
    _initialOverscanLength = 0; // 0 = use overscanLength
    _initialShadowBufferMultiplier = 0; // 0 = use shadowBufferMultiplier
    _hasScrolled = NO;
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

    _mountController = [[SmartCollectionViewMountController alloc] initWithContainerView:_containerView];
    _reusePool = [[SmartCollectionViewReusePool alloc] init];
    _scheduler = [[SmartCollectionViewScheduler alloc] initWithOwner:self
                                                         layoutCache:_layoutCache
                                                  visibilityTracker:_visibilityTracker
                                                    mountController:_mountController
                                                           eventBus:_eventBus];
    _scheduler.horizontal = _horizontal;
    _scheduler.initialNumToRender = _initialNumToRender;
    [self updateSchedulerWithEffectiveValues];
    _appliedIndicesThisTick = [NSMutableSet set];
    
    SCVLog(@"SmartCollectionView initialized with scrollView");
    // BREAKPOINT: Set breakpoint here to check reactTag after initialization
    // Note: reactTag might not be set immediately, check again in didMoveToWindow
}

- (NSInteger)estimatedItemsPerViewport
{
    if (!_horizontal) {
        return 1;
    }
    CGFloat viewport = MAX(self.bounds.size.width, 1);
    CGFloat item = MAX(_estimatedItemSize.width, 1);
    NSInteger per = (NSInteger)ceil(viewport / item);
    return MAX(1, per);
}

- (void)ensureWrapperPoolCapacity
{
    // Target pool = (viewport items + overscan*2) * multiplier
    static const NSInteger kPoolMultiplier = 8; // 5-10x viewport suggested; use 8 as default
    NSInteger perViewport = [self estimatedItemsPerViewport];
    NSInteger base = perViewport + (_overscanCount * 2);
    NSInteger target = MAX(8, base * kPoolMultiplier);
    
    NSInteger available = (NSInteger)_wrapperReusePool.count + (NSInteger)_mountedIndices.count;
    NSInteger deficit = target - available;
    if (deficit > 0) {
        for (NSInteger i = 0; i < deficit; i++) {
            SmartCollectionViewWrapperView *wrapper = [[SmartCollectionViewWrapperView alloc] initWithFrame:CGRectZero];
            [_wrapperReusePool addObject:wrapper];
        }
        SCVLog(@"Prewarmed wrapper pool by %ld to size %lu (target %ld)", (long)deficit, (unsigned long)_wrapperReusePool.count, (long)target);
    }
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
    self.scheduler.viewportSize = self.bounds.size;
    self.scheduler.scrollOffset = self.scrollView.contentOffset;
    
    // Ensure we have enough wrappers to avoid rapid reuse churn on fast scrolls
    [self ensureWrapperPoolCapacity];
    
    // Diagnostic: Log reactSubviews to see what React Native thinks our children are
    if (self.reactSubviews.count > 0) {
        for (NSInteger i = 0; i < self.reactSubviews.count; i++) {
            UIView *subview = self.reactSubviews[i];
            SCVLog(@"  reactSubviews[%ld]: %@ (tag: %@)", (long)i, NSStringFromClass([subview class]), subview.reactTag);
        }
    }
    
    // Update scroll view frame
    _scrollView.frame = self.bounds;
    
    // Recompute layout if we have data and need it
    // This handles both initial layout and when bounds become available after being zero
    if ([self itemCount] > 0 && self.localData && self.localData.items.count > 0) {
        if (_needsFullRecompute || CGSizeEqualToSize(_scrollView.contentSize, CGSizeZero)) {
            SCVLog(@"Triggering layout recompute - needsFullRecompute: %@, contentSize: %@", 
                   _needsFullRecompute ? @"YES" : @"NO", NSStringFromCGSize(_scrollView.contentSize));
            [self recomputeLayout];
        }
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
        self.scheduler.totalItemCount = [self itemCount];
        
        SCVLog(@"Added virtual item at index %ld, total items: %ld", (long)index, (long)_virtualItems.count);
        SCVLog(@"Child tag %@ initial frame %@", item.reactTag, NSStringFromCGRect(item.frame));
        
        // DON'T call recomputeLayout here - wait for updateWithLocalData to provide complete metadata
        // Layout will be triggered when localData arrives with all item sizes
        // This prevents multiple layout recomputes with incomplete data
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
        self.scheduler.totalItemCount = [self itemCount];
        
        SCVLog(@"Removed virtual item at index %ld, total items: %ld", (long)index, (long)_virtualItems.count);
        
        [self recomputeLayout];
    }
}

- (void)registerChildView:(UIView *)view atIndex:(NSInteger)index
{
    SCVLog(@"registerChildView: view tag %@ at index %ld", view.reactTag, (long)index);
    
    // Mark this index as rendered
    [_renderedIndices addObject:@(index)];
    [self.scheduler updateRenderedIndices:[NSSet setWithSet:_renderedIndices]];
    
    // Also add to registry immediately by reactTag
    if (view.reactTag != nil) {
        _childViewRegistry[view.reactTag] = view;
        SCVLog(@"Added to childViewRegistry: tag %@", view.reactTag);
    }
    
    [self addVirtualItem:view atIndex:index];
    
    // After adding a new item, check if we should trigger layout and mounting
    // This handles the case where items arrive after scroll (requested via onRequestItems)
    // Throttle: Only trigger update if we don't have a pending update
    if (self.localData && self.localData.items.count > 0 && !self.isUpdatingVisibleItems) {
        // Local data exists, so layout should be possible
        // Trigger update to check if we can now mount items that were waiting
        dispatch_async(dispatch_get_main_queue(), ^{
            // Check if this item is in the current visible/mount range
            NSRange currentRange = [self computeRangeToLayout];
            if (index >= currentRange.location && index < NSMaxRange(currentRange)) {
                SCVLog(@"New item %ld is in current mount range %@ - triggering update", (long)index, NSStringFromRange(currentRange));
                [self updateVisibleItems];
            }
        });
    }
}

- (void)unregisterChildView:(UIView *)view
{
    [self removeVirtualItem:view];
}

- (void)updateWithLocalData:(SmartCollectionViewLocalData *)localData
{
    // BREAKPOINT: Set breakpoint here - this confirms localData arrived from manager
    SCVLog(@"🔥🔥🔥 updateWithLocalData CALLED - version %ld, items %lu, my tag: %@", (long)localData.version, (unsigned long)localData.items.count, self.reactTag);
    
    // Ensure we're on main queue (manager may call from shadow thread)
    dispatch_async(dispatch_get_main_queue(), ^{
        self.localData = localData;
        self.scheduler.totalItemCount = [self itemCount];
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
        
        // Force layout recompute - handle zero bounds case
        if (CGRectEqualToRect(self.bounds, CGRectZero)) {
            SCVLog(@"⚠️  Bounds are zero, will recompute when bounds are set");
            // Layout will be triggered when bounds are set in layoutSubviews
        } else {
            // Bounds are available, compute layout immediately
            [self recomputeLayout];
        }
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
    
    // If bounds are zero, use estimated sizes but still compute layout
    // This allows initial layout to happen even before bounds are set
    BOOL usingEstimatedBounds = CGRectEqualToRect(self.bounds, CGRectZero);
    if (usingEstimatedBounds) {
        SCVLog(@"⚠️  Bounds are zero, using estimated item sizes for initial layout calculation");
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
    [self.layoutCache removeAllSpecs];
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
        
        // Do not read from virtualItems by position; rely on metadata size for now
        
        if (itemSize.height > maxHeight) {
            maxHeight = itemSize.height;
        }
        
        SCVLog(@"Measured item %ld size %@ (maxHeight so far: %.2f)", (long)i, NSStringFromCGSize(itemSize), maxHeight);
    }
    
    SCVLog(@"Max height calculated: %.2f (from %ld items)", maxHeight, (long)itemCount);
    
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
        
        [self.layoutCache setFrame:frame forIndex:i];
        [_cumulativeOffsets addObject:@(currentOffset)];
    }
    
    [self updateContentSize];
    
    // Update scroll view content size
    _scrollView.contentSize = _contentSize;
    _containerView.frame = CGRectMake(0, 0, _contentSize.width, _contentSize.height);
    
    // Update SmartCollectionView height to match max item height
    // Note: If height is explicitly set via style props, React Native will override this
    // Setting frame height here is safe - it will be overridden by Yoga layout if needed
    // Store current height to detect changes
    CGFloat previousHeight = self.frame.size.height;
    if (maxHeight > 0) {
        if (maxHeight != previousHeight) {
            CGRect newFrame = self.frame;
            newFrame.size.height = maxHeight;
            self.frame = newFrame;
            SCVLog(@"Updated SCV frame height: %.2f -> %.2f", previousHeight, maxHeight);
        }
    }
    
    SCVLog(@"Updated scrollView.contentSize %@", NSStringFromCGSize(_contentSize));
    SCVLog(@"Updated SCV frame %@", NSStringFromCGRect(self.frame));

    _lastComputedRange = NSMakeRange(0, itemCount);
    self.scheduler.totalItemCount = itemCount;
    [self.scheduler updateCumulativeOffsets:[_cumulativeOffsets copy]];
    [self.scheduler notifyLayoutRecomputed];
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
    // Use cumulative offsets if available to avoid O(n) prefix sum
    if (range.location > 0 && _cumulativeOffsets.count >= range.location) {
        currentOffset = [_cumulativeOffsets[range.location - 1] doubleValue];
    } else {
        // Fallback: small prefix sum only if needed
        for (NSInteger i = 0; i < range.location; i++) {
            CGSize itemSize = [self estimatedSizeForItemAtIndex:i];
            currentOffset += itemSize.width;
        }
    }
    
    NSInteger totalCount = [self itemCount];
    for (NSInteger i = range.location; i < NSMaxRange(range); i++) {
        if (i < totalCount) {
            CGSize itemSize = [self estimatedSizeForItemAtIndex:i];
            
            // Horizontal layout: items side by side
            CGRect frame = CGRectMake(currentOffset, 0, itemSize.width, self.bounds.size.height);
            currentOffset += itemSize.width;
            
            [self.layoutCache setFrame:frame forIndex:i];
        }
    }
}

- (NSRange)computeRangeToLayout
{
    return [self.scheduler rangeToMount];
}

- (CGSize)estimatedSizeForItemAtIndex:(NSInteger)index
{
    return [self sizeForItemAtIndex:index];
}

- (void)mountVisibleItemsWithBatching
{
    // Ensure layout has run before attempting to mount
    // If layout cache is empty and we have data, layout needs to run first
    if ([self.layoutCache count] == 0 && self.localData && self.localData.items.count > 0 && _needsFullRecompute) {
        SCVLog(@"⚠️  Layout cache is empty but we have data - running layout first before mounting");
        [self performFullLayoutRecompute];
        _needsFullRecompute = NO;
    }
    
    NSRange rangeToMount = [self computeRangeToLayout];
    
    // For initial render, mount all items that React Native rendered (up to initialNumToRender)
    // This ensures we mount items even if they're not yet in the visible range
    // After initial render, we only mount items in the visible range + overscan
    BOOL isInitialRender = (_mountedIndices.count == 0 && _initialNumToRender > 0);
    
    if (isInitialRender) {
        // For initial render, mount items in the visible range + overscan
        // NOT all items up to initialNumToRender - that's only for JS rendering
        // Native should only mount what's actually visible + overscan buffer
        NSMutableArray *itemsToMountArray = [NSMutableArray array];
        
        for (NSInteger i = rangeToMount.location; i < NSMaxRange(rangeToMount); i++) {
            if (![self.mountController isItemMountedAtIndex:i]) {
                SmartCollectionViewLayoutSpec *spec = [self.layoutCache specForIndex:i];
                UIView *view = [self viewForItemAtIndex:i];
                if (spec && view) {
                    [itemsToMountArray addObject:@(i)];
                } else {
                    SCVLog(@"Skipping initial mount of index %ld - frame: %@, view: %@",
                           (long)i, spec ? @"exists" : @"missing", view ? @"exists" : @"missing");
                }
            }
        }
        
        SCVLog(@"Initial render: mounting %ld items from rangeToMount %@ (initialNumToRender=%ld, total available=%ld)", 
               (long)itemsToMountArray.count, NSStringFromRange(rangeToMount), (long)_initialNumToRender, (long)[self itemCount]);
        if (itemsToMountArray.count > 0) {
            [self mountItemsBatched:itemsToMountArray batchSize:_maxToRenderPerBatch];
        } else {
            SCVLog(@"⚠️  No items ready for initial mount - layout may need to run first");
        }
    } else {
        // Normal operation: mount items in visible range + overscan
        NSMutableArray *itemsToMount = [NSMutableArray array];
        
        for (NSInteger i = rangeToMount.location; i < NSMaxRange(rangeToMount); i++) {
            if (![self.mountController isItemMountedAtIndex:i]) {
                SmartCollectionViewLayoutSpec *spec = [self.layoutCache specForIndex:i];
                UIView *view = [self viewForItemAtIndex:i];
                if (spec && view) {
                    [itemsToMount addObject:@(i)];
                }
            } else {
                SCVLog(@"Index %ld already mounted", (long)i);
            }
        }
        
        [self mountItemsBatched:itemsToMount batchSize:_maxToRenderPerBatch];
    }
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
        
        _mountedCount = end;
        
        if (end < items.count) {
            [self mountItemsBatched:items batchSize:size];
        }
    });
}

- (void)mountItemAtIndex:(NSInteger)index
{
    if (index < 0) {
        SCVLog(@"❌ mountItemAtIndex: Invalid index %ld", (long)index);
        return;
    }

    // First, try to get view from registry (preferred - React Native has rendered it)
    UIView *item = [self viewForItemAtIndex:index];
    
    // If no view in registry, try to dequeue from reuse pool (if itemTypes map is provided)
    if (!item && _itemTypes) {
        NSString *itemType = _itemTypes[@(index)];
        if (itemType) {
            item = [_reusePool dequeueViewForItemType:itemType];
            if (item) {
                SCVLog(@"♻️  Reused view from pool for index %ld (type: %@)", (long)index, itemType);
                // Note: Recycled view's reactTag might not match expected tag for this index.
                // React Native will handle reconciliation when JS renders this index.
            }
        }
    }
    
    if (!item) {
        SCVLog(@"❌ mountItemAtIndex: No view available for index %ld", (long)index);
        return;
    }
    
    SmartCollectionViewLayoutSpec *spec = [self.layoutCache specForIndex:index];
    if (!spec) {
        SCVLog(@"❌ mountItemAtIndex: No layout spec for index %ld", (long)index);
        return;
    }

    CGRect frame = spec.frame;
    if (CGRectIsEmpty(frame) || CGRectIsNull(frame)) {
        SCVLog(@"❌ mountItemAtIndex: Invalid frame %@ for index %ld", NSStringFromCGRect(frame), (long)index);
        return;
    }

    SCVLog(@"🔵 mountItemAtIndex: %ld - frame: %@, item tag: %@", (long)index, NSStringFromCGRect(frame), item.reactTag);

    SmartCollectionViewWrapperView *wrapper = _indexToWrapper[@(index)];
    if (!wrapper) {
        wrapper = [self dequeueWrapper];
        if (!wrapper) {
            SCVLog(@"❌ mountItemAtIndex: Failed to get wrapper for index %ld", (long)index);
            return;
        }
        _indexToWrapper[@(index)] = wrapper;
        SCVLog(@"Created new wrapper for index %ld", (long)index);
    } else {
        SCVLog(@"Reusing existing wrapper for index %ld", (long)index);
    }

    wrapper.reactTag = item.reactTag;
    wrapper.currentIndex = @(index);
    wrapper.frame = frame;

    if (wrapper.superview != _containerView) {
        SCVLog(@"Adding wrapper to containerView (index %ld)", (long)index);
        [_containerView addSubview:wrapper];
        SCVLog(@"ContainerView frame: %@, subviews count: %lu", NSStringFromCGRect(_containerView.frame), (unsigned long)_containerView.subviews.count);
    }

    if (item.superview != wrapper) {
        if (item.superview) {
            SCVLog(@"Removing item from old superview: %@", item.superview);
            [item removeFromSuperview];
        }
        item.frame = wrapper.bounds;
        item.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [wrapper addSubview:item];
        [item setNeedsLayout];
        [item layoutIfNeeded];
        SCVLog(@"✅ Added React child to wrapper, child frame: %@, wrapper bounds: %@", NSStringFromCGRect(item.frame), NSStringFromCGRect(wrapper.bounds));
    } else {
        item.frame = wrapper.bounds;
        [item setNeedsLayout];
        [item layoutIfNeeded];
        SCVLog(@"✅ Updated React child frame for reused wrapper");
    }

    if (![_mountedIndices containsObject:@(index)]) {
        [_mountedIndices addObject:@(index)];
        SCVLog(@"✅ Successfully mounted item %ld - wrapper: %@, in hierarchy: %@, mounted count: %lu", 
               (long)index, NSStringFromCGRect(wrapper.frame), wrapper.superview ? @"YES" : @"NO", (unsigned long)_mountedIndices.count);
    } else {
        SCVLog(@"⚠️  Item %ld already in mountedIndices, skipping add", (long)index);
    }
    
    // Verify wrapper is actually in the hierarchy
    if (wrapper.superview != _containerView) {
        SCVLog(@"⚠️  Wrapper for index %ld not in containerView! Re-adding...", (long)index);
        [_containerView addSubview:wrapper];
    }
    
    // Verify item is in wrapper
    if (item.superview != wrapper) {
        SCVLog(@"⚠️  Item for index %ld not in wrapper! Re-adding...", (long)index);
        [item removeFromSuperview];
        item.frame = wrapper.bounds;
        item.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [wrapper addSubview:item];
        [item setNeedsLayout];
        [item layoutIfNeeded];
    }
    
    // After mounting and laying out, measure the actual item height
    // This is important because the item's intrinsic content size might be larger than estimated
    [item layoutIfNeeded]; // Ensure item is fully laid out
    CGSize itemActualSize = item.frame.size;
    
    // Check if this item's actual height is larger than what we calculated
    // If so, we need to recalculate layout with the new max height
    if (itemActualSize.height > 0) {
        // Get the current max height from our layout cache
        CGFloat currentCalculatedMaxHeight = 0;
        for (SmartCollectionViewLayoutSpec *existingSpec in [self.layoutCache allSpecs]) {
            if (existingSpec.frame.size.height > currentCalculatedMaxHeight) {
                currentCalculatedMaxHeight = existingSpec.frame.size.height;
            }
        }

        if (itemActualSize.height > currentCalculatedMaxHeight) {
            SCVLog(@"⚠️  Mounted item %ld has actual height %.2f > calculated max %.2f, triggering height recalculation",
                   (long)index, itemActualSize.height, currentCalculatedMaxHeight);

            spec.frame = CGRectMake(spec.frame.origin.x,
                                    spec.frame.origin.y,
                                    spec.frame.size.width,
                                    itemActualSize.height);
            [self.layoutCache setSpec:spec forIndex:index];

            _needsFullRecompute = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self recomputeLayout];
            });
        }
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
                
                // Enqueue to reuse pool if itemTypes map is provided
                if (_itemTypes) {
                    NSString *itemType = _itemTypes[@(index)];
                    if (itemType) {
                        [_reusePool enqueueView:item forItemType:itemType];
                        SCVLog(@"♻️  Enqueued view to reuse pool for index %ld (type: %@)", (long)index, itemType);
                    }
                }
            }
            [wrapper removeFromSuperview];
            wrapper.reactTag = nil;
            wrapper.currentIndex = nil;
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

- (void)updateSchedulerWithEffectiveValues
{
    // Get effective values based on scroll state
    NSInteger effectiveMaxBatch = [self effectiveMaxToRenderPerBatch];
    NSInteger effectiveOverscanCount = [self effectiveOverscanCount];
    CGFloat effectiveOverscanLength = [self effectiveOverscanLength];
    CGFloat effectiveShadowBuffer = [self effectiveShadowBufferMultiplier];
    
    self.scheduler.maxToRenderPerBatch = effectiveMaxBatch;
    self.scheduler.overscanCount = effectiveOverscanCount;
    self.scheduler.overscanLength = effectiveOverscanLength;
    self.scheduler.shadowBufferMultiplier = effectiveShadowBuffer;
}

- (NSInteger)effectiveMaxToRenderPerBatch
{
    if (!_hasScrolled && _initialMaxToRenderPerBatch > 0) {
        return _initialMaxToRenderPerBatch;
    }
    return _maxToRenderPerBatch;
}

- (NSInteger)effectiveOverscanCount
{
    if (!_hasScrolled && _initialOverscanCount > 0) {
        return _initialOverscanCount;
    }
    return _overscanCount;
}

- (CGFloat)effectiveOverscanLength
{
    if (!_hasScrolled) {
        // If either initial overscan value is provided, use that specific one
        if (_initialOverscanCount > 0) {
            return 0; // Count takes precedence, ignore length
        }
        if (_initialOverscanLength > 0) {
            return _initialOverscanLength;
        }
    }
    return _overscanLength;
}

- (CGFloat)effectiveShadowBufferMultiplier
{
    if (!_hasScrolled && _initialShadowBufferMultiplier > 0) {
        return _initialShadowBufferMultiplier;
    }
    return _shadowBufferMultiplier;
}

- (void)requestItemsForVisibleRange
{
    [self updateSchedulerWithEffectiveValues]; // Update before requesting
    [self.scheduler requestItemsIfNeeded];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    // Mark as scrolled on first scroll
    if (!_hasScrolled && (scrollView.contentOffset.x != 0 || scrollView.contentOffset.y != 0)) {
        _hasScrolled = YES;
        [self updateSchedulerWithEffectiveValues]; // Switch to scroll props
    }
    
    _scrollOffset = scrollView.contentOffset.x; // Horizontal scroll offset
    self.scheduler.scrollOffset = scrollView.contentOffset;
    self.scheduler.viewportSize = scrollView.bounds.size;
    self.scheduler.totalItemCount = [self itemCount];

    CGPoint velocity = CGPointZero;
    if (scrollView.isTracking || scrollView.isDecelerating) {
        velocity = [scrollView.panGestureRecognizer velocityInView:scrollView];
    }
    [self.eventBus emitScrollWithOffset:scrollView.contentOffset
                                velocity:velocity
                                 content:scrollView.contentSize
                                 visible:scrollView.bounds.size];

    [self.scheduler requestItemsIfNeeded];
    [self updateVisibleItems];

    NSRange visibleRange = [self.scheduler visibleRange];
    [self.eventBus emitVisibleRange:visibleRange];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self.eventBus emitScrollBeginDrag];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    [self.eventBus emitScrollEndDrag];

    if (!decelerate) {
        [self.eventBus emitScrollEndDecelerating];
    }
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView
{
    [self.eventBus emitMomentumScrollBegin];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self.eventBus emitMomentumScrollEnd];
    [self.eventBus emitScrollEndDecelerating];
    [self.scheduler requestItemsIfNeeded];
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
    return [self.scheduler visibleRange];
}

- (void)updateVisibleItems
{
    // Prevent re-entrant calls
    if (self.isUpdatingVisibleItems) {
        SCVLog(@"⚠️  updateVisibleItems already in progress, skipping");
        return;
    }
    
    self.isUpdatingVisibleItems = YES;
    [self.appliedIndicesThisTick removeAllObjects];
    
    NSRange visibleRange = [self visibleItemRange];
    NSRange rangeToMount = [self computeRangeToLayout];
    
    SCVLog(@"Visible range %@, rangeToMount %@", NSStringFromRange(visibleRange), NSStringFromRange(rangeToMount));
    
    // First, check which items in rangeToMount actually have views available
    NSMutableSet *itemsReadyToMount = [NSMutableSet set];
    NSMutableSet *itemsNotReady = [NSMutableSet set];
    
    for (NSInteger i = rangeToMount.location; i < NSMaxRange(rangeToMount); i++) {
        UIView *view = [self viewForItemAtIndex:i];
        SmartCollectionViewLayoutSpec *spec = [self.layoutCache specForIndex:i];
        if (view && spec) {
            [itemsReadyToMount addObject:@(i)];
        } else {
            [itemsNotReady addObject:@(i)];
            SCVLog(@"Item %ld not ready: view=%@, spec=%@", (long)i, view ? @"YES" : @"NO", spec ? @"YES" : @"NO");
        }
    }
    
    // Only unmount items if we have replacements ready, OR if they're far outside the visible range
    // Use a larger unmount threshold to prevent premature unmounting
    NSRange unmountRange = [self expandRangeWithOverscan:visibleRange];
    NSInteger unmountThreshold = _overscanCount * 2; // Items beyond 2x overscan are safe to unmount
    
    NSMutableSet *indicesToUnmount = [NSMutableSet set];
    for (NSNumber *mountedIndex in _mountedIndices) {
        NSInteger index = [mountedIndex integerValue];
        
        // Unmount if:
        // 1. Item is outside the unmount range (far from visible)
        // 2. OR item is outside rangeToMount AND we have at least one replacement ready
        BOOL isFarOutsideVisible = (index < unmountRange.location - unmountThreshold || 
                                   index >= NSMaxRange(unmountRange) + unmountThreshold);
        BOOL hasReplacementReady = (itemsReadyToMount.count > 0 && index < rangeToMount.location);
        
        if (isFarOutsideVisible || (hasReplacementReady && index < rangeToMount.location)) {
            [indicesToUnmount addObject:mountedIndex];
        } else if (index >= NSMaxRange(rangeToMount) && itemsReadyToMount.count > 0) {
            // Also unmount items beyond rangeToMount if we have replacements
            [indicesToUnmount addObject:mountedIndex];
        }
    }
    
    // Mount items that are ready (mount before unmount to reduce churn)
    SCVLog(@"Mounting %lu ready items: %@", (unsigned long)itemsReadyToMount.count, itemsReadyToMount);
    SCVLog(@"Currently mounted indices: %@", _mountedIndices);
    
    NSInteger mountedCount = 0;
    NSInteger updatedCount = 0;
    NSInteger newMountCount = 0;
    
    for (NSNumber *indexNumber in itemsReadyToMount) {
        NSInteger i = [indexNumber integerValue];
        if ([self.appliedIndicesThisTick containsObject:indexNumber]) {
            continue; // assignment dedupe per tick
        }
        SmartCollectionViewLayoutSpec *spec = [self.layoutCache specForIndex:i];
        CGRect frame = spec ? [spec frame] : CGRectZero;

        if ([_mountedIndices containsObject:indexNumber]) {
            // Item already mounted - verify it's still in hierarchy and update if needed
            SmartCollectionViewWrapperView *wrapper = _indexToWrapper[indexNumber];
            if (!wrapper) {
                SCVLog(@"⚠️  Item %ld marked as mounted but no wrapper found! Re-mounting", (long)i);
                [_mountedIndices removeObject:indexNumber];
                [self mountItemAtIndex:i];
                newMountCount++;
            } else {
                // Verify wrapper is in containerView
                if (wrapper.superview != _containerView) {
                    SCVLog(@"⚠️  Item %ld wrapper not in containerView! Re-adding...", (long)i);
                    [_containerView addSubview:wrapper];
                    updatedCount++;
                }
                
                // Get the actual item view for this index
                UIView *item = [self viewForItemAtIndex:i];
                
                // Verify item is in wrapper
                UIView *child = wrapper.subviews.firstObject;
                if (!child || (item && child != item)) {
                    SCVLog(@"⚠️  Item %ld child not in wrapper! Re-adding...", (long)i);
                    if (item) {
                        if (item.superview) {
                            [item removeFromSuperview];
                        }
                        item.frame = wrapper.bounds;
                        item.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                        [wrapper addSubview:item];
                        [item setNeedsLayout];
                        [item layoutIfNeeded];
                        updatedCount++;
                    } else {
                        SCVLog(@"⚠️  Item %ld view not found for verification!", (long)i);
                    }
                }
                
                // Update frame if needed
                if (!CGRectEqualToRect(wrapper.frame, frame) && !CGRectEqualToRect(frame, CGRectZero)) {
                    SCVLog(@"Updating mounted wrapper for index %ld: %@ -> %@", (long)i, NSStringFromCGRect(wrapper.frame), NSStringFromCGRect(frame));
                    wrapper.frame = frame;
                    if (child) {
                        child.frame = wrapper.bounds;
                        [child setNeedsLayout];
                        [child layoutIfNeeded];
                    }
                    updatedCount++;
                } else {
                    SCVLog(@"Item %ld already mounted with correct frame %@", (long)i, NSStringFromCGRect(frame));
                }
            }
            mountedCount++;
        } else {
            // Item not mounted yet - mount it
            SCVLog(@"Mounting new item %ld", (long)i);
            [self mountItemAtIndex:i];
            newMountCount++;
        }
        [self.appliedIndicesThisTick addObject:indexNumber];
    }
    
    // Now unmount after mounts to avoid immediate reuse of just-unmounted wrappers
    SCVLog(@"Unmounting %lu items: %@", (unsigned long)indicesToUnmount.count, indicesToUnmount);
    for (NSNumber *indexNum in indicesToUnmount) {
        [self unmountItemAtIndex:[indexNum integerValue]];
    }
    
    SCVLog(@"Mount summary: %ld already mounted, %ld updated, %ld newly mounted", (long)mountedCount, (long)updatedCount, (long)newMountCount);
    SCVLog(@"Final mounted indices: %@", _mountedIndices);
    
    // Log items that were requested but aren't ready yet
    if (itemsNotReady.count > 0) {
        SCVLog(@"⚠️  %lu items in rangeToMount but not ready yet: %@", (unsigned long)itemsNotReady.count, itemsNotReady);
    }
    
    self.isUpdatingVisibleItems = NO;
}

- (SmartCollectionViewWrapperView *)dequeueWrapper
{
    // Disable reuse for now: always create a fresh wrapper to avoid stale child flashes
    SmartCollectionViewWrapperView *wrapper = [[SmartCollectionViewWrapperView alloc] initWithFrame:CGRectZero];
    [wrapper.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    return wrapper;
}

- (void)recycleWrapper:(SmartCollectionViewWrapperView *)wrapper
{
    if (!wrapper) {
        return;
    }
    // Drop wrappers instead of pooling to keep behavior simple and avoid reuse artifacts
    [wrapper.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    wrapper.frame = CGRectZero;
    wrapper.reactTag = nil;
    [wrapper removeFromSuperview];
}

- (void)setHorizontal:(BOOL)horizontal
{
    if (_horizontal == horizontal) {
        return;
    }

    _horizontal = horizontal;
    self.scheduler.horizontal = horizontal;
    
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

- (void)setOverscanCount:(NSInteger)overscanCount
{
    if (_overscanCount == overscanCount) {
        return;
    }
    _overscanCount = overscanCount;
    [self updateSchedulerWithEffectiveValues];
}

- (void)setOverscanLength:(CGFloat)overscanLength
{
    if (fabs(_overscanLength - overscanLength) < DBL_EPSILON) {
        return;
    }
    _overscanLength = overscanLength;
    [self updateSchedulerWithEffectiveValues];
}

- (void)setShadowBufferMultiplier:(CGFloat)shadowBufferMultiplier
{
    if (fabs(_shadowBufferMultiplier - shadowBufferMultiplier) < DBL_EPSILON) {
        return;
    }
    _shadowBufferMultiplier = shadowBufferMultiplier;
    [self updateSchedulerWithEffectiveValues];
}

- (void)setInitialMaxToRenderPerBatch:(NSInteger)initialMaxToRenderPerBatch
{
    if (_initialMaxToRenderPerBatch == initialMaxToRenderPerBatch) {
        return;
    }
    _initialMaxToRenderPerBatch = initialMaxToRenderPerBatch;
    [self updateSchedulerWithEffectiveValues];
}

- (void)setInitialOverscanCount:(NSInteger)initialOverscanCount
{
    if (_initialOverscanCount == initialOverscanCount) {
        return;
    }
    _initialOverscanCount = initialOverscanCount;
    [self updateSchedulerWithEffectiveValues];
}

- (void)setInitialOverscanLength:(CGFloat)initialOverscanLength
{
    if (fabs(_initialOverscanLength - initialOverscanLength) < DBL_EPSILON) {
        return;
    }
    _initialOverscanLength = initialOverscanLength;
    [self updateSchedulerWithEffectiveValues];
}

- (void)setInitialShadowBufferMultiplier:(CGFloat)initialShadowBufferMultiplier
{
    if (fabs(_initialShadowBufferMultiplier - initialShadowBufferMultiplier) < DBL_EPSILON) {
        return;
    }
    _initialShadowBufferMultiplier = initialShadowBufferMultiplier;
    [self updateSchedulerWithEffectiveValues];
}

- (void)setInitialNumToRender:(NSInteger)initialNumToRender
{
    if (_initialNumToRender == initialNumToRender) {
        return;
    }
    _initialNumToRender = initialNumToRender;
    self.scheduler.initialNumToRender = initialNumToRender;
}

- (void)setMaxToRenderPerBatch:(NSInteger)maxToRenderPerBatch
{
    if (_maxToRenderPerBatch == maxToRenderPerBatch) {
        return;
    }
    _maxToRenderPerBatch = maxToRenderPerBatch;
    [self updateSchedulerWithEffectiveValues];
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
