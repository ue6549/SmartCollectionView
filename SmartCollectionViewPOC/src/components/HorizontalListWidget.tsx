import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Dimensions } from 'react-native';
import { FlatList } from 'react-native';
import SmartCollectionView from './SmartCollectionView';
import ProductCard from './ProductCard';
import { generateMockProducts, ProductCard as ProductCardType } from '../data/mockData';

const { width: screenWidth } = Dimensions.get('window');

interface HorizontalListWidgetProps {
  useSmartCollection?: boolean;
}

const HorizontalListWidget: React.FC<HorizontalListWidgetProps> = ({ 
  useSmartCollection = false 
}) => {
  const [products] = useState(() => generateMockProducts(10));
  
  const renderProductCard = ({ item, index }: { item: ProductCardType; index: number }) => {
    return <ProductCard key={item.id} product={item} />;
  };
  
  if (useSmartCollection) {
    return (
      <View style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>SmartCollectionView</Text>
          <Text style={styles.subtitle}>
            Horizontal Product List ({products.length} items)
          </Text>
        </View>
        
        <View style={styles.listContainer}>
          <SmartCollectionView
            data={products}
            renderItem={renderProductCard}
            horizontal
            initialNumToRender={10}
            maxToRenderPerBatch={5}
            overscanCount={3}
            estimatedItemSize={{width: screenWidth * 0.4 + 16, height: 200}}
          />
        </View>
      </View>
    );
  }
  
  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>FlatList</Text>
        <Text style={styles.subtitle}>
          Horizontal Product List ({products.length} items)
        </Text>
      </View>
      
      <View style={styles.listContainer}>
        <FlatList
          data={products}
          renderItem={renderProductCard}
          horizontal
          showsHorizontalScrollIndicator={false}
          keyExtractor={(item) => item.id}
          style={{ backgroundColor: '#00ff00' }} // Debug green background
          contentContainerStyle={{ paddingHorizontal: 8 }}
        />
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    marginVertical: 16,
    backgroundColor: '#f0f0f0', // Debug background
    minHeight: 250, // Ensure minimum height
  },
  header: {
    paddingHorizontal: 16,
    marginBottom: 12,
  },
  title: {
    fontSize: 18,
    fontWeight: '700',
    color: '#333',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 14,
    color: '#666',
  },
  listContainer: {
    width: '100%', // Ensure full width
    backgroundColor: '#e0e0e0', // Debug background
    borderWidth: 2,
    borderColor: '#ff0000', // Debug red border
    // Dynamic height based on max item height
  },
});

export default HorizontalListWidget;
