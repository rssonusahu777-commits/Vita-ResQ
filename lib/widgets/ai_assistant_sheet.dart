import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_shapes.dart';
import '../models/emergency_model.dart';
import '../models/hospital_model.dart';
import '../services/ai_assistant_service.dart';
import '../services/voice_assistant_service.dart';

/// Modal bottom sheet providing an optional, read-only AI situational assistant
/// and Push-to-Talk ElevenLabs Voice Assistant for responders and victims.
///
/// Strict rules enforced:
/// 1. The assistant is strictly optional and read-only.
/// 2. It explains verified application data without inventing facts or overriding assignments.
/// 3. Model output is displayed in a separate, non-authoritative container.
/// 4. Core emergency operations remain fully functional regardless of assistant availability.
/// 5. Never automatically mutates emergency status or initiates hospital transfer from voice commands.
class AIAssistantSheet extends StatefulWidget {
  final EmergencyModel emergency;
  final String currentUserId;
  final bool isRoadRoute;
  final double? roadDistanceMeters;
  final double? directDistanceMeters;
  final String roadEtaText;
  final LatLng? responderLocation;
  final AIAssistantService? aiService;
  final VoiceAssistantService? voiceService;
  final void Function(HospitalModel)? onSelectHospitalRoute;

  const AIAssistantSheet({
    super.key,
    required this.emergency,
    required this.currentUserId,
    this.isRoadRoute = false,
    this.roadDistanceMeters,
    this.directDistanceMeters,
    this.roadEtaText = '-- min',
    this.responderLocation,
    this.aiService,
    this.voiceService,
    this.onSelectHospitalRoute,
  });

  static Future<void> show(
    BuildContext context, {
    required EmergencyModel emergency,
    required String currentUserId,
    bool isRoadRoute = false,
    double? roadDistanceMeters,
    double? directDistanceMeters,
    String roadEtaText = '-- min',
    LatLng? responderLocation,
    AIAssistantService? aiService,
    VoiceAssistantService? voiceService,
    void Function(HospitalModel)? onSelectHospitalRoute,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AIAssistantSheet(
        emergency: emergency,
        currentUserId: currentUserId,
        isRoadRoute: isRoadRoute,
        roadDistanceMeters: roadDistanceMeters,
        directDistanceMeters: directDistanceMeters,
        roadEtaText: roadEtaText,
        responderLocation: responderLocation,
        aiService: aiService,
        voiceService: voiceService,
        onSelectHospitalRoute: onSelectHospitalRoute,
      ),
    );
  }

  @override
  State<AIAssistantSheet> createState() => _AIAssistantSheetState();
}

class _AIAssistantSheetState extends State<AIAssistantSheet> {
  late final AIAssistantService _aiService;
  late final VoiceAssistantService _voiceService;
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;
  AIAssistantResponse? _textResponse;
  VoiceQueryResult? _voiceResult;
  String _selectedLanguage = 'en'; // 'en' or 'hi'
  String? _lastQueryType; // for retry action

  StreamSubscription<VoiceAssistantState>? _voiceStateSub;
  VoiceAssistantState _voiceState = VoiceAssistantState.idle;
  int _recordingSecondsElapsed = 0;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _aiService = widget.aiService ?? AIAssistantService();
    _voiceService = widget.voiceService ?? VoiceAssistantService();
    _voiceState = _voiceService.currentState;
    _voiceResult = _voiceService.lastResult;

    _voiceStateSub = _voiceService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _voiceState = state;
          if (state == VoiceAssistantState.recording) {
            _startRecordingCountdown();
          } else {
            _recordingTimer?.cancel();
            _recordingTimer = null;
          }
        });
      }
    });
  }

  void _startRecordingCountdown() {
    _recordingSecondsElapsed = 0;
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _recordingSecondsElapsed++;
        if (_recordingSecondsElapsed >= 10) {
          timer.cancel();
          _stopVoiceRecording();
        }
      });
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _voiceStateSub?.cancel();
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double? get _effectiveDistance => widget.isRoadRoute
      ? widget.roadDistanceMeters
      : widget.directDistanceMeters;

  Future<void> _startVoiceRecording() async {
    _focusNode.unfocus();
    setState(() {
      _textResponse = null;
    });

    await _voiceService.startRecording(
      emergencyId: widget.emergency.id,
      onAutoStop: _stopVoiceRecording,
    );
  }

  Future<void> _stopVoiceRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final result = await _voiceService.stopRecordingAndProcess(
      emergency: widget.emergency,
      responderLocation: widget.responderLocation,
      isRoadRoute: widget.isRoadRoute,
      roadDistanceMeters: widget.roadDistanceMeters,
      directDistanceMeters: widget.directDistanceMeters,
      roadEtaText: widget.roadEtaText,
      preferredLanguage: _selectedLanguage,
    );

    if (mounted) {
      setState(() {
        _voiceResult = result;
        _lastQueryType = 'VOICE';
      });
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _voiceService.cancelRecording();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _fetchBrief() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _voiceResult = null;
      _lastQueryType = 'BRIEF';
    });
    _focusNode.unfocus();

    try {
      final res = await _aiService.getEmergencyBrief(
        emergency: widget.emergency,
        language: _selectedLanguage,
        isRoadRoute: widget.isRoadRoute,
        distanceMeters: _effectiveDistance,
        etaText: widget.roadEtaText,
      );
      if (mounted) {
        setState(() {
          _textResponse = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _textResponse = AIAssistantResponse(
            success: false,
            answer: '',
            error: 'CLIENT_ERROR',
            message: e.toString(),
            isOfflineOrUnavailable: true,
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _askQuestion(String query) async {
    final clean = query.trim();
    if (clean.isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
      _voiceResult = null;
      _lastQueryType = 'QUERY:$clean';
    });
    _focusNode.unfocus();

    try {
      final res = await _aiService.askAssistant(
        emergency: widget.emergency,
        query: clean,
        language: _selectedLanguage,
        isRoadRoute: widget.isRoadRoute,
        distanceMeters: _effectiveDistance,
        etaText: widget.roadEtaText,
      );
      if (mounted) {
        setState(() {
          _textResponse = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _textResponse = AIAssistantResponse(
            success: false,
            answer: '',
            error: 'CLIENT_ERROR',
            message: e.toString(),
            isOfflineOrUnavailable: true,
          );
          _isLoading = false;
        });
      }
    }
  }

  void _retryLastAction() {
    if (_lastQueryType == 'BRIEF') {
      _fetchBrief();
    } else if (_lastQueryType != null && _lastQueryType!.startsWith('QUERY:')) {
      final q = _lastQueryType!.substring('QUERY:'.length);
      _askQuestion(q);
    } else if (_lastQueryType == 'VOICE') {
      _startVoiceRecording();
    } else {
      _fetchBrief();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfacePureWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppShapes.radiusLg)),
        boxShadow: [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Top Header: Title, Language Selector, Close
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.brandBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI Emergency Assistant',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.deepNavy,
                        ),
                      ),
                      Text(
                        'Ask for situational guidance',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Language toggle (EN / HI)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLangChip('EN', 'en'),
                      _buildLangChip('हिन्दी', 'hi'),
                    ],
                  ),
                ),
                const SizedBox(width: 4),

                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.textSecondary),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Official Disclaimer Notice
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 16, color: AppColors.deepNavy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Push-to-talk voice commands & verified emergency data. Does not replace emergency dispatch (112).',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Quick Questions Carousel / Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.local_hospital_outlined, size: 16, color: AppColors.emergencyRed),
                    label: const Text('Nearest Hospital'),
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.deepNavy),
                    backgroundColor: AppColors.surfaceLight,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    onPressed: _isLoading ? null : () => _askQuestion('Nearest hospital for this emergency'),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.summarize_outlined, size: 16, color: AppColors.brandBlue),
                    label: const Text('Situation Brief'),
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.deepNavy),
                    backgroundColor: AppColors.surfaceLight,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    onPressed: _isLoading ? null : _fetchBrief,
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.person_pin_circle_outlined, size: 16, color: AppColors.brandBlue),
                    label: const Text('Where is my responder?'),
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.deepNavy),
                    backgroundColor: AppColors.surfaceLight,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    onPressed: _isLoading
                        ? null
                        : () => _askQuestion('Where is my responder and what is their current status?'),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.help_outline_rounded, size: 16, color: AppColors.brandBlue),
                    label: const Text('Why is ETA unavailable?'),
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.deepNavy),
                    backgroundColor: AppColors.surfaceLight,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    onPressed: _isLoading
                        ? null
                        : () => _askQuestion('Why is ETA unavailable?'),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.timer_outlined, size: 16, color: AppColors.brandBlue),
                    label: const Text('Road Distance & ETA'),
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.deepNavy),
                    backgroundColor: AppColors.surfaceLight,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    onPressed: _isLoading
                        ? null
                        : () => _askQuestion('What is the road distance and estimated arrival time?'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Voice Status Banner / Recording Controls (Dynamic)
            if (_voiceState == VoiceAssistantState.recording)
              _buildRecordingActiveBanner()
            else if (_voiceState == VoiceAssistantState.transcribing ||
                _voiceState == VoiceAssistantState.processingIntent ||
                _voiceState == VoiceAssistantState.synthesizingSpeech)
              _buildVoiceProcessingBanner(),

            // Text Input & Push-to-Talk Mic Trigger
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    focusNode: _focusNode,
                    maxLength: 200,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: _selectedLanguage == 'hi'
                          ? 'बोलें या स्थिति के बारे में लिखें...'
                          : 'Speak or type your question...',
                      hintStyle: AppTypography.caption.copyWith(color: AppColors.textMuted),
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5),
                      ),
                    ),
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty) {
                        final q = text.trim();
                        _queryController.clear();
                        _askQuestion(q);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Push-to-Talk Mic Action Button
                GestureDetector(
                  onTap: () {
                    if (_voiceState == VoiceAssistantState.recording) {
                      _stopVoiceRecording();
                    } else {
                      _startVoiceRecording();
                    }
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _voiceState == VoiceAssistantState.recording
                          ? AppColors.emergencyRed
                          : AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _voiceState == VoiceAssistantState.recording
                          ? [
                              BoxShadow(
                                color: AppColors.emergencyRed.withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      _voiceState == VoiceAssistantState.recording
                          ? Icons.stop_rounded
                          : Icons.mic_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Text Send Button
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.deepNavy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.arrow_upward_rounded, size: 20),
                  tooltip: 'Send Question',
                  onPressed: _isLoading
                      ? null
                      : () {
                          final text = _queryController.text.trim();
                          if (text.isNotEmpty) {
                            _queryController.clear();
                            _askQuestion(text);
                          }
                        },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Result Display Area (Scrollable)
            Flexible(
              child: SingleChildScrollView(
                child: _buildResultContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingActiveBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.emergencyRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.emergencyRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: AppColors.emergencyRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Listening... 0:0$_recordingSecondsElapsed / 0:10',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.emergencyRed,
              ),
            ),
          ),
          TextButton(
            onPressed: _cancelVoiceRecording,
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emergencyRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: const Size(0, 32),
            ),
            onPressed: _stopVoiceRecording,
            child: const Text('Done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceProcessingBanner() {
    String label = 'Processing voice request...';
    if (_voiceState == VoiceAssistantState.transcribing) {
      label = 'Transcribing with ElevenLabs STT...';
    } else if (_voiceState == VoiceAssistantState.processingIntent) {
      label = 'Retrieving verified hospital & emergency data...';
    } else if (_voiceState == VoiceAssistantState.synthesizingSpeech) {
      label = 'Synthesizing voice response with ElevenLabs TTS...';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.deepNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLangChip(String label, String code) {
    final isSelected = _selectedLanguage == code;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() {
            _selectedLanguage = code;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildResultContent() {
    if (_isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.brandBlue),
            ),
            const SizedBox(height: 14),
            Text(
              'Consulting Gemini AI Assistant...',
              style: AppTypography.bodySecondary.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.deepNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Analyzing verified app telemetry snapshot without PII',
              style: AppTypography.caption.copyWith(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    // 1. Voice Result Display
    if (_voiceResult != null) {
      return _buildVoiceResultCard(_voiceResult!);
    }

    // 2. Text Result Display
    if (_textResponse != null) {
      return _buildTextResultCard(_textResponse!);
    }

    // 3. Idle / Empty State
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          const Icon(Icons.record_voice_over_outlined, size: 32, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(
            'Ask with Voice or Text',
            style: AppTypography.bodySecondary.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.deepNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the Mic icon to speak (e.g. "Tell me the nearest hospital" or "Where is the victim?").',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceResultCard(VoiceQueryResult result) {
    if (!result.success) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warningAmber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic_off_rounded, color: AppColors.warningAmber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.isOfflineOrUnavailable
                        ? 'Voice Assistant Unavailable'
                        : 'Voice Request Unsuccessful',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.deepNavy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.answerText,
              style: AppTypography.bodySecondary.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: const BorderSide(color: AppColors.brandBlue),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Try Again', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _startVoiceRecording,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'SOS & navigation are active',
                    style: AppTypography.caption.copyWith(color: AppColors.emeraldGreen, fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfacePureWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Voice Query Transcript Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.record_voice_over, size: 12, color: AppColors.brandBlue),
                    const SizedBox(width: 4),
                    Text(
                      result.intentType == VoiceIntentType.nearestHospital
                          ? 'VERIFIED HOSPITAL ASSISTANT'
                          : 'VOICE ASSISTANT',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandBlue,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (result.isAudioGenerated)
                IconButton(
                  icon: const Icon(Icons.volume_up_rounded, color: AppColors.brandBlue, size: 20),
                  tooltip: 'Replay Spoken Audio',
                  onPressed: () => _voiceService.replayLastAudio(),
                ),
            ],
          ),

          if (result.transcript.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Recognized: "${result.transcript}"',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
                fontSize: 11.5,
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Main Spoken Answer Text
          SelectableText(
            result.answerText,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.deepNavy,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),

          // Hospital Details Card (if hospital intent)
          if (result.hospital != null) ...[
            const SizedBox(height: 12),
            _buildHospitalDetailsCard(result.hospital!, result.isHospitalUnverified, result.roadEtaText),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: 8),

          // Footer note / Disclaimer
          Text(
            result.disclaimer ??
                'Non-authoritative explanation based strictly on verified snapshot facts. Does not override official dispatch decisions.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHospitalDetailsCard(HospitalModel hospital, bool isUnverified, String? etaText) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUnverified
              ? AppColors.warningAmber.withValues(alpha: 0.5)
              : AppColors.emeraldGreen.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hospital.isGovernmentTraumaCenter
                    ? Icons.local_hospital_rounded
                    : Icons.medical_services_outlined,
                color: hospital.isGovernmentTraumaCenter ? AppColors.emergencyRed : AppColors.brandBlue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hospital.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.deepNavy,
                  ),
                ),
              ),
              if (isUnverified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warningAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Demo Data',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.warningAmber),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Type: ${hospital.type} • Distance: ${VoiceAssistantService.formatDistance(hospital.distanceMeters)}${etaText != null ? ' • ETA: $etaText' : ''}',
            style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.textSecondary),
          ),
          if (widget.onSelectHospitalRoute != null && widget.emergency.isActive) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.navigation_rounded, size: 16),
                label: const Text('Review Route to Hospital', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onSelectHospitalRoute!(hospital);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextResultCard(AIAssistantResponse response) {
    if (!response.success) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warningAmber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_off_rounded, color: AppColors.warningAmber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    response.isOfflineOrUnavailable
                        ? 'AI Assistant Backend Unavailable'
                        : 'Request Unsuccessful',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.deepNavy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              response.message ??
                  'The AI assistant could not be reached. All core emergency navigation and dispatch functions remain fully active.',
              style: AppTypography.bodySecondary.copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: const BorderSide(color: AppColors.brandBlue),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _retryLastAction,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'SOS and navigation are active',
                    style: AppTypography.caption.copyWith(color: AppColors.emeraldGreen, fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfacePureWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 12, color: AppColors.brandBlue),
                    SizedBox(width: 4),
                    Text(
                      'AI SITUATION SUMMARY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandBlue,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (response.model != null)
                Text(
                  response.model!,
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Main answer text
          SelectableText(
            response.answer,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.deepNavy,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.borderSubtle),
          const SizedBox(height: 8),

          // Non-authoritative footer note
          Text(
            response.disclaimer ??
                'Non-authoritative explanation based strictly on verified snapshot facts. Does not override official dispatch decisions.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
