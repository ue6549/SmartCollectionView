#import "SmartCollectionViewLayoutSpec.h"
#import <QuartzCore/QuartzCore.h>

@implementation SmartCollectionViewLayoutSpec

- (instancetype)initWithIndex:(NSInteger)index frame:(CGRect)frame
{
    self = [super init];
    if (self) {
        _index = index;
        _frame = frame;
        _version = 0;
        _valid = YES;
        _timestamp = CACurrentMediaTime();
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    SmartCollectionViewLayoutSpec *copy = [[[self class] allocWithZone:zone] initWithIndex:self.index frame:self.frame];
    copy.version = self.version;
    copy.valid = self.isValid;
    copy.timestamp = self.timestamp;
    return copy;
}

@end

