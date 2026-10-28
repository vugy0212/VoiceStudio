import 'package:flutter/material.dart';
import '../config/theme.dart';

class ConnectionBadge extends StatelessWidget {
  final bool isConnected;
  final bool isChecking;
  final bool isUsingLocal;
  final String backendStatus; // 'RUNNING', 'SLEEPING', 'STARTING', 'DIRECT', 'OFFLINE'
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ConnectionBadge({
    super.key,
    required this.isConnected,
    required this.isChecking,
    this.isUsingLocal = false,
    this.backendStatus = 'OFFLINE',
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSleeping = isConnected && backendStatus == 'SLEEPING';
    final bool isStarting = isChecking || backendStatus == 'STARTING';

    final Color statusColor = isStarting
        ? AppTheme.accentAmber
        : (!isConnected
            ? Colors.redAccent
            : (isSleeping ? AppTheme.accentCyan : AppTheme.accentGreen));

    final String statusText = isStarting
        ? (backendStatus == 'STARTING' ? 'Buđenje GPU-a...' : 'Provjera...')
        : (!isConnected
            ? 'Izvan mreže'
            : (isSleeping ? 'Standby (0% GPU)' : 'Spreman'));

    final String networkLabel = isUsingLocal ? 'Lokalno' : 'Cloudflare';
    final IconData networkIcon = isUsingLocal ? Icons.wifi_rounded : Icons.cloud_rounded;
    final Color networkIconColor = isUsingLocal ? AppTheme.accentCyan : AppTheme.accentCloudflare;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF131A29),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isConnected
                ? statusColor.withValues(alpha: 0.35)
                : AppTheme.border,
            width: 1,
          ),
          boxShadow: isConnected
              ? [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.15),
                    blurRadius: 8,
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(networkIcon, color: networkIconColor, size: 15),
            const SizedBox(width: 5),
            Text(
              networkLabel,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 7),
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
            const SizedBox(width: 5),
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isSleeping) ...[
              const SizedBox(width: 4),
              const Icon(Icons.bedtime_rounded, size: 12, color: AppTheme.accentCyan),
            ],
          ],
        ),
      ),
    );
  }
}
