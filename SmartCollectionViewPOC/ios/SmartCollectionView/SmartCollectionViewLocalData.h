#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface SmartCollectionViewItemMetadata : NSObject <NSCopying>

@property (nonatomic, strong) NSNumber *reactTag;
@property (nonatomic, assign) CGSize size;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) NSInteger version;

- (instancetype)initWithReactTag:(NSNumber *)reactTag
                              size:(CGSize)size
                             index:(NSInteger)index
                            version:(NSInteger)version;

@end

@interface SmartCollectionViewLocalData : NSObject <NSCopying>

@property (nonatomic, strong) NSArray<SmartCollectionViewItemMetadata *> *items;
@property (nonatomic, assign) NSInteger version;

- (instancetype)initWithItems:(NSArray<SmartCollectionViewItemMetadata *> *)items
                       version:(NSInteger)version;

@end

NS_ASSUME_NONNULL_END

