#import "SmartCollectionViewWrapperView.h"

@implementation SmartCollectionViewWrapperView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        // Clip to bounds to prevent content overflow when wrapper is reused
        self.clipsToBounds = YES;
    }
    return self;
}

@end

