#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface SmartCollectionViewLayoutSpec : NSObject <NSCopying>

@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) NSInteger version;
@property (nonatomic, assign, getter=isValid) BOOL valid;
@property (nonatomic, assign) NSTimeInterval timestamp;

- (instancetype)initWithIndex:(NSInteger)index frame:(CGRect)frame;

@end

NS_ASSUME_NONNULL_END

