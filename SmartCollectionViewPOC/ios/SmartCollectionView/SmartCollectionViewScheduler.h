#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class SmartCollectionView;
@class SmartCollectionViewLayoutCache;
@class SmartCollectionViewVisibilityTracker;
@class SmartCollectionViewMountController;
@class SmartCollectionViewEventBus;

NS_ASSUME_NONNULL_BEGIN

@interface SmartCollectionViewScheduler : NSObject

@property (nonatomic, weak, readonly) SmartCollectionView *owner;
@property (nonatomic, strong, readonly) SmartCollectionViewLayoutCache *layoutCache;
@property (nonatomic, strong, readonly) SmartCollectionViewVisibilityTracker *visibilityTracker;
@property (nonatomic, strong, readonly) SmartCollectionViewMountController *mountController;
@property (nonatomic, strong, readonly) SmartCollectionViewEventBus *eventBus;

@property (nonatomic, assign) NSInteger initialNumToRender;
@property (nonatomic, assign) NSInteger maxToRenderPerBatch;
@property (nonatomic, assign) NSInteger overscanCount;
@property (nonatomic, assign) CGFloat overscanLength;
@property (nonatomic, assign) CGFloat shadowBufferMultiplier; // Multiplier for request range beyond mount range (default: 2.0)
@property (nonatomic, assign, getter=isHorizontal) BOOL horizontal;

@property (nonatomic, assign) CGPoint scrollOffset;
@property (nonatomic, assign) CGSize viewportSize;
@property (nonatomic, assign) NSInteger totalItemCount;

- (instancetype)initWithOwner:(SmartCollectionView *)owner
                  layoutCache:(SmartCollectionViewLayoutCache *)layoutCache
           visibilityTracker:(SmartCollectionViewVisibilityTracker *)visibilityTracker
             mountController:(SmartCollectionViewMountController *)mountController
                    eventBus:(SmartCollectionViewEventBus *)eventBus NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)updateCumulativeOffsets:(NSArray<NSNumber *> *)offsets;
- (void)updateRenderedIndices:(NSSet<NSNumber *> *)renderedIndices;
- (void)notifyLayoutRecomputed;

- (NSRange)visibleRange;
- (NSRange)rangeToMount;
- (NSRange)rangeToRequest; // Larger range for requesting items (shadow buffer)
- (void)requestItemsIfNeeded;
// Optional: allow owner to inform scheduler that certain indices were requested (to dedupe)
- (void)noteItemsRequested:(NSArray<NSNumber *> *)indices;

@end

NS_ASSUME_NONNULL_END
