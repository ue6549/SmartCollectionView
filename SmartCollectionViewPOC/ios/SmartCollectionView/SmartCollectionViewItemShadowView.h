#import <React/RCTShadowView.h>

NS_ASSUME_NONNULL_BEGIN

@interface SmartCollectionViewItemShadowView : RCTShadowView

@property (nonatomic, copy, nullable) NSString *itemType;
@property (nonatomic, assign) NSInteger itemIndex;

@end

NS_ASSUME_NONNULL_END

