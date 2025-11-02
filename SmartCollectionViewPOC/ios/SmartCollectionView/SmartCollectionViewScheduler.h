#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SmartCollectionViewLayoutProvider.h"

NS_ASSUME_NONNULL_BEGIN

@interface SmartCollectionViewScheduler : NSObject

// Properties
@property (nonatomic, strong) id<SmartCollectionViewLayoutProvider> layoutProvider;
@property (nonatomic, strong) NSMutableArray<UIView *> *virtualItems;
@property (nonatomic, assign) CGSize viewport;
@property (nonatomic, assign) BOOL horizontal;
@property (nonatomic, assign) NSInteger initialNumToRender;
@property (nonatomic, assign) NSInteger maxToRenderPerBatch;
@property (nonatomic, assign) NSInteger overscanCount;

// State
@property (nonatomic, assign) CGFloat scrollOffset;
@property (nonatomic, assign) CGSize contentSize;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *mountedIndices;
@property (nonatomic, assign) BOOL needsLayoutRecompute;

// Initialization
- (instancetype)initWithLayoutProvider:(id<SmartCollectionViewLayoutProvider>)layoutProvider;

// Main methods
- (void)onScrollOffsetChange:(CGFloat)offset;
- (void)onDataChange:(NSArray<UIView *> *)items;
- (void)onViewportChange:(CGSize)viewport;
- (void)recomputeLayoutIfNeeded;

// Query methods
- (NSRange)visibleItemRange;
- (NSRange)rangeToMount;
- (NSArray<NSNumber *> *)indicesToMount;
- (NSArray<NSNumber *> *)indicesToUnmount;

// Layout methods
- (CGRect)frameForItemAtIndex:(NSInteger)index;
- (CGSize)getContentSize;

@end

NS_ASSUME_NONNULL_END
