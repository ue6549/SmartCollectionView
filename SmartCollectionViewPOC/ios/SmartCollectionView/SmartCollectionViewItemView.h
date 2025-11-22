#import <React/RCTView.h>

@class SmartCollectionView;

NS_ASSUME_NONNULL_BEGIN

@interface SmartCollectionViewItemView : RCTView

@property (nonatomic, copy, nullable) NSString *itemType;
@property (nonatomic, assign) NSInteger itemIndex;
@property (nonatomic, weak, nullable) SmartCollectionView *parentCollectionView;
@property (nonatomic, assign, readonly) BOOL isInPlaceholderMode;

// Placeholder state helpers
- (void)enterPlaceholderMode;
- (void)promoteContentIfAvailable;

@end

NS_ASSUME_NONNULL_END

