import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../config/constants.dart';

class TextInputCard extends StatelessWidget {
  final TextEditingController controller;
  final String selectedLanguage;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onClear;

  const TextInputCard({
    super.key,
    required this.controller,
    required this.selectedLanguage,
    required this.onLanguageChanged,
    required this.onClear,
  });

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      controller.text = data.text!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = controller.text;
    final wordCount = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final charCount = text.length;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF2E3A52),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header inside card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tekst',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Paste Button
                    GestureDetector(
                      onTap: _pasteClipboard,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E283C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF33415C), width: 1),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.content_paste_rounded, size: 13, color: AppTheme.textSecondary),
                            SizedBox(width: 4),
                            Text(
                              'Paste',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Language dropdown selector
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedLanguage,
                          dropdownColor: AppTheme.surfaceElevated,
                          icon: const Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.textSecondary),
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          items: AppConstants.availableLanguages.map((lang) {
                            return DropdownMenuItem(
                              value: lang,
                              child: Text(lang),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) onLanguageChanged(val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Paste Button
                    IconButton(
                      icon: const Icon(Icons.content_paste_rounded, size: 17, color: AppTheme.accentCyan),
                      tooltip: 'Paste from clipboard',
                      visualDensity: VisualDensity.compact,
                      onPressed: _pasteClipboard,
                    ),
                    // Clear Button
                    if (text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17, color: AppTheme.textMuted),
                        tooltip: 'Clear text',
                        visualDensity: VisualDensity.compact,
                        onPressed: onClear,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          // Text Input Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: TextField(
              controller: controller,
              maxLines: 7,
              minLines: 4,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                height: 1.45,
              ),
              decoration: const InputDecoration(
                hintText: 'Enter text here to generate natural speech in selected voice...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // Footer with character & word counts
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$wordCount words • $charCount chars',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11.5,
                  ),
                ),
                if (charCount > 0)
                  Text(
                    '~${(wordCount / 2.5).ceil()}s estimated',
                    style: const TextStyle(
                      color: AppTheme.accentCyan,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
