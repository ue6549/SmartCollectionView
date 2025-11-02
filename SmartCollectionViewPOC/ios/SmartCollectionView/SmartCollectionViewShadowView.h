#import <React/RCTShadowView.h>

NS_ASSUME_NONNULL_BEGIN

@class SmartCollectionViewLocalData; // Forward declaration

@interface SmartCollectionViewShadowView : RCTShadowView

// Shadow view management
@property (nonatomic, strong, readonly) NSArray<RCTShadowView *> *childShadowViews;

// Layout configuration (set from native view props)
@property (nonatomic, assign) BOOL horizontal;
@property (nonatomic, assign) CGSize estimatedItemSize;

// Public method to get local data snapshot
- (SmartCollectionViewLocalData *)localDataSnapshot;

// Force update of local data (can be called from native view)
- (void)updateLocalDataIfNeeded;

// Calculate max height from children (for measureFunc)
- (CGFloat)calculateMaxItemHeight;

@end

NS_ASSUME_NONNULL_END
