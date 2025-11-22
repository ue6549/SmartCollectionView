import React, { useState, useCallback, useEffect } from 'react';
import { requireNativeComponent, ViewStyle, NativeSyntheticEvent } from 'react-native';
import SmartCollectionViewItemWrapper from './SmartCollectionViewItemWrapper';

interface RequestItemsEvent {
  indices: number[];
}

interface VisibleRangeChangeEvent {
  first: number;
  last: number;
}

interface ScrollEvent {
  contentOffset: { x: number; y: number };
  contentSize: { width: number; height: number };
  layoutMeasurement: { width: number; height: number };
}

interface SmartCollectionViewNativeProps {
  children?: React.ReactNode;
  
  // Virtualization controls
  totalItemCount?: number;
  initialNumToRender?: number;
  maxToRenderPerBatch?: number;
  overscanCount?: number;
  overscanLength?: number;
  shadowBufferMultiplier?: number; // Multiplier for request range beyond mount range (default: 2.0)
  initialMaxToRenderPerBatch?: number; // Optional: override maxToRenderPerBatch during initial mount
  initialOverscanCount?: number; // Optional: override overscanCount during initial mount
  initialOverscanLength?: number; // Optional: override overscanLength during initial mount
  initialShadowBufferMultiplier?: number; // Optional: override shadowBufferMultiplier during initial mount
  
  // Layout
  horizontal?: boolean;
  estimatedItemSize?: {width: number, height: number};
  
  // Recycling
  itemTypes?: {[index: number]: string | null}; // Map of index -> itemType, updated incrementally
  
  // Events
  onRequestItems?: (event: NativeSyntheticEvent<RequestItemsEvent>) => void;
  onVisibleRangeChange?: (event: NativeSyntheticEvent<VisibleRangeChangeEvent>) => void;
  onScroll?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onScrollBeginDrag?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onScrollEndDrag?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onMomentumScrollBegin?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onMomentumScrollEnd?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onScrollEndDecelerating?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  
  style?: ViewStyle;
}

interface SmartCollectionViewProps {
  data: any[];
  renderItem: (info: {item: any, index: number}) => React.ReactElement;
  
  // Virtualization controls
  initialNumToRender?: number;        // Default: 10
  maxToRenderPerBatch?: number;       // Default: 10
  overscanCount?: number;             // Items before/after viewport, default: 5
  overscanLength?: number;            // Alternative: in screen widths/heights, default: 1.0
  shadowBufferMultiplier?: number;    // Multiplier for request range beyond mount range, default: 2.0
  initialMaxToRenderPerBatch?: number; // Optional: override maxToRenderPerBatch during initial mount
  initialOverscanCount?: number;      // Optional: override overscanCount during initial mount
  initialOverscanLength?: number;     // Optional: override overscanLength during initial mount
  initialShadowBufferMultiplier?: number; // Optional: override shadowBufferMultiplier during initial mount
  
  // Layout
  horizontal?: boolean;
  estimatedItemSize?: {width: number, height: number};
  
  // Recycling
  getItemType?: (item: any, index: number) => string | null; // Optional: returns item type for recycling
  
  // Events
  onRequestItems?: (event: NativeSyntheticEvent<RequestItemsEvent>) => void;
  onVisibleRangeChange?: (event: NativeSyntheticEvent<VisibleRangeChangeEvent>) => void;
  onScroll?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onScrollBeginDrag?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onScrollEndDrag?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onMomentumScrollBegin?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onMomentumScrollEnd?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  onScrollEndDecelerating?: (event: NativeSyntheticEvent<ScrollEvent>) => void;
  
  // Comparison mode
  useFlatList?: boolean;              // Toggle for performance comparison
  
  style?: ViewStyle;
}

const SmartCollectionViewNative = requireNativeComponent<SmartCollectionViewNativeProps>('SmartCollectionView');

const SmartCollectionView: React.FC<SmartCollectionViewProps> = ({
  data,
  renderItem,
  initialNumToRender = 2,
  maxToRenderPerBatch = 1,
  overscanCount = 1,
  overscanLength = 2,
  shadowBufferMultiplier = 2.0,
  initialMaxToRenderPerBatch,
  initialOverscanCount,
  initialOverscanLength,
  initialShadowBufferMultiplier,
  horizontal = true,
  estimatedItemSize = {width: 100, height: 80},
  getItemType,
  useFlatList = false,
  onRequestItems,
  onVisibleRangeChange,
  onScroll,
  onScrollBeginDrag,
  onScrollEndDrag,
  onMomentumScrollBegin,
  onMomentumScrollEnd,
  onScrollEndDecelerating,
  style,
  ...props
}) => {
  // Initialize rendered indices with initialNumToRender
  const [renderedIndices, setRenderedIndices] = useState<number[]>(() => {
    const count = Math.min(initialNumToRender, data.length);
    return Array.from({ length: count }, (_, i) => i);
  });
  
  // Maintain itemType map (index -> itemType)
  const [itemTypeMap, setItemTypeMap] = useState<{[index: number]: string | null}>({});
  
  // Reset when data changes
  useEffect(() => {
    const count = Math.min(initialNumToRender, data.length);
    const newIndices = Array.from({ length: count }, (_, i) => i);
    setRenderedIndices(newIndices);
    
    // Compute itemTypes for initial indices
    if (getItemType) {
      const newItemTypes: {[index: number]: string | null} = {};
      newIndices.forEach(index => {
        if (data[index] !== undefined) {
          newItemTypes[index] = getItemType(data[index], index);
        }
      });
      setItemTypeMap(newItemTypes);
    } else {
      setItemTypeMap({});
    }
  }, [data.length, initialNumToRender, getItemType]);
  
  // Handle native request for more items
  const handleRequestItems = useCallback((event: NativeSyntheticEvent<RequestItemsEvent>) => {
    const { indices } = event.nativeEvent;
    
    // Add new indices to rendered set
    setRenderedIndices(prev => {
      const newSet = new Set([...prev, ...indices]);
      return Array.from(newSet).sort((a, b) => a - b);
    });
    
    // Compute itemTypes for newly requested indices
    if (getItemType) {
      setItemTypeMap(prev => {
        const updated = {...prev};
        indices.forEach(index => {
          if (data[index] !== undefined) {
            updated[index] = getItemType(data[index], index);
          }
        });
        return updated;
      });
    }
    
    // Call user's handler if provided
    if (onRequestItems) {
      onRequestItems(event);
    }
  }, [onRequestItems, getItemType, data]);
  
  // Only render items whose indices are in renderedIndices
  // Wrap each item in an absolute-positioned View so they don't affect parent layout
  const itemsToRender = renderedIndices
    .filter(index => index >= 0 && index < data.length)
    .map(index => {
      const element = renderItem({ item: data[index], index });
      const itemType = getItemType ? getItemType(data[index], index) : 'default';

      return (
        <SmartCollectionViewItemWrapper
          key={index}
          itemIndex={index}
          itemType={itemType}
          style={{ position: 'absolute' }}
        >
          {element}
        </SmartCollectionViewItemWrapper>
      );
    });
  
  const nativeProps: SmartCollectionViewNativeProps = {
    totalItemCount: data.length,
    initialNumToRender,
    maxToRenderPerBatch,
    overscanCount,
    overscanLength,
    shadowBufferMultiplier,
    ...(initialMaxToRenderPerBatch !== undefined && { initialMaxToRenderPerBatch }),
    ...(initialOverscanCount !== undefined && { initialOverscanCount }),
    ...(initialOverscanLength !== undefined && { initialOverscanLength }),
    ...(initialShadowBufferMultiplier !== undefined && { initialShadowBufferMultiplier }),
    horizontal,
    estimatedItemSize,
    itemTypes: getItemType ? itemTypeMap : undefined, // Pass itemType map to native
    onRequestItems: handleRequestItems,
    onVisibleRangeChange,
    onScroll,
    onScrollBeginDrag,
    onScrollEndDrag,
    onMomentumScrollBegin,
    onMomentumScrollEnd,
    onScrollEndDecelerating,
    style,
    ...props,
  };
  
  return (
    <SmartCollectionViewNative {...nativeProps}>
      {itemsToRender}
    </SmartCollectionViewNative>
  );
};

export default SmartCollectionView;
