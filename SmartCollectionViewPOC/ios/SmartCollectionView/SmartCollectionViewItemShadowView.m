#import "SmartCollectionViewItemShadowView.h"

@implementation SmartCollectionViewItemShadowView

- (instancetype)init
{
    self = [super init];
    if (self) {
        // Default flex behavior so the wrapper does not affect Yoga layout.
        self.flexGrow = 0;
        self.flexShrink = 0;
    }
    return self;
}

@end

