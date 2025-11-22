import React from 'react';
import { requireNativeComponent, ViewProps } from 'react-native';

interface NativeItemWrapperProps extends ViewProps {
  itemType?: string | null;
  itemIndex: number;
  children?: React.ReactNode;
}

const SmartCollectionViewItemNative =
  requireNativeComponent<NativeItemWrapperProps>('SmartCollectionViewItem');

export interface SmartCollectionViewItemWrapperProps
  extends Omit<NativeItemWrapperProps, 'children'> {
  children: React.ReactElement;
}

const SmartCollectionViewItemWrapper: React.FC<SmartCollectionViewItemWrapperProps> = ({
  children,
  itemType,
  itemIndex,
  ...rest
}) => {
  return (
    <SmartCollectionViewItemNative
      {...rest}
      itemType={itemType}
      itemIndex={itemIndex}
    >
      {children}
    </SmartCollectionViewItemNative>
  );
};

export default SmartCollectionViewItemWrapper;

