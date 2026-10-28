import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/constants.dart';

class VoiceStylingCard extends StatefulWidget {
  final String currentInstruct;
  final ValueChanged<String> onInstructChanged;
  final int currentSteps;
  final ValueChanged<int> onStepsChanged;
  final double currentGuidanceScale;
  final ValueChanged<double> onGuidanceScaleChanged;

  const VoiceStylingCard({
    super.key,
    required this.currentInstruct,
    required this.onInstructChanged,
    required this.currentSteps,
    required this.onStepsChanged,
    required this.currentGuidanceScale,
    required this.onGuidanceScaleChanged,
  });

  @override
  State<VoiceStylingCard> createState() => _VoiceStylingCardState();
}

class _VoiceStylingCardState extends State<VoiceStylingCard> {
  bool _isExpanded = false;
  late TextEditingController _instructController;

  @override
  void initState() {
    super.initState();
    _instructController = TextEditingController(text: widget.currentInstruct);
  }

  @override
  void didUpdateWidget(covariant VoiceStylingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentInstruct != widget.currentInstruct &&
        _instructController.text != widget.currentInstruct) {
      _instructController.text = widget.currentInstruct;
    }
  }

  @override
  void dispose() {
    _instructController.dispose();
    super.dispose();
  }

  String _getStepsLabel(int steps) {
    if (steps <= 8) return '$steps koraka (⚡ Brzi nacrt)';
    if (steps <= 16) return '$steps koraka (Uravnoteženo)';
    if (steps <= 24) return '$steps koraka (Visoka kvaliteta)';
    return '$steps koraka (💎 Studijski master)';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isExpanded ? AppTheme.primary.withValues(alpha: 0.5) : AppTheme.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.tune_rounded, size: 16, color: AppTheme.accentCyan),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'STIL GLASA I NAPREDNE POSTAVKE',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          widget.currentInstruct.isNotEmpty
                              ? 'Stil: "${widget.currentInstruct}"'
                              : '${widget.currentSteps} koraka • CFG ${widget.currentGuidanceScale.toStringAsFixed(1)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),

          if (_isExpanded) ...[
            const Divider(height: 1, color: AppTheme.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'PREDLOŠCI EMOCIJA I STILA',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: AppConstants.emotionPresets.map((preset) {
                        final label = preset['label']!;
                        final prompt = preset['prompt']!;
                        final isSelected = widget.currentInstruct == prompt;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: isSelected,
                            selectedColor: AppTheme.primary,
                            backgroundColor: AppTheme.surfaceElevated,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isSelected ? AppTheme.primary : AppTheme.border,
                              ),
                            ),
                            onSelected: (_) {
                              widget.onInstructChanged(prompt);
                              _instructController.text = prompt;
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _instructController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    onChanged: (val) => widget.onInstructChanged(val),
                    decoration: InputDecoration(
                      labelText: 'Uputa za stil (Instruct prompt)',
                      hintText: 'npr. whisper, low pitch, excited...',
                      labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.auto_fix_high_rounded, size: 18, color: AppTheme.primary),
                      suffixIcon: _instructController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16, color: AppTheme.textMuted),
                              onPressed: () {
                                _instructController.clear();
                                widget.onInstructChanged('');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 18),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Kvaliteta sinteze (Koraci)',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _getStepsLabel(widget.currentSteps),
                        style: const TextStyle(color: AppTheme.accentCyan, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: AppTheme.accentCyan,
                      inactiveTrackColor: AppTheme.surfaceHighlight,
                      thumbColor: AppTheme.accentCyan,
                    ),
                    child: Slider(
                      value: widget.currentSteps.toDouble(),
                      min: 8,
                      max: 32,
                      divisions: 6,
                      onChanged: (val) => widget.onStepsChanged(val.toInt()),
                    ),
                  ),
                  const SizedBox(height: 6),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Vjernost glasu (CFG skala)',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${widget.currentGuidanceScale.toStringAsFixed(1)}x',
                        style: const TextStyle(color: AppTheme.accentGreen, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: AppTheme.accentGreen,
                      inactiveTrackColor: AppTheme.surfaceHighlight,
                      thumbColor: AppTheme.accentGreen,
                    ),
                    child: Slider(
                      value: widget.currentGuidanceScale,
                      min: 1.0,
                      max: 4.0,
                      divisions: 30,
                      onChanged: (val) => widget.onGuidanceScaleChanged(double.parse(val.toStringAsFixed(1))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
