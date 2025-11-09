#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef CGSize (^SmartCollectionViewSizeProvider)(NSInteger index);

@interface SmartCollectionViewVisibilityTracker : NSObject

@property (nonatomic, assign, getter=isHorizontal) BOOL horizontal;

- (instancetype)initWithSizeProvider:(SmartCollectionViewSizeProvider)sizeProvider NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (CGSize)sizeForIndex:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END

