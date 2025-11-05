#import <React/RCTViewManager.h>

@class SmartCollectionView;
@class SmartCollectionViewLocalData;

@interface SmartCollectionViewManager : RCTViewManager

// Public method to set local data on view (called from shadow view)
- (void)setLocalData:(SmartCollectionViewLocalData *)localData forView:(SmartCollectionView *)view;

@end
