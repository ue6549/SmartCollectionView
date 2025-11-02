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

export const generateMockProducts = (count: number): ProductCard[] => {
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
  
  for (let i = 0; i < count; i++) {
    const hasSubtitle = Math.random() > 0.3;
    const hasDiscount = Math.random() > 0.4;
    const hasRating = Math.random() > 0.2;
    const hasTag = Math.random() > 0.5;
    
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
  
  console.log('📦 Generated mock products:', products.length, 'items');
  
  return products;
};
