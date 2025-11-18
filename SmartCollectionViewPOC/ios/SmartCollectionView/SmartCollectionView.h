#import <React/RCTView.h>
#import <React/RCTComponent.h>

@class SmartCollectionViewLayoutCache;
@class SmartCollectionViewVisibilityTracker;
@class SmartCollectionViewMountController;
@class SmartCollectionViewEventBus;
@class SmartCollectionViewScheduler;

@interface SmartCollectionView : RCTView <UIScrollViewDelegate>

// Virtualization properties
@property (nonatomic, assign) NSInteger initialNumToRender;
@property (nonatomic, assign) NSInteger maxToRenderPerBatch;
@property (nonatomic, assign) NSInteger overscanCount;
@property (nonatomic, assign) CGFloat overscanLength;
@property (nonatomic, assign) CGFloat shadowBufferMultiplier; // Multiplier for request range beyond mount range (default: 2.0)

// Initial mount optimization (optional, overrides main props during initial mount)
@property (nonatomic, assign) NSInteger initialMaxToRenderPerBatch; // Default: 0 (use maxToRenderPerBatch)
@property (nonatomic, assign) NSInteger initialOverscanCount; // Default: 0 (use overscanCount)
@property (nonatomic, assign) CGFloat initialOverscanLength; // Default: 0 (use overscanLength)
@property (nonatomic, assign) CGFloat initialShadowBufferMultiplier; // Default: 0 (use shadowBufferMultiplier)

@property (nonatomic, assign) BOOL horizontal;
@property (nonatomic, assign) CGSize estimatedItemSize;
@property (nonatomic, assign) NSInteger totalItemCount;

// Events
@property (nonatomic, copy) RCTDirectEventBlock onRequestItems;
@property (nonatomic, copy) RCTDirectEventBlock onVisibleRangeChange;
@property (nonatomic, copy) RCTDirectEventBlock onScroll;
@property (nonatomic, copy) RCTDirectEventBlock onScrollBeginDrag;
@property (nonatomic, copy) RCTDirectEventBlock onScrollEndDrag;
@property (nonatomic, copy) RCTDirectEventBlock onMomentumScrollBegin;
@property (nonatomic, copy) RCTDirectEventBlock onMomentumScrollEnd;
@property (nonatomic, copy) RCTDirectEventBlock onScrollEndDecelerating;

// Scroll view components
@property (nonatomic, strong, readonly) UIScrollView *scrollView;
@property (nonatomic, strong, readonly) UIView *containerView;

// Data and layout
@property (nonatomic, strong, readonly) NSMutableArray<UIView *> *virtualItems;
@property (nonatomic, strong, readonly) NSMutableArray<NSNumber *> *cumulativeOffsets;
@property (nonatomic, assign, readonly) NSRange lastComputedRange;
@property (nonatomic, assign, readonly) BOOL needsFullRecompute;
@property (nonatomic, strong, readonly) SmartCollectionViewLayoutCache *layoutCache;
@property (nonatomic, strong, readonly) SmartCollectionViewVisibilityTracker *visibilityTracker;
@property (nonatomic, strong, readonly) SmartCollectionViewMountController *mountController;
@property (nonatomic, strong, readonly) SmartCollectionViewEventBus *eventBus;
@property (nonatomic, strong, readonly) SmartCollectionViewScheduler *scheduler;

// Mounting state
@property (nonatomic, strong, readonly) NSMutableSet<NSNumber *> *mountedIndices;
@property (nonatomic, assign, readonly) NSInteger mountedCount;

// Scroll tracking
@property (nonatomic, assign, readonly) CGFloat scrollOffset;
@property (nonatomic, assign, readonly) CGSize contentSize;

// Methods
- (void)addVirtualItem:(UIView *)item atIndex:(NSInteger)index;
- (void)removeVirtualItem:(UIView *)item;
- (void)registerChildView:(UIView *)view atIndex:(NSInteger)index;
- (void)unregisterChildView:(UIView *)view;
- (void)updateWithLocalData:(id)localData;
- (void)recomputeLayout;
- (NSRange)computeRangeToLayout;
- (void)mountVisibleItemsWithBatching;
- (void)mountItemsBatched:(NSArray *)items batchSize:(NSInteger)size;
- (void)mountItemAtIndex:(NSInteger)index;
- (void)unmountItemAtIndex:(NSInteger)index;
- (void)requestItemsForVisibleRange;
- (BOOL)hasRenderedItemAtIndex:(NSInteger)index;
- (NSRange)expandRangeWithOverscan:(NSRange)range;

// Layout computation
- (NSRange)visibleItemRange;
- (CGSize)estimatedSizeForItemAtIndex:(NSInteger)index;
- (CGSize)actualSizeForItem:(UIView *)item;
- (CGFloat)getCumulativeOffsetAtIndex:(NSInteger)index;
- (void)updateContentSize;
- (void)updateVisibleItems;

@end
