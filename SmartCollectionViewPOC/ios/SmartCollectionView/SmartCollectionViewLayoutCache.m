#import "SmartCollectionViewLayoutCache.h"
#import "SmartCollectionViewLayoutSpec.h"
#import <QuartzCore/QuartzCore.h>

@interface SmartCollectionViewLayoutCache ()

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, SmartCollectionViewLayoutSpec *> *specs;

@end

@implementation SmartCollectionViewLayoutCache

- (instancetype)init
{
    self = [super init];
    if (self) {
        _specs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setSpec:(SmartCollectionViewLayoutSpec *)spec forIndex:(NSInteger)index
{
    if (!spec) {
        return;
    }
    spec.index = index;
    spec.timestamp = CACurrentMediaTime();
    self.specs[@(index)] = spec;
}

- (void)setFrame:(CGRect)frame forIndex:(NSInteger)index
{
    SmartCollectionViewLayoutSpec *spec = [self specForIndex:index];
    if (spec) {
        spec.frame = frame;
        spec.timestamp = CACurrentMediaTime();
        spec.valid = YES;
        self.specs[@(index)] = spec;
    } else {
        SmartCollectionViewLayoutSpec *newSpec = [[SmartCollectionViewLayoutSpec alloc] initWithIndex:index frame:frame];
        [self setSpec:newSpec forIndex:index];
    }
}

- (SmartCollectionViewLayoutSpec *)specForIndex:(NSInteger)index
{
    return self.specs[@(index)];
}

- (void)removeSpecForIndex:(NSInteger)index
{
    [self.specs removeObjectForKey:@(index)];
}

- (void)removeAllSpecs
{
    [self.specs removeAllObjects];
}

- (NSArray<SmartCollectionViewLayoutSpec *> *)allSpecs
{
    return self.specs.allValues;
}

- (NSUInteger)count
{
    return self.specs.count;
}

@end

