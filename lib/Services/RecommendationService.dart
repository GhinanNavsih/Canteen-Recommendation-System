import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:point_of_sales_app_v3/Models/RecommendationModels.dart';
import 'package:point_of_sales_app_v3/Services/DatabaseHelper.dart';

class RecommendationService {
  static final RecommendationService instance = RecommendationService._init();
  final DatabaseHelper _db = DatabaseHelper.instance;

  RecommendationConfig? _config;
  bool _isInitialized = false;

  RecommendationService._init();

  /// Initialize the recommendation system
  /// Call this on app startup
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🔄 Initializing recommendation system...');

      // 1. Load configuration from Firestore
      _config = await _loadConfig();

      if (!_config!.enabled) {
        print('⚠️ Recommendation system is disabled');
        _isInitialized = true;
        return;
      }

      // 2. Check if we need to update rules
      final storedVersion = await _db.getMetadata('version');
      final needsUpdate = storedVersion != _config!.version;

      if (needsUpdate) {
        print('📥 Downloading new rules (version: ${_config!.version})...');
        await _downloadAndUpdateRules();
      } else {
        print('✅ Rules are up to date (version: $storedVersion)');
      }

      final ruleCount = await _db.getRuleCount();
      print('✅ Recommendation system initialized with $ruleCount rules');

      _isInitialized = true;
    } catch (e) {
      print('❌ Error initializing recommendation system: $e');
      // Don't throw - allow app to continue without recommendations
      _isInitialized = false;
    }
  }

  /// Load configuration from Firestore
  Future<RecommendationConfig> _loadConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('recommendations')
          .get();

      if (doc.exists && doc.data() != null) {
        return RecommendationConfig.fromFirestore(doc.data()!);
      }
    } catch (e) {
      print('⚠️ Error loading config, using defaults: $e');
    }

    return RecommendationConfig.defaultConfig();
  }

  /// Download CSV from Firebase Storage and update local database
  Future<void> _downloadAndUpdateRules() async {
    try {
      // 1. Download CSV file
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('recommendation_rules/${_config!.csvFileName}');

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/rules_temp.csv');

      await storageRef.writeToFile(tempFile);
      print('✅ CSV downloaded successfully');

      // 2. Parse CSV
      final csvString = await tempFile.readAsString();
      final rules = await _parseCSV(csvString);
      print('✅ Parsed ${rules.length} rules from CSV');

      // 3. Clear old rules and insert new ones
      await _db.clearRules();
      await _db.insertRules(rules);

      // 4. Update metadata
      await _db.setMetadata('version', _config!.version);
      await _db.setMetadata('lastUpdated', DateTime.now().toIso8601String());

      // 5. Clean up temp file
      await tempFile.delete();

      print('✅ Rules database updated successfully');
    } catch (e) {
      print('❌ Error downloading/updating rules: $e');
      rethrow;
    }
  }

  /// Parse CSV string into list of AssociationRule objects
  Future<List<AssociationRule>> _parseCSV(String csvString) async {
    final List<AssociationRule> rules = [];

    final rowsAsListOfValues = const CsvToListConverter().convert(csvString);

    // Skip header row
    for (int i = 1; i < rowsAsListOfValues.length; i++) {
      try {
        final row = rowsAsListOfValues[i];

        // Parse antecedents and consequents from frozenset format
        // Example: "frozenset({'ayam goreng'})" -> ['ayam goreng']
        final antecedentsRaw = row[1].toString();
        final consequentsRaw = row[2].toString();

        final antecedents = _parseFrozenset(antecedentsRaw);
        final consequents = _parseFrozenset(consequentsRaw);

        // Parse numeric values
        final support = _parseDouble(row[3]);
        final confidence = _parseDouble(row[6]);
        final lift = _parseDouble(row[7]);

        // Create rule
        if (antecedents.isNotEmpty && consequents.isNotEmpty) {
          rules.add(AssociationRule(
            id: i,
            antecedents: antecedents,
            consequents: consequents,
            confidence: confidence,
            support: support,
            lift: lift,
          ));
        }
      } catch (e) {
        print('⚠️ Error parsing row $i: $e');
        // Continue with other rows
      }
    }

    return rules;
  }

  /// Parse frozenset string to list of items
  /// Example: "frozenset({'ayam goreng', 'nasi putih'})" -> ['ayam goreng', 'nasi putih']
  List<String> _parseFrozenset(String frozensetStr) {
    try {
      // Remove "frozenset({" and "})"
      final content = frozensetStr
          .replaceAll('frozenset({', '')
          .replaceAll('})', '')
          .trim();

      if (content.isEmpty) return [];

      // Split by comma and clean up
      return content
          .split(',')
          .map((item) => item
              .trim()
              .replaceAll("'", '')
              .replaceAll('"', '')
              .toLowerCase()
              .trim())
          .where((item) => item.isNotEmpty)
          .toList();
    } catch (e) {
      print('⚠️ Error parsing frozenset: $frozensetStr - $e');
      return [];
    }
  }

  /// Safely parse double from dynamic value
  double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Get recommendations based on current order items
  Future<List<Recommendation>> getRecommendations(
      List<String> orderItems) async {
    if (!_isInitialized || _config == null || !_config!.enabled) {
      print('⚠️ Recommendation system not initialized or disabled');
      return [];
    }

    if (orderItems.isEmpty) {
      return [];
    }

    try {
      // Normalize order items (lowercase, trim)
      final normalizedOrder =
          orderItems.map((item) => item.toLowerCase().trim()).toSet();

      // Get all rules from database
      final allRules = await _db.getAllRules();

      // Find matching rules and generate recommendations
      final Map<String, Recommendation> recommendationMap = {};

      for (final rule in allRules) {
        // Normalize antecedents
        final normalizedAntecedents =
            rule.antecedents.map((item) => item.toLowerCase().trim()).toSet();

        // Calculate match percentage
        final matchCount = normalizedAntecedents
            .where((antecedent) => normalizedOrder.contains(antecedent))
            .length;

        final matchPercentage = matchCount / normalizedAntecedents.length;

        // Check if rule meets threshold
        if (matchPercentage >= _config!.matchThreshold &&
            rule.confidence >= _config!.minConfidence) {
          // Add consequents that aren't already in the order
          for (final consequent in rule.consequents) {
            final normalizedConsequent = consequent.toLowerCase().trim();

            if (!normalizedOrder.contains(normalizedConsequent)) {
              // If item already recommended, keep the one with higher confidence
              if (!recommendationMap.containsKey(normalizedConsequent) ||
                  recommendationMap[normalizedConsequent]!.confidence <
                      rule.confidence) {
                recommendationMap[normalizedConsequent] = Recommendation(
                  itemName: consequent,
                  confidence: rule.confidence,
                  basedOn: rule.antecedents,
                  ruleDescription:
                      '${rule.antecedents.join(", ")} → $consequent',
                );
              }
            }
          }
        }
      }

      // Sort by confidence (descending) and return top N
      final recommendations = recommendationMap.values.toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));

      return recommendations.take(_config!.maxRecommendations).toList();
    } catch (e) {
      print('❌ Error generating recommendations: $e');
      return [];
    }
  }

  /// Force refresh rules from Firebase
  Future<void> forceRefresh() async {
    try {
      print('🔄 Forcing rules refresh...');
      _config = await _loadConfig();
      await _downloadAndUpdateRules();
      print('✅ Rules refreshed successfully');
    } catch (e) {
      print('❌ Error refreshing rules: $e');
      rethrow;
    }
  }

  /// Get current configuration
  RecommendationConfig? get config => _config;

  /// Check if system is initialized
  bool get isInitialized => _isInitialized;

  /// Get statistics
  Future<Map<String, dynamic>> getStatistics() async {
    final ruleCount = await _db.getRuleCount();
    final version = await _db.getMetadata('version');
    final lastUpdated = await _db.getMetadata('lastUpdated');

    return {
      'ruleCount': ruleCount,
      'version': version ?? 'unknown',
      'lastUpdated': lastUpdated ?? 'never',
      'enabled': _config?.enabled ?? false,
      'initialized': _isInitialized,
    };
  }
}
