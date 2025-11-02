#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SmartCollectionViewLayoutProvider <NSObject>

// Pure layout calculation - no invalidation logic
- (CGSize)contentSizeForItems:(NSArray<UIView *> *)items 
                    viewport:(CGSize)viewport
              scrollDirection:(BOOL)horizontal;

- (NSArray<NSValue *> *)layoutAttributesForElementsInRect:(CGRect)rect
                                                   items:(NSArray<UIView *> *)items
                                                viewport:(CGSize)viewport;

- (CGRect)layoutAttributesForItemAtIndex:(NSInteger)index
                                    items:(NSArray<UIView *> *)items
                                 viewport:(CGSize)viewport;

// Layout type identification
- (NSString *)layoutType;

@end

NS_ASSUME_NONNULL_END
