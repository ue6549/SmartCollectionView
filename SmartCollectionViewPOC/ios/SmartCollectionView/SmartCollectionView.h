#import <React/RCTView.h>
#import <React/RCTComponent.h>

@interface SmartCollectionView : RCTView <UIScrollViewDelegate>

// Virtualization properties
@property (nonatomic, assign) NSInteger initialNumToRender;
@property (nonatomic, assign) NSInteger maxToRenderPerBatch;
@property (nonatomic, assign) NSInteger overscanCount;
@property (nonatomic, assign) CGFloat overscanLength;
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
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *containerView;

// Data and layout
@property (nonatomic, strong) NSMutableArray<UIView *> *virtualItems;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *layoutCache;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *cumulativeOffsets;
@property (nonatomic, assign) NSRange lastComputedRange;
@property (nonatomic, assign) BOOL needsFullRecompute;

// Mounting state
@property (nonatomic, strong) NSMutableSet<NSNumber *> *mountedIndices;
@property (nonatomic, assign) NSInteger mountedCount;

// Scroll tracking
@property (nonatomic, assign) CGFloat scrollOffset;
@property (nonatomic, assign) CGSize contentSize;

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
