#import "SmartCollectionViewLocalData.h"

@implementation SmartCollectionViewItemMetadata

- (instancetype)initWithReactTag:(NSNumber *)reactTag
                              size:(CGSize)size
                             index:(NSInteger)index
                            version:(NSInteger)version
{
    self = [super init];
    if (self) {
        _reactTag = reactTag;
        _size = size;
        _index = index;
        _version = version;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    SmartCollectionViewItemMetadata *copy = [[SmartCollectionViewItemMetadata allocWithZone:zone] init];
    copy.reactTag = self.reactTag;
    copy.size = self.size;
    copy.index = self.index;
    copy.version = self.version;
    return copy;
}

@end

@implementation SmartCollectionViewLocalData

- (instancetype)initWithItems:(NSArray<SmartCollectionViewItemMetadata *> *)items
                       version:(NSInteger)version
{
    self = [super init];
    if (self) {
        _items = items;
        _version = version;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    NSMutableArray *copiedItems = [NSMutableArray arrayWithCapacity:self.items.count];
    for (SmartCollectionViewItemMetadata *item in self.items) {
        [copiedItems addObject:[item copyWithZone:zone]];
    }
    SmartCollectionViewLocalData *copy = [[SmartCollectionViewLocalData allocWithZone:zone] initWithItems:[copiedItems copy] version:self.version];
    return copy;
}

@end

