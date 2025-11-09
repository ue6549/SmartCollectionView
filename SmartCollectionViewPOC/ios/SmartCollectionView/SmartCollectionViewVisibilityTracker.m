#import "SmartCollectionViewVisibilityTracker.h"

@interface SmartCollectionViewVisibilityTracker ()

@property (nonatomic, copy) SmartCollectionViewSizeProvider sizeProvider;

@end

@implementation SmartCollectionViewVisibilityTracker

- (instancetype)initWithSizeProvider:(SmartCollectionViewSizeProvider)sizeProvider
{
    NSParameterAssert(sizeProvider != nil);
    self = [super init];
    if (self) {
        _sizeProvider = [sizeProvider copy];
        _horizontal = YES;
    }
    return self;
}

- (CGSize)sizeForIndex:(NSInteger)index
{
    if (!self.sizeProvider) {
        return CGSizeZero;
    }
    return self.sizeProvider(index);
}

@end

