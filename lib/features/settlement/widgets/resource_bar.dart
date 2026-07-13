import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/resource_model.dart';

class ResourceBar extends StatelessWidget {
  final ResourceModel resources;
  final Map<String, double> hourlyRates;

  const ResourceBar({
    super.key,
    required this.resources,
    required this.hourlyRates,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A3E))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _res('🪵', 'Wood', resources.wood, hourlyRates['wood'] ?? 0),
          _divider(),
          _res('🪨', 'Stone', resources.stone, hourlyRates['stone'] ?? 0),
        ],
      ),
    );
  }

  Widget _res(String emoji, String label, double amount, double rate) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              amount.toStringAsFixed(0),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Text(
          '+${rate.toStringAsFixed(1)}/h',
          style: GoogleFonts.outfit(
            color: const Color(0xFF7B8FA8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 32, color: const Color(0xFF2A2A3E));
}
