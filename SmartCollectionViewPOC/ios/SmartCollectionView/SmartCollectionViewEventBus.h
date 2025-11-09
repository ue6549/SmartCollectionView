#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class SmartCollectionView;

@interface SmartCollectionViewEventBus : NSObject

@property (nonatomic, weak, readonly) SmartCollectionView *owner;
@property (nonatomic, assign) NSTimeInterval scrollEventThrottle;     // milliseconds
@property (nonatomic, assign) NSTimeInterval rangeEventThrottle;      // milliseconds

- (instancetype)initWithOwner:(SmartCollectionView *)owner NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)emitScrollWithOffset:(CGPoint)offset
                    velocity:(CGPoint)velocity
                     content:(CGSize)contentSize
                     visible:(CGSize)visibleSize;
- (void)emitVisibleRange:(NSRange)range;
- (void)emitRequestItems:(NSArray<NSNumber *> *)indices;
- (void)emitScrollBeginDrag;
- (void)emitScrollEndDrag;
- (void)emitMomentumScrollBegin;
- (void)emitMomentumScrollEnd;
- (void)emitScrollEndDecelerating;

@end

NS_ASSUME_NONNULL_END
