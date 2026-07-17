// ============================================================
// AI 生成：本文件由 AI（Claude / Trae）辅助生成
// 人工修改：经开发者 review、测试反馈与需求确认后迭代调整
// ============================================================
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:health_xiaohe/core/constants/app_colors.dart';
import 'package:health_xiaohe/core/constants/app_radius.dart';
import 'package:health_xiaohe/core/constants/app_shadows.dart';
import 'package:health_xiaohe/presentation/widgets/chat/image_picker_stub.dart'
    if (dart.library.html) 'package:health_xiaohe/presentation/widgets/chat/image_picker_web.dart';

class ChatInputField extends StatefulWidget {
  final Function(String) onSendMessage;
  final Function(Uint8List)? onSendImage;
  final VoidCallback? onVoicePressed;
  final VoidCallback? onHealthRecordPressed;
  final VoidCallback? onCallPressed;

  const ChatInputField({
    super.key,
    required this.onSendMessage,
    this.onSendImage,
    this.onVoicePressed,
    this.onHealthRecordPressed,
    this.onCallPressed,
  });

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> with TickerProviderStateMixin {
  final _controller = TextEditingController();
  bool _isRecording = false;
  bool _panelOpen = false;
  Uint8List? _selectedImage;
  late AnimationController _animController;
  late Animation<double> _panelAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _panelAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _togglePanel() {
    setState(() => _panelOpen = !_panelOpen);
    if (_panelOpen) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  Future<void> _pickImage() async {
    final bytes = await pickImage();
    if (bytes != null && mounted) {
      setState(() => _selectedImage = bytes);
    }
  }

  void _removeImage() {
    setState(() => _selectedImage = null);
  }

  void _send() {
    final text = _controller.text.trim();
    final hasImage = _selectedImage != null;
    if (text.isEmpty && !hasImage) return;

    if (hasImage && widget.onSendImage != null) {
      widget.onSendImage!(_selectedImage!);
    }
    if (text.isNotEmpty) {
      widget.onSendMessage(text);
    }
    _controller.clear();
    setState(() => _selectedImage = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 图片预览
        if (_selectedImage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: AppColors.bgCard,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_selectedImage!, width: 56, height: 56, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Text('图片已选中', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                const Spacer(),
                GestureDetector(
                  onTap: _removeImage,
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
        // 功能面板
        SizeTransition(
          sizeFactor: _panelAnim,
          axisAlignment: 1.0,
          child: _buildPanel(),
        ),
        // 输入栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgBase,
            border: Border(top: BorderSide(color: AppColors.borderSoft)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                // + 按钮
                GestureDetector(
                  onTap: _togglePanel,
                  child: AnimatedRotation(
                    turns: _panelOpen ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border, width: 1.5),
                      ),
                      child: Icon(LucideIcons.plus, color: AppColors.textSecondary, size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 文字输入
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(AppRadius.chip + 4),
                      boxShadow: AppShadows.soft,
                    ),
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: _selectedImage != null ? '输入文字描述...' : '请输入您的健康问题...',
                        hintStyle: TextStyle(color: AppColors.textMuted),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        suffixIcon: GestureDetector(
                          onTapDown: (_) => _startRecording(),
                          onTapUp: (_) => _stopRecording(),
                          onTapCancel: () => _stopRecording(),
                          child: Container(
                            width: 36, height: 36,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: _isRecording ? AppColors.danger : AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isRecording ? LucideIcons.square : LucideIcons.mic,
                              color: Colors.white, size: 16,
                            ),
                          ),
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 发送按钮
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.primary,
                    ),
                    child: const Icon(LucideIcons.arrowUp, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildPanelItem(
            icon: LucideIcons.image, label: '发送图片', color: AppColors.primary,
            onTap: () {
              _togglePanel();
              _pickImage();
            },
          ),
          _buildPanelItem(
            icon: LucideIcons.phone, label: '语音通话', color: AppColors.primary,
            onTap: () {
              _togglePanel();
              widget.onCallPressed?.call();
            },
          ),
          _buildPanelItem(
            icon: LucideIcons.heart, label: '健康记录', color: AppColors.primary,
            onTap: () {
              _togglePanel();
              widget.onHealthRecordPressed?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPanelItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  void _startRecording() {
    setState(() => _isRecording = true);
    widget.onVoicePressed?.call();
  }

  void _stopRecording() {
    setState(() => _isRecording = false);
  }
}
