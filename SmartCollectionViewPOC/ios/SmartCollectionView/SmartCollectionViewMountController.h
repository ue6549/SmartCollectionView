#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SmartCollectionViewMountController : NSObject

// Properties
@property (nonatomic, weak) UIView *containerView;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *mountedIndices;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIView *> *mountedViews;

// Initialization
- (instancetype)initWithContainerView:(UIView *)containerView;

// Mount/unmount methods
- (void)mountItem:(UIView *)item atIndex:(NSInteger)index withFrame:(CGRect)frame;
- (void)unmountItemAtIndex:(NSInteger)index;
- (void)unmountAllItems;

// Query methods
- (BOOL)isItemMountedAtIndex:(NSInteger)index;
- (UIView * _Nullable)mountedViewAtIndex:(NSInteger)index;
- (NSArray<NSNumber *> *)allMountedIndices;

// Batch operations
- (void)mountItems:(NSArray<UIView *> *)items 
           indices:(NSArray<NSNumber *> *)indices 
           frames:(NSArray<NSValue *> *)frames;
- (void)unmountItemsAtIndices:(NSArray<NSNumber *> *)indices;

@end

NS_ASSUME_NONNULL_END
