#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * ReusePool manages a pool of React Native child views for recycling.
 * Views are keyed by item type and can be enqueued on unmount and dequeued on mount.
 */
@interface SmartCollectionViewReusePool : NSObject

/**
 * Initialize a new reuse pool.
 */
- (instancetype)init;

/**
 * Enqueue a view for reuse. The view is stored by its item type.
 * @param view The view to enqueue
 * @param itemType The type identifier for this view (used as the key)
 */
- (void)enqueueView:(UIView *)view forItemType:(NSString *)itemType;

/**
 * Dequeue a view from the pool for the given item type.
 * Returns nil if no view is available for that type.
 * @param itemType The type identifier to dequeue a view for
 * @return A view ready for reuse, or nil if none available
 */
- (UIView * _Nullable)dequeueViewForItemType:(NSString *)itemType;

/**
 * Remove all views from the pool.
 */
- (void)clear;

/**
 * Get the current pool size (total number of views in all pools).
 */
- (NSInteger)poolSize;

/**
 * Get the pool size for a specific item type.
 */
- (NSInteger)poolSizeForItemType:(NSString *)itemType;

@end

NS_ASSUME_NONNULL_END

