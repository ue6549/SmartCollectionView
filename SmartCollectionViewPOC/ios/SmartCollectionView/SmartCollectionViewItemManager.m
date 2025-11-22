#import "SmartCollectionViewItemManager.h"

#import "SmartCollectionViewItemShadowView.h"
#import "SmartCollectionViewItemView.h"

@implementation SmartCollectionViewItemManager

RCT_EXPORT_MODULE(SmartCollectionViewItem)

- (UIView *)view
{
    return [[SmartCollectionViewItemView alloc] initWithFrame:CGRectZero];
}

- (RCTShadowView *)shadowView
{
    return [[SmartCollectionViewItemShadowView alloc] init];
}

RCT_EXPORT_VIEW_PROPERTY(itemType, NSString)
RCT_EXPORT_VIEW_PROPERTY(itemIndex, NSInteger)

@end

