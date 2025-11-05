export interface ProductCard {
  id: string;
  title: string;
  subtitle?: string;
  imageUrl: string;
  mrp: number;
  sellingPrice: number;
  discount?: number;
  rating?: number;
  tag?: string;
}

export interface GenerateMockProductsOptions {
  longestItemPosition?: 'last' | 'secondLast' | 'thirdLast' | 'first' | number;
}

export const generateMockProducts = (
  count: number, 
  options: GenerateMockProductsOptions = {}
): ProductCard[] => {
  const products: ProductCard[] = [];
  
  const titles = [
    'Wireless Bluetooth Headphones',
    'Smart Fitness Tracker',
    'Portable Phone Charger',
    'Ergonomic Office Chair',
    'LED Desk Lamp',
    'Bluetooth Speaker',
    'Gaming Mouse',
    'Mechanical Keyboard',
    'USB-C Hub',
    'Wireless Charging Pad'
  ];
  
  const subtitles = [
    'Premium Quality',
    'Latest Technology',
    'Energy Efficient',
    'Compact Design',
    'High Performance',
    'Durable Material',
    'Easy to Use',
    'Professional Grade',
    'Multi-Purpose',
    'Innovative Features'
  ];
  
  const tags = [
    'Selling Fast',
    'Top Deal',
    'Limited Time',
    'Best Seller',
    'New Arrival',
    'Clearance',
    'Flash Sale',
    'Exclusive',
    'Trending',
    'Popular'
  ];
  
  // Determine position of longest item
  let longestItemIndex: number;
  if (typeof options.longestItemPosition === 'number') {
    longestItemIndex = options.longestItemPosition;
  } else {
    switch (options.longestItemPosition) {
      case 'last':
        longestItemIndex = count - 1;
        break;
      case 'secondLast':
        longestItemIndex = count - 2;
        break;
      case 'thirdLast':
        longestItemIndex = count - 3;
        break;
      case 'first':
        longestItemIndex = 0;
        break;
      default:
        longestItemIndex = count - 1; // Default to last
    }
  }
  
  // Ensure longestItemIndex is valid
  longestItemIndex = Math.max(0, Math.min(longestItemIndex, count - 1));
  
  for (let i = 0; i < count; i++) {
    // Determine if this is the longest item (has all features: subtitle, tag, rating, discount)
    const isLongestItem = i === longestItemIndex;
    
    // For longest item: always include all features
    // For other items: smaller height (randomly exclude features)
    const hasSubtitle = isLongestItem ? true : (i < 5 ? false : Math.random() > 0.3);
    const hasTag = isLongestItem ? true : (i < 5 ? false : Math.random() > 0.5);
    const hasRating = isLongestItem ? true : (i < 5 ? false : Math.random() > 0.2);
    const hasDiscount = isLongestItem ? true : (Math.random() > 0.4);
    
    const mrp = Math.floor(Math.random() * 5000) + 500; // 500-5500
    const discount = hasDiscount ? Math.floor(Math.random() * 50) + 10 : undefined; // 10-60%
    const sellingPrice = hasDiscount ? Math.floor(mrp * (1 - discount! / 100)) : mrp;
    
    products.push({
      id: `product_${i}`,
      title: titles[i % titles.length],
      subtitle: hasSubtitle ? subtitles[i % subtitles.length] : undefined,
      imageUrl: `https://picsum.photos/200/200?random=${i}`,
      mrp,
      sellingPrice,
      discount,
      rating: hasRating ? Math.floor(Math.random() * 2) + 4 : undefined, // 4-5 stars
      tag: hasTag ? tags[i % tags.length] : undefined
    });
  }
  
  console.log(`📦 Generated mock products: ${products.length} items, longest item at index ${longestItemIndex}`);
  
  return products;
};
