import React from 'react';
import { View, Text, StyleSheet, Dimensions } from 'react-native';
import FastImage from 'react-native-fast-image';
import { ProductCard } from '../data/mockData';

interface ProductCardProps {
  product: ProductCard;
  index?: number;
}

const { width: screenWidth } = Dimensions.get('window');
const cardWidth = screenWidth * 0.4; // 40% of screen width

const ProductCardComponent: React.FC<ProductCardProps> = ({ product, index }) => {
  return (
    <View style={styles.container}>
      <FastImage
        source={{ uri: product.imageUrl }}
        style={styles.image}
        resizeMode={FastImage.resizeMode.cover}
      />
      
      <View style={styles.content}>
        <Text style={styles.title} numberOfLines={2}>
          {typeof index === 'number' ? `${index}. ` : ''}{product.title}
        </Text>
        
        {product.subtitle && (
          <Text style={styles.subtitle} numberOfLines={1}>
            {product.subtitle}
          </Text>
        )}
        
        <View style={styles.priceContainer}>
          <Text style={styles.sellingPrice}>
            ₹{product.sellingPrice.toLocaleString()}
          </Text>
          {product.discount && (
            <>
              <Text style={styles.mrp}>
                ₹{product.mrp.toLocaleString()}
              </Text>
              <Text style={styles.discount}>
                {product.discount}% off
              </Text>
            </>
          )}
        </View>
        
        {product.rating && (
          <View style={styles.ratingContainer}>
            <Text style={styles.rating}>
              ⭐ {product.rating}/5
            </Text>
          </View>
        )}
        
        {product.tag && (
          <View style={styles.tagContainer}>
            <Text style={styles.tag}>
              {product.tag}
            </Text>
          </View>
        )}
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    width: cardWidth,
    backgroundColor: 'white',
    borderRadius: 8,
    marginHorizontal: 8,
    marginVertical: 4,
    borderWidth: 2,
    borderColor: '#0000ff', // Debug blue border
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.1,
    shadowRadius: 3.84,
    elevation: 5,
  },
  image: {
    width: '100%',
    height: cardWidth * 0.6, // 60% of card width
    borderTopLeftRadius: 8,
    borderTopRightRadius: 8,
  },
  content: {
    padding: 12,
  },
  title: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 12,
    color: '#666',
    marginBottom: 8,
  },
  priceContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
    flexWrap: 'wrap', // Allow wrapping if content is too wide
  },
  sellingPrice: {
    fontSize: 16,
    fontWeight: '700',
    color: '#e74c3c',
    marginRight: 8,
  },
  mrp: {
    fontSize: 12,
    color: '#999',
    textDecorationLine: 'line-through',
    marginRight: 4,
  },
  discount: {
    fontSize: 10,
    color: '#27ae60',
    fontWeight: '600',
  },
  ratingContainer: {
    marginBottom: 8,
  },
  rating: {
    fontSize: 12,
    color: '#f39c12',
  },
  tagContainer: {
    backgroundColor: '#e74c3c',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    alignSelf: 'flex-start',
  },
  tag: {
    fontSize: 10,
    color: 'white',
    fontWeight: '600',
  },
});

export default ProductCardComponent;
