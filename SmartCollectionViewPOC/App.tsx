import React, { useState } from 'react';
import {
  SafeAreaView,
  StatusBar,
  StyleSheet,
  Text,
  useColorScheme,
  View,
  TouchableOpacity,
  Dimensions,
  FlatList,
} from 'react-native';
import HorizontalListWidget from './src/components/HorizontalListWidget';

const { width: screenWidth, height: screenHeight } = Dimensions.get('window');

function App(): JSX.Element {
  const isDarkMode = useColorScheme() === 'dark';
  const [useSmartCollection, setUseSmartCollection] = useState(true);

  const backgroundStyle = {
    backgroundColor: isDarkMode ? '#000' : '#fff',
  };

  // Create data for FlatList including header
  const widgetData = [
    { id: 'header', type: 'header' },
    { id: 'widget1', type: 'widget' },
    { id: 'widget2', type: 'widget' },
    { id: 'widget3', type: 'widget' },
  ];

  const renderItem = ({ item, index }: { item: any; index: number }) => {
    if (item.type === 'header') {
      return (
        <View style={styles.header}>
          <Text style={styles.title}>SmartCollectionView POC</Text>
          <Text style={styles.subtitle}>Testing native virtualization</Text>
          
          <TouchableOpacity
            style={styles.toggleButton}
            onPress={() => setUseSmartCollection(!useSmartCollection)}
          >
            <Text style={styles.toggleText}>
              Switch to {useSmartCollection ? 'FlatList' : 'SmartCollectionView'}
            </Text>
          </TouchableOpacity>
        </View>
      );
    }
    return <HorizontalListWidget useSmartCollection={useSmartCollection} />;
  };

  return (
    <View style={backgroundStyle}>
      <StatusBar
        barStyle={isDarkMode ? 'light-content' : 'dark-content'}
        backgroundColor={backgroundStyle.backgroundColor}
      />
      
      {/* Fixed height top area for status bar */}
      <View style={styles.statusBarArea} />
      
      <View style={styles.container}>
        <FlatList
          data={widgetData}
          renderItem={renderItem}
          keyExtractor={(item) => item.id}
          style={styles.rlv}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  statusBarArea: {
    height: 44, // Fixed height for status bar area
    backgroundColor: '#f8f9fa',
  },
  header: {
    padding: 20,
    backgroundColor: '#f8f9fa',
    borderBottomWidth: 1,
    borderBottomColor: '#e9ecef',
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    color: '#333',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    marginBottom: 16,
  },
  toggleButton: {
    backgroundColor: '#007bff',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 6,
    alignSelf: 'flex-start',
  },
  toggleText: {
    color: 'white',
    fontWeight: '600',
  },
  container: {
    height: screenHeight - 44, // Fixed height for container
    backgroundColor: '#ffff00', // Debug yellow background
  },
  rlv: {
    flex: 1, // Back to flex: 1
    backgroundColor: '#ff00ff', // Debug magenta background
  },
});

export default App;
