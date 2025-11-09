#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class SmartCollectionViewLayoutSpec;

NS_ASSUME_NONNULL_BEGIN

@interface SmartCollectionViewLayoutCache : NSObject

- (void)setSpec:(SmartCollectionViewLayoutSpec *)spec forIndex:(NSInteger)index;
- (void)setFrame:(CGRect)frame forIndex:(NSInteger)index;
- (nullable SmartCollectionViewLayoutSpec *)specForIndex:(NSInteger)index;
- (void)removeSpecForIndex:(NSInteger)index;
- (void)removeAllSpecs;
- (NSArray<SmartCollectionViewLayoutSpec *> *)allSpecs;
- (NSUInteger)count;

@end

NS_ASSUME_NONNULL_END

