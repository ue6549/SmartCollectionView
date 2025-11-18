#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SmartCollectionViewWrapperView : UIView

@property (nonatomic, strong, nullable) NSNumber *reactTag;
@property (nonatomic, strong, nullable) NSNumber *currentIndex; // debug/assignment tracking

@end

NS_ASSUME_NONNULL_END

