import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:point_of_sales_app_v3/Models/RecommendationModels.dart';
import 'package:point_of_sales_app_v3/Services/RecommendationService.dart';

class RecommendationListWidget extends StatelessWidget {
  final List<Recommendation> recommendations;
  final Function(String) onRecommendationTap;

  const RecommendationListWidget({
    Key? key,
    required this.recommendations,
    required this.onRecommendationTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (recommendations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Tidak ada rekomendasi',
            style: GoogleFonts.poppins(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Rekomendasi',
                  style: GoogleFonts.poppins(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // Recommendations List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: recommendations.length,
              itemBuilder: (context, index) {
                final rec = recommendations[index];
                return _buildRecommendationCard(rec, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(Recommendation rec, int index) {
    // Get aliases for this item
    final aliases = _getAliases(rec.itemName);
    final displayName = _capitalizeFirst(rec.itemName);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      child: InkWell(
        onTap: () => onRecommendationTap(rec.itemName),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main item name
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: GoogleFonts.poppins(
                          color: Colors.green.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayName,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  // Confidence badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getConfidenceColor(rec.confidence),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${(rec.confidence * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              // Show aliases (index 0 and 1 if they exist)
              if (aliases.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (int i = 0; i < (aliases.length > 2 ? 2 : aliases.length); i++)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _capitalizeFirst(aliases[i]),
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    if (aliases.length > 2)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '+${aliases.length - 2}',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              // Based on
              const SizedBox(height: 6),
              Text(
                'Berdasarkan: ${rec.basedOn.map((e) => _capitalizeFirst(e)).join(", ")}',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Get aliases for an item from the item merges map
  List<String> _getAliases(String canonicalName) {
    final itemMerges = RecommendationService.itemMerges;
    final aliases = itemMerges[canonicalName.toLowerCase()];
    if (aliases == null || aliases.isEmpty) return [];
    
    // Return all aliases except the canonical name itself
    return aliases.where((alias) => alias.toLowerCase() != canonicalName.toLowerCase()).toList();
  }

  // Get color based on confidence level
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green.shade600;
    if (confidence >= 0.6) return Colors.blue.shade600;
    if (confidence >= 0.5) return Colors.orange.shade600;
    return Colors.grey.shade600;
  }

  // Capitalize first letter of each word
  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}

