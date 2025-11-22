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
#import "SmartCollectionViewItemView.h"

// Debug logging helper (temporarily enabled for diagnostics)
#define SCVLog(fmt, ...) // RCTLogInfo(@"[SCV] " fmt, ##__VA_ARGS__)

// Reuse pool logs are always enabled (not conditional on DEBUG)
#define SCVReusePoolLog(fmt, ...) // RCTLogInfo(@"[SCV-ReusePool] " fmt, ##__VA_ARGS__)

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
    _virtualItems = [NSMutableDictionary dictionary];
    _layoutCache = [[SmartCollectionViewLayoutCache alloc] init];
    _cumulativeOffsets = [NSMutableArray array];
    _childViewRegistry = [NSMutableDictionary dictionary];
    _indexToWrapper = [NSMutableDictionary dictionary];
    _wrapperReusePool = [NSMutableArray array];
    _renderedIndices = [NSMutableSet set];
    _mountedIndices = [NSMutableSet set];
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
    _itemSpacing = 0; // Default: no spacing between items
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
    if (index < 0) {
        return;
    }
    
    NSNumber *indexKey = @(index);
    NSNumber *reactTag = item.reactTag;
    if (reactTag != nil) {
        _childViewRegistry[reactTag] = item;
    }
    
    if (item.superview != nil) {
        [item removeFromSuperview];
    }
    
    _virtualItems[indexKey] = item;
    _needsFullRecompute = YES;
    self.scheduler.totalItemCount = [self itemCount];
    
    SCVLog(@"Added virtual item at index %ld, total tracked items: %lu", (long)index, (unsigned long)_virtualItems.count);
    SCVLog(@"Child tag %@ initial frame %@", item.reactTag, NSStringFromCGRect(item.frame));
    
    // DON'T call recomputeLayout here - wait for updateWithLocalData to provide complete metadata
    // Layout will be triggered when localData arrives with all item sizes
    // This prevents multiple layout recomputes with incomplete data
}

- (void)removeVirtualItem:(UIView *)item atIndex:(NSInteger)index
{
    NSNumber *indexKey = @(index);
    UIView *storedItem = _virtualItems[indexKey];
    if (storedItem != item) {
        // Fallback: find by pointer if indices mismatched (e.g., unexpected view type)
        for (NSNumber *key in _virtualItems.allKeys) {
            if (_virtualItems[key] == item) {
                indexKey = key;
                storedItem = item;
                break;
            }
        }
    }
    
    if (!storedItem) {
        return;
    }
    
    [_virtualItems removeObjectForKey:indexKey];
    NSNumber *reactTag = item.reactTag;
    if (reactTag != nil) {
        [_childViewRegistry removeObjectForKey:reactTag];
    }
    [_mountedIndices removeObject:indexKey];
    _needsFullRecompute = YES;
    self.scheduler.totalItemCount = [self itemCount];
    
    SCVLog(@"Removed virtual item at index %@, total tracked items: %lu", indexKey, (unsigned long)_virtualItems.count);
    
    [self recomputeLayout];
}

- (NSInteger)effectiveItemIndexForView:(UIView *)view fallback:(NSInteger)fallback
{
    if ([view isKindOfClass:[SmartCollectionViewItemView class]]) {
        SmartCollectionViewItemView *itemView = (SmartCollectionViewItemView *)view;
        if (itemView.itemIndex >= 0) {
            return itemView.itemIndex;
        }
    }
    
    if (fallback != NSNotFound) {
        return fallback;
    }
    
    __block NSInteger resolvedIndex = NSNotFound;
    [_virtualItems enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, UIView *obj, BOOL *stop) {
        if (obj == view) {
            resolvedIndex = [key integerValue];
            *stop = YES;
        }
    }];
    
    return resolvedIndex;
}

- (void)registerChildView:(UIView *)view atIndex:(NSInteger)index
{
    NSInteger effectiveIndex = [self effectiveItemIndexForView:view fallback:index];
    
    SCVLog(@"registerChildView: view tag %@ mapped to data index %ld (react index %ld)", view.reactTag, (long)effectiveIndex, (long)index);
    
    // Mark this index as rendered
    [_renderedIndices addObject:@(effectiveIndex)];
    [self.scheduler updateRenderedIndices:[NSSet setWithSet:_renderedIndices]];
    
    // Also add to registry immediately by reactTag
    if (view.reactTag != nil) {
        _childViewRegistry[view.reactTag] = view;
        SCVLog(@"Added to childViewRegistry: tag %@", view.reactTag);
    }
    
    [self addVirtualItem:view atIndex:effectiveIndex];
    
    // After adding a new item, check if we should trigger layout and mounting
    // This handles the case where items arrive after scroll (requested via onRequestItems)
    // Throttle: Only trigger update if we don't have a pending update
    if (self.localData && self.localData.items.count > 0 && !self.isUpdatingVisibleItems) {
        // Local data exists, so layout should be possible
        // Trigger update to check if we can now mount items that were waiting
        dispatch_async(dispatch_get_main_queue(), ^{
            // Check if this item is in the current visible/mount range
            NSRange currentRange = [self computeRangeToLayout];
            if (effectiveIndex >= currentRange.location && effectiveIndex < NSMaxRange(currentRange)) {
                SCVLog(@"New item %ld is in current mount range %@ - triggering update", (long)effectiveIndex, NSStringFromRange(currentRange));
                [self updateVisibleItems];
            }
        });
    }
}

- (void)unregisterChildView:(UIView *)view
{
    NSInteger effectiveIndex = [self effectiveItemIndexForView:view fallback:NSNotFound];
    if (effectiveIndex != NSNotFound) {
        [self removeVirtualItem:view atIndex:effectiveIndex];
    }
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
    
    // First, try to find by index in virtualItems (works even after recycling when reactTag changes)
    NSNumber *indexKey = @(index);
    UIView *view = _virtualItems[indexKey];
    if (view) {
        SCVLog(@"Found view for index %ld in virtualItems (tag: %@)", (long)index, view.reactTag);
        return view;
    }
    
    // Fallback: try reactTag lookup from metadata (for non-recycled views)
    if (self.localData && index < self.localData.items.count) {
        SmartCollectionViewItemMetadata *metadata = self.localData.items[index];
        SCVLog(@"Looking for view with reactTag %@ in registry (count: %lu)", metadata.reactTag, (unsigned long)_childViewRegistry.count);
        
        view = _childViewRegistry[metadata.reactTag];
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

- (void)applyItemFrame:(UIView *)item toWrapper:(SmartCollectionViewWrapperView *)wrapper
{
    if (!item || !wrapper) {
        return;
    }
    
    if (item.superview != wrapper) {
        if (item.superview) {
            [item removeFromSuperview];
        }
        [wrapper addSubview:item];
    }
    
    CGRect bounds = wrapper.bounds;
    if (!CGRectEqualToRect(item.frame, bounds)) {
        item.frame = bounds;
    }
    item.autoresizingMask = UIViewAutoresizingNone;
    [item setNeedsLayout];
    [item layoutIfNeeded];
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
        // Add spacing before each item (except the first one)
        if (i > 0) {
            currentOffset += _itemSpacing;
        }
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
    UIView *item = nil;
    BOOL isRecycled = NO;
    
    if (_itemTypes) {
        NSString *itemType = _itemTypes[@(index)];
        SCVReusePoolLog(@"🔍 mountItemAtIndex %ld: Checking reuse pool first, itemType from map: %@", (long)index, itemType ?: @"nil");
        if (itemType) {
            item = [_reusePool dequeueViewForItemType:itemType];
            if (item) {
                isRecycled = YES;
                SCVReusePoolLog(@"♻️  Reused view from pool for index %ld (type: %@)", (long)index, itemType);
                if (item.reactTag) {
                    [_childViewRegistry removeObjectForKey:item.reactTag];
                }
                
                // Update props to trigger React Native reconciliation
                if ([item isKindOfClass:[SmartCollectionViewItemView class]]) {
                    SmartCollectionViewItemView *itemView = (SmartCollectionViewItemView *)item;
                    
                    // Enter placeholder mode while React Native updates content
                    [itemView enterPlaceholderMode];
                    
                    // Update props - React Native will reconcile when these change
                    // Store old values to force change detection
                    NSInteger oldIndex = itemView.itemIndex;
                    NSString *oldType = itemView.itemType;
                    
                    itemView.itemIndex = index;
                    itemView.itemType = itemType;
                    SCVReusePoolLog(@"✅ Updated recycled view props: itemIndex %ld -> %ld, itemType %@ -> %@", 
                                   (long)oldIndex, (long)index, oldType ?: @"nil", itemType ?: @"nil");
                    
                    // Force React Native to see the prop change by triggering multiple reconciliation passes
                    // This is especially important when scrolling backward
                    [itemView setNeedsLayout];
                    [itemView layoutIfNeeded];
                    
                    // Force parent to update (helps trigger React Native reconciliation)
                    if (itemView.superview) {
                        [itemView.superview setNeedsLayout];
                        [itemView.superview layoutIfNeeded];
                    }
                    
                    // Trigger React Native's didUpdateReactSubviews by forcing a layout pass
                    // This helps ensure React Native sees the prop change and reconciles
                    [itemView setNeedsUpdateConstraints];
                    [itemView updateConstraintsIfNeeded];
                }
            }
        }
    }
    
    if (!item) {
        item = [self viewForItemAtIndex:index];
    }
    
    // If still no item, create a placeholder view to prevent blank space
    if (!item) {
        SCVLog(@"⚠️  mountItemAtIndex: No view available for index %ld, creating placeholder", (long)index);
        SmartCollectionViewItemView *placeholderView = [[SmartCollectionViewItemView alloc] initWithFrame:CGRectZero];
        placeholderView.itemIndex = index;
        if (_itemTypes) {
            placeholderView.itemType = _itemTypes[@(index)];
        }
        [placeholderView enterPlaceholderMode];
        item = placeholderView;
    }
    
    NSNumber *indexKey = @(index);
    _virtualItems[indexKey] = item;
    if (item.reactTag) {
        _childViewRegistry[item.reactTag] = item;
    }
    
    SmartCollectionViewLayoutSpec *spec = [self.layoutCache specForIndex:index];
    if (!spec) {
        SCVLog(@"❌ mountItemAtIndex: No layout spec for index %ld", (long)index);
        return;
    }
    CGRect frame = spec.frame;
    if (CGRectIsEmpty(frame) || CGRectIsNull(frame) || frame.size.width <= 0 || frame.size.height <= 0) {
        SCVLog(@"❌ mountItemAtIndex: Invalid frame %@ for index %ld", NSStringFromCGRect(frame), (long)index);
        return;
    }
    
    SmartCollectionViewWrapperView *wrapper = _indexToWrapper[@(index)];
    if (!wrapper) {
        wrapper = [self dequeueWrapper];
        if (!wrapper) {
            SCVLog(@"❌ mountItemAtIndex: Failed to get wrapper for index %ld", (long)index);
            return;
        }
        _indexToWrapper[@(index)] = wrapper;
    }
    
    wrapper.reactTag = item.reactTag;
    wrapper.currentIndex = @(index);
    wrapper.frame = frame;
    
    if (wrapper.superview != _containerView) {
        [_containerView addSubview:wrapper];
    }
    
    [self applyItemFrame:item toWrapper:wrapper];
    
    if (![_mountedIndices containsObject:indexKey]) {
        [_mountedIndices addObject:indexKey];
    }
    
    // For recycled views, schedule multiple deferred checks to ensure content updated
    // This is critical when scrolling backward as React Native reconciliation can be slower
    if (isRecycled && [item isKindOfClass:[SmartCollectionViewItemView class]]) {
        SmartCollectionViewItemView *itemView = (SmartCollectionViewItemView *)item;
        NSInteger checkIndex = index; // Capture index for deferred checks
        
        // First check: immediate (next run loop)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self checkAndPromoteRecycledView:itemView atIndex:checkIndex attempt:1];
        });
        
        // Second check: after a short delay (for slower reconciliations)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self checkAndPromoteRecycledView:itemView atIndex:checkIndex attempt:2];
        });
        
        // Third check: after longer delay (fallback for very slow reconciliations)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self checkAndPromoteRecycledView:itemView atIndex:checkIndex attempt:3];
        });
    }
    
    SCVLog(@"✅ Mounted item %ld - wrapper: %@, item frame: %@, recycled: %@", 
           (long)index, NSStringFromCGRect(wrapper.frame), NSStringFromCGRect(item.frame), 
           isRecycled ? @"YES" : @"NO");
}


- (void)unmountItemAtIndex:(NSInteger)index
{
    SCVReusePoolLog(@"🔍 unmountItemAtIndex called for index %ld", (long)index);
    
    if ([_mountedIndices containsObject:@(index)]) {
        SmartCollectionViewWrapperView *wrapper = _indexToWrapper[@(index)];
        SCVReusePoolLog(@"🔍 unmountItemAtIndex %ld: wrapper exists: %@, subviews count: %lu", 
                        (long)index, wrapper ? @"YES" : @"NO", (unsigned long)wrapper.subviews.count);
        
        if (wrapper) {
            UIView *item = wrapper.subviews.firstObject;
            SCVReusePoolLog(@"🔍 unmountItemAtIndex %ld: item exists: %@, _itemTypes exists: %@", 
                            (long)index, item ? @"YES" : @"NO", _itemTypes ? @"YES" : @"NO");
            
            if (item) {
                [item removeFromSuperview];
                
                // Enqueue to reuse pool if itemTypes map is provided
                if (_itemTypes) {
                    NSString *itemType = _itemTypes[@(index)];
                    SCVReusePoolLog(@"🔍 unmountItemAtIndex %ld: itemType from map: %@", (long)index, itemType ?: @"nil");
                    
                    if (itemType) {
                        [_reusePool enqueueView:item forItemType:itemType];
                        SCVReusePoolLog(@"♻️  Enqueued view to reuse pool for index %ld (type: %@)", (long)index, itemType);
                    } else {
                        SCVReusePoolLog(@"⚠️  Attempted to enqueue view for index %ld but no itemType found in map", (long)index);
                    }
                } else {
                    SCVReusePoolLog(@"⚠️  Attempted to enqueue view for index %ld but no itemTypes map provided", (long)index);
                }
            } else {
                SCVReusePoolLog(@"⚠️  unmountItemAtIndex %ld: No item found in wrapper.subviews (count: %lu)", 
                                (long)index, (unsigned long)wrapper.subviews.count);
            }
            [wrapper removeFromSuperview];
            wrapper.reactTag = nil;
            wrapper.currentIndex = nil;
            [self recycleWrapper:wrapper];
            [_indexToWrapper removeObjectForKey:@(index)];
            
            // Remove from virtualItems so the index->view mapping is cleared
            // The view is still accessible via reuse pool or childViewRegistry (by reactTag)
            if (item) {
                NSNumber *indexKey = @(index);
                if (_virtualItems[indexKey] == item) {
                    [_virtualItems removeObjectForKey:indexKey];
                    SCVReusePoolLog(@"Removed view from virtualItems for index %ld", (long)index);
                }
            }
        } else {
            SCVReusePoolLog(@"⚠️  unmountItemAtIndex %ld: No wrapper found in _indexToWrapper", (long)index);
        }
        [_mountedIndices removeObject:@(index)];
    } else {
        SCVReusePoolLog(@"⚠️  unmountItemAtIndex %ld: Index not in _mountedIndices", (long)index);
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

- (void)setItemTypes:(NSDictionary<NSNumber *,NSString *> *)itemTypes
{
    _itemTypes = itemTypes;
    if (itemTypes) {
        SCVReusePoolLog(@"✅ itemTypes set on SmartCollectionView: %lu entries", (unsigned long)itemTypes.count);
    } else {
        SCVReusePoolLog(@"⚠️  itemTypes cleared on SmartCollectionView (set to nil)");
    }
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
    
    // Only unmount items if they're far outside the visible range
    // Unmount threshold equals overscan - items beyond overscan buffer can be safely unmounted
    // Shadow buffer ensures shadow tree is available, recycling makes remounting fast
    NSRange unmountRange = [self expandRangeWithOverscan:visibleRange];
    NSInteger unmountThreshold = _overscanCount; // Items beyond overscan range are safe to unmount (shadow buffer + recycling handle remounting)
    
    NSMutableSet *indicesToUnmount = [NSMutableSet set];
    for (NSNumber *mountedIndex in _mountedIndices) {
        NSInteger index = [mountedIndex integerValue];
        
        // NEVER unmount items in the visible range
        if (index >= visibleRange.location && index < NSMaxRange(visibleRange)) {
            continue; // Keep visible items mounted
        }
        
        // NEVER unmount items in rangeToMount (they're needed soon)
        if (index >= rangeToMount.location && index < NSMaxRange(rangeToMount)) {
            continue; // Keep items in mount range
        }
        
        // Only unmount items that are far outside the visible range
        BOOL isFarOutsideVisible = (index < unmountRange.location - unmountThreshold || 
                                   index >= NSMaxRange(unmountRange) + unmountThreshold);
        
        if (isFarOutsideVisible) {
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
        
        // Validate frame before proceeding
        if (CGRectIsEmpty(frame) || CGRectIsNull(frame) || frame.size.width <= 0 || frame.size.height <= 0) {
            SCVLog(@"⚠️  updateVisibleItems: Skipping item %ld - invalid frame %@", (long)i, NSStringFromCGRect(frame));
            continue;
        }

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
                
                // If no view found, create placeholder to prevent blank space
                if (!item) {
                    SCVLog(@"⚠️  Item %ld view not found, creating placeholder", (long)i);
                    SmartCollectionViewItemView *placeholderView = [[SmartCollectionViewItemView alloc] initWithFrame:CGRectZero];
                    placeholderView.itemIndex = i;
                    if (_itemTypes) {
                        placeholderView.itemType = _itemTypes[@(i)];
                    }
                    [placeholderView enterPlaceholderMode];
                    item = placeholderView;
                    _virtualItems[@(i)] = item;
                }
                
                // Verify item is in wrapper
                UIView *child = wrapper.subviews.firstObject;
                if (!child || (item && child != item)) {
                    SCVLog(@"⚠️  Item %ld child not in wrapper! Re-adding...", (long)i);
                    if (item) {
                        if (item.superview) {
                            [item removeFromSuperview];
                        }
                        [self applyItemFrame:item toWrapper:wrapper];
                        updatedCount++;
                    }
                }
                
                // Update frame if needed
                if (!CGRectEqualToRect(wrapper.frame, frame) && !CGRectEqualToRect(frame, CGRectZero)) {
                    SCVLog(@"Updating mounted wrapper for index %ld: %@ -> %@", (long)i, NSStringFromCGRect(wrapper.frame), NSStringFromCGRect(frame));
                    wrapper.frame = frame;
                    if (child) {
                        // Get actual React child content size (especially important after recycling)
                        CGSize actualItemSize = [self sizeForItemAtIndex:i];
                        
                        // If child is SmartCollectionViewItemView, get actual React content size
                        // contentView.frame.size includes margins, borders, padding (React Native's frame.size)
                        if ([child isKindOfClass:[SmartCollectionViewItemView class]]) {
                            SmartCollectionViewItemView *itemView = (SmartCollectionViewItemView *)child;
                            UIView *contentView = itemView.reactSubviews.firstObject;
                            if (contentView) {
                                // Force layout to ensure React Native has updated content
                                [itemView setNeedsLayout];
                                [itemView layoutIfNeeded];
                                [contentView setNeedsLayout];
                                [contentView layoutIfNeeded];
                                
                                CGSize contentSize = contentView.frame.size;
                                if (!CGSizeEqualToSize(contentSize, CGSizeZero) && contentSize.width > 0 && contentSize.height > 0) {
                                    // Use actual React child content size (includes margins/borders)
                                    actualItemSize = contentSize;
                                    SCVLog(@"🔵 updateVisibleItems %ld: Using actual React child content size (includes margins): %@", (long)i, NSStringFromCGSize(contentSize));
                                }
                            }
                        }
                        
                        if (actualItemSize.width <= 0 || actualItemSize.height <= 0) {
                            actualItemSize = _estimatedItemSize;
                            if (actualItemSize.width <= 0) actualItemSize.width = 100;
                            if (actualItemSize.height <= 0) actualItemSize.height = 80;
                        }
                        
                        CGRect itemFrame = CGRectMake(0, 
                                                      0, // Top-aligned, not centered
                                                      actualItemSize.width, // Use actual width (includes margins)
                                                      actualItemSize.height);
                        child.frame = itemFrame;
                        child.autoresizingMask = UIViewAutoresizingNone; // Use fixed size, no autoresizing
                        
                        // Update wrapper size to match actual content size (includes margins)
                        // Use tolerance to avoid tiny floating-point differences
                        const CGFloat kSizeTolerance = 1.0;
                        if (actualItemSize.width > 0 && actualItemSize.height > 0) {
                            CGRect updatedWrapperFrame = wrapper.frame;
                            BOOL needsUpdate = NO;
                            
                            CGFloat widthDiff = fabs(actualItemSize.width - frame.size.width);
                            CGFloat heightDiff = fabs(actualItemSize.height - frame.size.height);
                            
                            // Update width if significantly different
                            if (widthDiff > kSizeTolerance) {
                                updatedWrapperFrame.size.width = actualItemSize.width;
                                needsUpdate = YES;
                                SCVLog(@"🔵 updateVisibleItems %ld: Updated wrapper width from %.2f to %.2f (diff: %.2f)", (long)i, frame.size.width, actualItemSize.width, widthDiff);
                            }
                            
                            // For height, ensure wrapper is at least content height (to prevent cutting)
                            if (actualItemSize.height > frame.size.height + kSizeTolerance) {
                                updatedWrapperFrame.size.height = actualItemSize.height;
                                needsUpdate = YES;
                                SCVLog(@"🔵 updateVisibleItems %ld: Updated wrapper height from %.2f to %.2f to accommodate content (diff: %.2f)", (long)i, frame.size.height, actualItemSize.height, heightDiff);
                            }
                            
                            if (needsUpdate) {
                                wrapper.frame = updatedWrapperFrame;
                                
                                // CRITICAL: After updating wrapper size, ensure child frame matches with origin (0, 0)
                                if (child && child.superview == wrapper) {
                                    CGRect itemFrame = CGRectMake(0, 0, actualItemSize.width, actualItemSize.height);
                                    child.frame = itemFrame;
                                    SCVLog(@"🔵 updateVisibleItems %ld: Updated child frame to match wrapper: %@ (origin: %.2f, %.2f)", 
                                           (long)i, NSStringFromCGRect(itemFrame), itemFrame.origin.x, itemFrame.origin.y);
                                }
                            }
                        }
                        
                        [child setNeedsLayout];
                        [child layoutIfNeeded];
                        
                        // CRITICAL: Verify and fix child frame origin - must always be (0, 0)
                        if (child.superview == wrapper && (child.frame.origin.x != 0 || child.frame.origin.y != 0)) {
                            CGPoint oldOrigin = child.frame.origin;
                            CGRect correctedFrame = child.frame;
                            correctedFrame.origin = CGPointMake(0, 0);
                            child.frame = correctedFrame;
                            SCVLog(@"⚠️  updateVisibleItems: Fixed child frame origin from (%.2f, %.2f) to (0, 0) for index %ld", 
                                   oldOrigin.x, oldOrigin.y, (long)i);
                        }
                    }
                    updatedCount++;
                } else {
                    SCVLog(@"Item %ld already mounted with correct frame %@", (long)i, NSStringFromCGRect(frame));
                }
				UIView *finalChild = wrapper.subviews.firstObject;
				if (finalChild) {
					[self applyItemFrame:finalChild toWrapper:wrapper];
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
    SCVReusePoolLog(@"🔍 updateVisibleItems: Unmounting %lu items: %@", (unsigned long)indicesToUnmount.count, indicesToUnmount);
    SCVReusePoolLog(@"🔍 updateVisibleItems: Currently mounted indices before unmount: %@", _mountedIndices);
    for (NSNumber *indexNum in indicesToUnmount) {
        SCVReusePoolLog(@"🔍 updateVisibleItems: About to unmount index %ld", (long)[indexNum integerValue]);
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

- (void)checkAndPromoteRecycledView:(SmartCollectionViewItemView *)itemView atIndex:(NSInteger)index attempt:(NSInteger)attempt
{
    if (!itemView) {
        return;
    }
    
    // Verify view is still mounted at this index (hasn't been recycled again)
    NSNumber *indexKey = @(index);
    UIView *currentView = _virtualItems[indexKey];
    if (currentView != itemView || itemView.itemIndex != index) {
        SCVLog(@"⚠️  Recycled view check skipped - view at index %ld has been recycled again or index changed", (long)index);
        return;
    }
    
    // Verify view is still in the hierarchy
    if (!itemView.superview) {
        SCVLog(@"⚠️  Recycled view check skipped - view at index %ld is not in hierarchy", (long)index);
        return;
    }
    
    // Check if content is ready
    if (itemView.isInPlaceholderMode) {
        UIView *contentView = itemView.reactSubviews.firstObject;
        
        // Force layout to ensure React Native has updated
        [itemView setNeedsLayout];
        [itemView layoutIfNeeded];
        if (contentView) {
            [contentView setNeedsLayout];
            [contentView layoutIfNeeded];
        }
        
        // Check if content is now ready
        if (contentView && contentView.frame.size.width > 0 && contentView.frame.size.height > 0) {
            SCVLog(@"✅ Recycled view %ld content ready on attempt %ld, promoting", (long)index, (long)attempt);
            [itemView promoteContentIfAvailable];
        } else if (attempt < 3) {
            SCVLog(@"⚠️  Recycled view %ld still in placeholder mode on attempt %ld, will check again", (long)index, (long)attempt);
        } else {
            SCVLog(@"⚠️  Recycled view %ld still in placeholder mode after all attempts, content may not be ready", (long)index);
            // Force promotion anyway - better to show stale content than blank space
            [itemView promoteContentIfAvailable];
        }
    } else {
        // Already promoted, no need to check
        if (attempt == 1) {
            SCVLog(@"✅ Recycled view %ld already promoted on first check", (long)index);
        }
    }
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
