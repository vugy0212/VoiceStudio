import 'package:flutter/material.dart';
import '../config/theme.dart';

class ConnectionBadge extends StatelessWidget {
  final bool isConnected;
  final bool isChecking;
  final VoidCallback onTap;

  const ConnectionBadge({
    super.key,
    required this.isConnected,
    required this.isChecking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isChecking
        ? AppTheme.accentAmber
        : (isConnected ? AppTheme.accentGreen : Colors.redAccent);

    final statusText = isChecking
        ? 'Connecting'
        : (isConnected ? 'Connected' : 'Offline');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF131A29),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isConnected
                ? AppTheme.accentCyan.withValues(alpha: 0.35)
                : AppTheme.border,
            width: 1,
          ),
          boxShadow: isConnected
              ? [
                  BoxShadow(
                    color: AppTheme.accentCyan.withValues(alpha: 0.15),
                    blurRadius: 8,
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_rounded, color: AppTheme.accentCloudflare, size: 15),
            const SizedBox(width: 5),
            const Text(
              'Cloudflare',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.8),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
