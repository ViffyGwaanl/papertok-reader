import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/app/app_globals.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_draft_input.dart';
import 'package:papertok_reader/providers/ai_history.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/providers/spaced_review.dart';
import 'package:papertok_reader/service/ai/ai_services.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/enums/ai_thinking_mode.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/page/settings_page/custom_skills.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_workflow_policy.dart';
import 'package:papertok_reader/service/memory/memory_workflow_service.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/utils/ai_reasoning_parser.dart';
import 'package:papertok_reader/widgets/ai/tool_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/tool_tile_base.dart';
import 'package:papertok_reader/widgets/delete_confirm.dart';
import 'package:papertok_reader/widgets/markdown/styled_markdown.dart';
import 'package:papertok_reader/widgets/ai/attachment_picker_dialog.dart';
import 'package:papertok_reader/widgets/common/pt_bottom_sheet.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/deeplink/paperreader_source_opener.dart';
import 'package:papertok_reader/service/knowledge/ai_chat_knowledge_card_producer.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/attachment_item.dart';
import 'package:papertok_reader/models/book_import_item.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/book.dart';
import 'package:papertok_reader/service/receive_file/share_inbox_cleanup_service.dart';
import 'package:papertok_reader/service/receive_file/share_inbox_paths.dart';
import 'package:papertok_reader/service/receive_file/share_safe_import.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/common/pt_collapsible_card.dart';
import 'package:papertok_reader/widgets/common/anx_segmented_button.dart';
import 'package:papertok_reader/utils/get_path/get_cache_dir.dart';
import 'package:papertok_reader/utils/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import 'package:papertok_reader/models/ai_quick_prompt_chip.dart';

class _ConfigurableSkillPickerRow extends StatelessWidget {
  const _ConfigurableSkillPickerRow({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.configLabel,
    required this.onSelect,
    required this.onConfigure,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final String configLabel;
  final VoidCallback onSelect;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onSelect();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? ClaudePalette.accentTint(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? ClaudePalette.accent(context)
                    : ClaudePalette.secondary(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: ClaudePalette.fg(context),
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: ClaudePalette.secondary(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: ClaudePalette.accent(context),
                ),
              ],
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onConfigure,
                icon: const Icon(Icons.tune_outlined, size: 16),
                label: Text(configLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuiltInSkillPromptSettingsSheet extends StatefulWidget {
  const _BuiltInSkillPromptSettingsSheet({
    required this.initialPrompt,
    required this.description,
    required this.label,
    required this.hint,
    required this.clearLabel,
    required this.cancelLabel,
    required this.saveLabel,
    required this.onClear,
    required this.onSave,
  });

  final String initialPrompt;
  final String description;
  final String label;
  final String hint;
  final String clearLabel;
  final String cancelLabel;
  final String saveLabel;
  final VoidCallback onClear;
  final ValueChanged<String> onSave;

  @override
  State<_BuiltInSkillPromptSettingsSheet> createState() =>
      _BuiltInSkillPromptSettingsSheetState();
}

class _BuiltInSkillPromptSettingsSheetState
    extends State<_BuiltInSkillPromptSettingsSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.description,
            style: TextStyle(
              fontSize: 13,
              color: ClaudePalette.secondary(context),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 4,
            maxLines: 8,
            maxLength: Prefs.aiSkillCustomPromptMaxChars,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: widget.label,
              hintText: widget.hint,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: widget.onClear,
                child: Text(widget.clearLabel),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.cancelLabel),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => widget.onSave(_controller.text),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(widget.saveLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeminarRunConfig {
  const _SeminarRunConfig({
    required this.includeVerifier,
    required this.maxRounds,
    required this.roleProfiles,
  });

  final bool includeVerifier;
  final int maxRounds;
  final List<AiSeminarRoleProfile> roleProfiles;
}

class _SeminarRunSetupSheet extends StatefulWidget {
  const _SeminarRunSetupSheet({
    required this.initialQuestion,
    required this.cancelLabel,
    required this.startLabel,
    required this.onStart,
  });

  final String initialQuestion;
  final String cancelLabel;
  final String startLabel;
  final void Function(String question, _SeminarRunConfig config) onStart;

  @override
  State<_SeminarRunSetupSheet> createState() => _SeminarRunSetupSheetState();
}

class _SeminarRunSetupSheetState extends State<_SeminarRunSetupSheet> {
  late final TextEditingController _questionController;
  late final TextEditingController _maxRoundsController;
  late final Map<AiSeminarRole, TextEditingController> _promptControllers;
  late final Map<AiSeminarRole, TextEditingController> _nameControllers;
  late final Map<AiSeminarRole, AiSeminarRoleProfile?> _baseProfiles;
  late final Map<AiSeminarRole, bool> _roleEnabled;
  late final Map<AiSeminarRole, Set<AiSeminarEvidenceScope>>
      _roleEvidenceScopes;
  late final Set<AiSeminarRole> _roleEvidenceScopeTouched;
  late bool _includeVerifier;

  @override
  void initState() {
    super.initState();
    _questionController = TextEditingController(text: widget.initialQuestion);
    _maxRoundsController = TextEditingController(text: '2');
    _includeVerifier = Prefs().aiSeminarIncludeVerifier;
    _baseProfiles = {
      for (final role in AiSeminarRole.values)
        role: Prefs().aiSeminarRoleProfileFor(role),
    };
    _promptControllers = {
      for (final role in AiSeminarRole.values)
        role: TextEditingController(
          text: _baseProfiles[role]?.customPrompt ?? '',
        ),
    };
    _nameControllers = {
      for (final role in AiSeminarRole.values)
        role: TextEditingController(
          text: _baseProfiles[role]?.name ?? '',
        ),
    };
    _roleEnabled = {
      for (final role in AiSeminarRole.values)
        role: _baseProfiles[role]?.enabled ?? true,
    };
    _roleEvidenceScopes = {
      for (final role in AiSeminarRole.values)
        role: {
          ...(_baseProfiles[role]?.evidenceScopes ??
              const <AiSeminarEvidenceScope>[]),
        },
    };
    _roleEvidenceScopeTouched = <AiSeminarRole>{};
  }

  @override
  void dispose() {
    _questionController.dispose();
    _maxRoundsController.dispose();
    for (final controller in _promptControllers.values) {
      controller.dispose();
    }
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final roleOrder = [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
      AiSeminarRole.verifier,
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            zh
                ? '这次配置只影响即将插入的研讨卡，不会覆盖全局设置。'
                : 'These settings only affect the next Seminar card.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _questionController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: zh ? '研讨问题' : 'Seminar question',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('seminar-run-max-rounds'),
            controller: _maxRoundsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: zh ? '最多讨论轮次' : 'Max discussion rounds',
              helperText: zh
                  ? '出现分歧时可刷新证据再讨论，范围 1-5。'
                  : 'When disagreements appear, evidence can refresh and the panel can continue. Range 1-5.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.verified_outlined),
            title: Text(zh ? '加入核验者' : 'Include verifier'),
            subtitle: Text(zh
                ? '让一个角色专门检查证据和引用。'
                : 'Adds a role focused on evidence checks.'),
            value: _includeVerifier,
            onChanged: (value) => setState(() => _includeVerifier = value),
          ),
          const SizedBox(height: 6),
          for (final role in roleOrder)
            _SeminarRunRoleProfileTile(
              role: role,
              initiallyExpanded: role == AiSeminarRole.critical,
              enabled: _roleEnabled[role] ?? true,
              nameController: _nameControllers[role]!,
              promptController: _promptControllers[role]!,
              evidenceScopes:
                  _roleEvidenceScopes[role] ?? const <AiSeminarEvidenceScope>{},
              onEnabledChanged: (value) {
                setState(() => _roleEnabled[role] = value);
              },
              onEvidenceScopeToggled: (scope) {
                setState(() {
                  _roleEvidenceScopeTouched.add(role);
                  final scopes = _roleEvidenceScopes.putIfAbsent(
                    role,
                    () => <AiSeminarEvidenceScope>{},
                  );
                  if (scopes.contains(scope)) {
                    scopes.remove(scope);
                  } else {
                    scopes.add(scope);
                  }
                });
              },
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(widget.cancelLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('seminar-run-start'),
                  icon: const Icon(Icons.groups_2_outlined),
                  label: Text(widget.startLabel),
                  onPressed: _start,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _start() {
    final maxRounds = int.tryParse(_maxRoundsController.text.trim()) ?? 2;
    final profiles = <AiSeminarRoleProfile>[];
    for (final role in AiSeminarRole.values) {
      final baseProfile = _baseProfiles[role];
      final selectedScopes =
          _roleEvidenceScopes[role] ?? const <AiSeminarEvidenceScope>{};
      final evidenceScopes =
          selectedScopes.isEmpty && _roleEvidenceScopeTouched.contains(role)
              ? const <AiSeminarEvidenceScope>[
                  AiSeminarEvidenceScope.currentBook,
                ]
              : selectedScopes.toList(growable: false);
      final profile = AiSeminarRoleProfile(
        role: role,
        name: _nameControllers[role]?.text,
        customPrompt: _promptControllers[role]?.text,
        enabled: _roleEnabled[role] ?? true,
        evidenceScopes: evidenceScopes,
        allowedToolIds: baseProfile?.allowedToolIds ?? const <String>[],
      );
      if (profile.hasOverrides) {
        profiles.add(profile);
      }
    }
    widget.onStart(
      _questionController.text,
      _SeminarRunConfig(
        includeVerifier: _includeVerifier,
        maxRounds: maxRounds.clamp(1, 5).toInt(),
        roleProfiles: List.unmodifiable(profiles),
      ),
    );
  }
}

class _SeminarRunRoleProfileTile extends StatelessWidget {
  const _SeminarRunRoleProfileTile({
    required this.role,
    required this.initiallyExpanded,
    required this.enabled,
    required this.nameController,
    required this.promptController,
    required this.evidenceScopes,
    required this.onEnabledChanged,
    required this.onEvidenceScopeToggled,
  });

  final AiSeminarRole role;
  final bool initiallyExpanded;
  final bool enabled;
  final TextEditingController nameController;
  final TextEditingController promptController;
  final Set<AiSeminarEvidenceScope> evidenceScopes;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<AiSeminarEvidenceScope> onEvidenceScopeToggled;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final label = _seminarRunRoleLabel(context, role);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ClaudePalette.divider(context)),
        ),
      ),
      child: ExpansionTile(
        key: ValueKey('seminar-run-role-${role.asString}'),
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: initiallyExpanded,
        title: Text(label),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(zh ? '启用$label' : 'Enable $label'),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: zh ? '$label名称' : '$label name',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('seminar-run-role-${role.asString}-prompt'),
            controller: promptController,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: zh ? '$label提示词' : '$label prompt',
              hintText: zh
                  ? '例如：先列出你不同意的论点，再说明需要哪些证据。'
                  : 'Example: list what you disagree with first, then name the evidence needed.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              zh ? '本次证据范围' : 'Run evidence scope',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SeminarRunEvidenceScopeChip(
                key: ValueKey(
                  'seminar-run-role-${role.asString}-scope-current-book',
                ),
                label: zh ? '当前书' : 'Current book',
                selected: evidenceScopes.isEmpty ||
                    evidenceScopes.contains(AiSeminarEvidenceScope.currentBook),
                onPressed: () => onEvidenceScopeToggled(
                  AiSeminarEvidenceScope.currentBook,
                ),
              ),
              _SeminarRunEvidenceScopeChip(
                key: ValueKey(
                  'seminar-run-role-${role.asString}-scope-library',
                ),
                label: zh ? '书库' : 'Library',
                selected:
                    evidenceScopes.contains(AiSeminarEvidenceScope.library),
                onPressed: () => onEvidenceScopeToggled(
                  AiSeminarEvidenceScope.library,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeminarRunEvidenceScopeChip extends StatelessWidget {
  const _SeminarRunEvidenceScopeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      avatar: Icon(
        selected ? Icons.check_circle_outline : Icons.circle_outlined,
        size: 16,
      ),
      onSelected: (_) => onPressed(),
    );
  }
}

String _seminarRunRoleLabel(BuildContext context, AiSeminarRole role) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return switch (role) {
    AiSeminarRole.critical => zh ? '批判者' : 'Critical',
    AiSeminarRole.supportive => zh ? '支持者' : 'Supportive',
    AiSeminarRole.synthesizer => zh ? '综合者' : 'Synthesizer',
    AiSeminarRole.verifier => zh ? '核验者' : 'Verifier',
  };
}

class AiChatStream extends ConsumerStatefulWidget {
  const AiChatStream({
    super.key,
    this.initialMessage,
    this.sendImmediate = false,
    this.quickPromptChips = const [],
    this.trailing,
    this.scrollController,
    this.onRequestMinimize,
    this.bottomPadding = 0,
    this.inputSafeAreaBottom = true,
    this.resizeToAvoidBottomInset = true,
    this.emptyStateBuilder,
    this.chatKnowledgeCardProducer,
    this.memoryWorkflowService,
    this.sourceOpener,
    this.initialSourceRef,
    this.uiVisible = true,
  });

  final String? initialMessage;
  final bool sendImmediate;
  final List<AiQuickPromptChip> quickPromptChips;
  final List<Widget>? trailing;

  /// Optional external scroll controller used for the message list.
  ///
  /// This is mainly for integrating with [DraggableScrollableSheet].
  final ScrollController? scrollController;

  /// Optional callback used by bottom-sheet mode to minimize the sheet.
  final VoidCallback? onRequestMinimize;

  /// Extra bottom padding used for bottom overlays (e.g. floating home tab bar).
  ///
  /// This is applied as *internal* padding inside the input box so the bar can
  /// float above the content without leaving a visible blank gap.
  final double bottomPadding;

  /// Whether the input box should add the system bottom safe area.
  ///
  /// On Home AI tab we set this to false because HomePage already places a
  /// floating tab bar with its own bottom safe area.
  final bool inputSafeAreaBottom;

  /// When AiChatStream is used inside another Scaffold (e.g. Home tab page),
  /// letting both Scaffolds handle viewInsets can cause the keyboard inset to be
  /// applied twice on iOS, leaving a large blank gap above the keyboard.
  final bool resizeToAvoidBottomInset;

  /// Custom empty state builder.
  ///
  /// This is mainly for the Home AI tab where we want a cleaner design.
  /// The callback can be used to send a prompt directly.
  final Widget Function(
          BuildContext context, void Function(String prompt) send)?
      emptyStateBuilder;

  final AiChatKnowledgeCardProducer? chatKnowledgeCardProducer;
  final MemoryWorkflowService? memoryWorkflowService;
  final PaperReaderSourceOpener? sourceOpener;
  final SourceRef? initialSourceRef;
  final bool uiVisible;

  @override
  ConsumerState<AiChatStream> createState() => AiChatStreamState();
}

enum _MessageMemoryAction {
  rememberNow,
  saveToLongTerm,
  addToReviewInbox,
  undoDirectSave,
}

enum _SeminarRunSnapshotSubview {
  overview('overview'),
  evidence('evidence'),
  roles('roles'),
  disagreements('disagreements'),
  whiteboard('whiteboard'),
  summary('summary'),
  review('review');

  const _SeminarRunSnapshotSubview(this.id);

  final String id;
}

class AiChatStreamState extends ConsumerState<AiChatStream> {
  final TextEditingController inputController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final MemoryWorkflowService _memoryWorkflow =
      widget.memoryWorkflowService ?? MemoryWorkflowService();
  late final AiChatKnowledgeCardProducer _chatKnowledgeCards =
      widget.chatKnowledgeCardProducer ?? AiChatKnowledgeCardProducer();
  late final PaperReaderSourceOpener _sourceOpener =
      widget.sourceOpener ?? openPaperReaderSource;

  bool _suppressDraftSync = false;
  bool _inlineSeminarVisible = false;
  String? _inlineSeminarQuestion;
  String? _inlineSeminarSessionId;
  int? _inlineSeminarBookId;
  SourceRef? _inlineSeminarSourceRef;
  List<AiSeminarRoleProfile>? _inlineSeminarRoleProfiles;
  int? _inlineSeminarMaxRounds;
  bool? _inlineSeminarIncludeVerifier;
  final Map<String, String> _lastSeminarCardSignatures = {};
  final Map<String, TextEditingController> _seminarCardReplyControllers = {};
  final Map<String, AiSeminarRole> _seminarCardSelectedRoles = {};
  final Map<String, _SeminarRunSnapshotSubview> _seminarCardSnapshotSubviews =
      {};
  final Set<String> _seminarCardSubmittingSessionIds = <String>{};
  final Set<String> _seminarCardSavedKnowledgeCardIds = <String>{};
  final Set<String> _seminarCardSpacedReviewFlashcardIds = <String>{};
  final Set<String> _seminarCardConceptNodeIds = <String>{};
  final Set<String> _seminarCardIgnoredActionSessionIds = <String>{};
  final Map<String, MemoryCandidate> _directMemoryByMessageKey =
      <String, MemoryCandidate>{};

  String? _seminarRuntimeScopeId(String? raw) {
    final value = raw?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String _newSeminarChatSessionId() {
    return 'seminar-chat-${DateTime.now().microsecondsSinceEpoch}';
  }

  String? _seminarSynthesisKnowledgeCardId(String? sessionId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return null;
    }
    return 'seminar:$normalizedSessionId:synthesis-card';
  }

  String? _seminarSynthesisReviewFlashcardId(String? sessionId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return null;
    }
    return 'seminar:$normalizedSessionId:synthesis-review';
  }

  String? _seminarSynthesisConceptNodeId(String? sessionId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return null;
    }
    return 'seminar:$normalizedSessionId:synthesis-node';
  }

  AiSeminarRuntimeState _watchSeminarRuntimeState(String? sessionId) {
    final scopeId = _seminarRuntimeScopeId(sessionId);
    return scopeId == null
        ? ref.watch(aiSeminarRuntimeProvider)
        : ref.watch(aiSeminarRuntimeScopedProvider(scopeId));
  }

  AiSeminarRuntimeState _readSeminarRuntimeState(String? sessionId) {
    final scopeId = _seminarRuntimeScopeId(sessionId);
    return scopeId == null
        ? ref.read(aiSeminarRuntimeProvider)
        : ref.read(aiSeminarRuntimeScopedProvider(scopeId));
  }

  AiSeminarRuntimeNotifier _readSeminarRuntimeNotifier(String? sessionId) {
    final scopeId = _seminarRuntimeScopeId(sessionId);
    return scopeId == null
        ? ref.read(aiSeminarRuntimeProvider.notifier)
        : ref.read(aiSeminarRuntimeScopedProvider(scopeId).notifier);
  }

  void _onDraftInputChanged() {
    if (_suppressDraftSync) return;
    if (inputController.text.trim().isEmpty) {
      _draftSourceRef = null;
      _draftSourceRefSeedText = null;
    }
    try {
      ref.read(aiChatDraftInputProvider.notifier).set(inputController.text);
    } catch (_) {
      // Best-effort.
    }
  }

  late ScrollController _scrollController;
  bool _ownsScrollController = false;

  bool get _isStreaming => ref.read(aiChatStreamingProvider);

  // Bottom sheet convenience gesture: swipe down on input box to minimize.
  double _inputSwipeDownDy = 0;

  // Auto-scroll behavior:
  // - Do NOT jump to bottom when opening the panel.
  // - While streaming, only keep scrolling if the user is already near bottom.
  bool _pinnedToBottom = false;

  // For each user turn, the assistant may have multiple generated variants.
  // We keep a lightweight UI-only selection index per turn.
  final Map<int, int> _selectedVariantByUserIndex = {};
  final Map<int, SourceRef> _sourceRefByUserIndex = {};
  SourceRef? _draftSourceRef;
  String? _draftSourceRefSeedText;
  bool _uiVisibleSyncScheduled = false;
  AiHistoryScope _historyScope = AiHistoryScope.currentBook;
  int? _historyScopeBookId;

  // Attachments for multimodal chat (sent to the model)
  final List<AttachmentItem> _attachments = [];

  // Book files queued for bookshelf import (UI-only; never sent to the model).
  final List<BookImportItem> _pendingBookImports = [];

  // Cache decoded base64 images for chat bubbles to avoid flicker during
  // streaming rebuilds.
  // Key: base64 string (no data: prefix).
  final LinkedHashMap<String, Uint8List> _decodedImageCache = LinkedHashMap();
  static const int _decodedImageCacheMaxEntries = 32;

  late final List<AiServiceOption> _builtInOptions;
  late final Map<String, AiServiceOption> _builtInById;
  late List<AiProviderMeta> _providers;
  late String _selectedProviderId;

  late List<String> _suggestedPrompts;
  late List<String> _starterPrompts;
  bool _starterPromptsReady = false;

  List<Map<String, String>> _getQuickPrompts(BuildContext context) {
    // Use customized prompts if available.
    final custom = Prefs().aiInputQuickPrompts;
    if (custom.isNotEmpty) {
      return custom
          .where((p) => p.enabled)
          .map((p) => {'label': p.label, 'prompt': p.prompt})
          .toList();
    }
    // Fall back to localized defaults.
    return [
      {
        'label': L10n.of(context).aiQuickPromptExplain,
        'prompt': L10n.of(context).aiQuickPromptExplainText,
      },
      {
        'label': L10n.of(context).aiQuickPromptOpinion,
        'prompt': L10n.of(context).aiQuickPromptOpinionText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSummary,
        'prompt': L10n.of(context).aiQuickPromptSummaryText,
      },
      {
        'label': L10n.of(context).aiQuickPromptAnalyze,
        'prompt': L10n.of(context).aiQuickPromptAnalyzeText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSuggest,
        'prompt': L10n.of(context).aiQuickPromptSuggestText,
      },
    ];
  }

  void _handleScroll() {
    // Be defensive: scroll controller may be swapped/rebuilt by the sheet.
    try {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final offset = _scrollController.offset;
      // Within 120px counts as "at bottom".
      _pinnedToBottom = (max - offset) < 120;
    } catch (_) {
      // Ignore (e.g. controller disposed during rebuild).
    }
  }

  void _attachScrollController(ScrollController? external) {
    // Detach old controller.
    try {
      _scrollController.removeListener(_handleScroll);
    } catch (_) {}

    if (_ownsScrollController) {
      try {
        _scrollController.dispose();
      } catch (_) {}
    }

    _ownsScrollController = external == null;
    _scrollController = external ?? ScrollController();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void initState() {
    super.initState();
    _scheduleSyncUiVisible();

    _scrollController = ScrollController();
    _attachScrollController(widget.scrollController);

    _starterPrompts = const [];
    _builtInOptions = buildDefaultAiServices();
    _builtInById = {
      for (final option in _builtInOptions) option.identifier: option,
    };

    _ensureProvidersInitialized();
    _providers = Prefs().aiProvidersV1;

    _selectedProviderId = Prefs().selectedAiService;
    if (!_isProviderSelectable(_selectedProviderId)) {
      _selectedProviderId = _fallbackProviderId(_providers);
      Prefs().selectedAiService = _selectedProviderId;
    }
    // Shared draft input (allows other pages to insert snippets).
    final draft = ref.read(aiChatDraftInputProvider);
    final initial = draft.isNotEmpty ? draft : (widget.initialMessage ?? '');
    inputController.text = initial;
    _draftSourceRef = widget.initialSourceRef;
    _draftSourceRefSeedText = widget.initialSourceRef == null ? null : initial;
    ref.read(aiChatDraftInputProvider.notifier).set(initial);
    inputController.addListener(_onDraftInputChanged);

    // Share Sheet may enqueue pending book imports before the chat UI builds.
    pendingShareBookImportPaths.addListener(_drainPendingShareBookImports);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drainPendingShareBookImports();
    });

    _suggestedPrompts = const [];
    if (widget.sendImmediate) {
      _sendMessage();
    }
  }

  @override
  void didUpdateWidget(covariant AiChatStream oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.scrollController != widget.scrollController) {
      _attachScrollController(widget.scrollController);
    }
    if (oldWidget.uiVisible != widget.uiVisible) {
      _scheduleSyncUiVisible();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize localized starter prompts using the widget's own context.
    // Avoid depending on a global navigator context in initState.
    if (!_starterPromptsReady) {
      final l10n = L10n.of(context);
      _starterPrompts = [
        l10n.quickPrompt1,
        l10n.quickPrompt2,
        l10n.quickPrompt3,
        l10n.quickPrompt4,
        l10n.quickPrompt5,
        l10n.quickPrompt6,
        l10n.quickPrompt7,
        l10n.quickPrompt8,
        l10n.quickPrompt9,
        l10n.quickPrompt10,
        l10n.quickPrompt11,
        l10n.quickPrompt12,
      ];
      _suggestedPrompts = _pickSuggestedPrompts();
      _starterPromptsReady = true;
    }
  }

  @override
  void dispose() {
    try {
      pendingShareBookImportPaths.removeListener(_drainPendingShareBookImports);
    } catch (_) {}
    try {
      inputController.removeListener(_onDraftInputChanged);
    } catch (_) {}
    inputController.dispose();
    for (final controller in _seminarCardReplyControllers.values) {
      controller.dispose();
    }
    try {
      _scrollController.removeListener(_handleScroll);
    } catch (_) {}
    if (_ownsScrollController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _scheduleSyncUiVisible() {
    if (_uiVisibleSyncScheduled) {
      return;
    }
    _uiVisibleSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _uiVisibleSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final visible = widget.uiVisible;
      ref.read(aiChatProvider.notifier).setStreamingUiVisible(visible);
    });
  }

  void _ensureProvidersInitialized() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final builtIns = _builtInOptions.map((option) {
      final type = switch (option.identifier) {
        'claude' => AiProviderType.anthropic,
        'gemini' => AiProviderType.gemini,
        'openai-responses' => AiProviderType.openaiResponses,
        _ => AiProviderType.openaiCompatible,
      };

      return AiProviderMeta(
        id: option.identifier,
        name: option.title,
        type: type,
        enabled: true,
        isBuiltIn: true,
        createdAt: now,
        updatedAt: now,
        logoKey: option.logo,
      );
    }).toList(growable: false);

    Prefs().ensureAiProvidersV1Initialized(builtIns: builtIns);
  }

  AiProviderMeta? _providerById(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool _isProviderSelectable(String id) {
    final p = _providerById(id);
    return p != null && p.enabled;
  }

  String _fallbackProviderId(List<AiProviderMeta> providers) {
    for (final p in providers) {
      if (p.id == 'openai' && p.enabled) return p.id;
    }
    for (final p in providers) {
      if (p.enabled) return p.id;
    }
    return 'openai';
  }

  AiProviderMeta get _currentProvider {
    return _providerById(_selectedProviderId) ??
        (_providers.isNotEmpty
            ? _providers.first
            : AiProviderMeta(
                id: 'openai',
                name: 'OpenAI',
                type: AiProviderType.openaiCompatible,
                enabled: true,
                isBuiltIn: true,
                createdAt: 0,
                updatedAt: 0,
              ));
  }

  AiServiceOption? _builtInOptionForProvider(AiProviderMeta meta) {
    final exact = _builtInById[meta.id];
    if (exact != null) return exact;

    // Custom providers: fall back to the built-in logo/model per type.
    switch (meta.type) {
      case AiProviderType.anthropic:
        return _builtInById['claude'];
      case AiProviderType.gemini:
        return _builtInById['gemini'];
      case AiProviderType.openaiResponses:
        return _builtInById['openai-responses'];
      case AiProviderType.openaiCompatible:
        return _builtInById['openai'];
    }
  }

  String _providerLogoKey(AiProviderMeta meta) {
    return meta.logoKey ?? _builtInOptionForProvider(meta)?.logo ?? '';
  }

  String _modelLabel(String providerId) {
    final stored = Prefs().getAiConfig(providerId);
    final model = stored['model']?.trim();
    if (model != null && model.isNotEmpty) {
      return model;
    }

    final meta = _providerById(providerId);
    final builtIn = meta == null
        ? _builtInById[providerId]
        : _builtInOptionForProvider(meta);

    return builtIn?.defaultModel ?? '';
  }

  Future<void> _onProviderSelected(String providerId) async {
    if (_isStreaming || providerId == _selectedProviderId) return;
    if (!_isProviderSelectable(providerId)) return;

    await _flushMemoryBeforeContextSwitch();

    Prefs().selectedAiService = providerId;
    setState(() {
      _selectedProviderId = providerId;
    });
  }

  Future<void> _flushMemoryBeforeContextSwitch() async {
    final prefs = Prefs();
    if (!prefs.memorySessionDigestEnabled) {
      return;
    }

    final messages =
        ref.read(aiChatProvider).asData?.value ?? const <ChatMessage>[];
    if (messages.length < 2) {
      return;
    }

    try {
      ref.read(aiChatProvider.notifier).persistCurrentConversation(ref);
      await _memoryWorkflow.captureSessionDigest(
        messages: messages,
        dailyStrategy: prefs.memoryWorkflowDailyStrategy,
        conversationId: ref.read(aiChatProvider.notifier).currentSessionId,
        triggerKind: 'provider_switch',
      );
    } catch (_) {
      // Best effort only. Provider switching should not hard-fail on digest.
    }
  }

  AiThinkingMode _thinkingModeForProvider(String providerId) {
    final existing = Prefs().getAiConfig(providerId);
    return aiThinkingModeFromString(existing['thinking_mode'] ?? 'auto');
  }

  bool _includeThoughtsForProvider(AiProviderMeta provider) {
    if (provider.type != AiProviderType.gemini) {
      return false;
    }
    final existing = Prefs().getAiConfig(provider.id);
    final raw = (existing['include_thoughts'] ?? 'true').trim().toLowerCase();
    return raw != 'false' && raw != '0' && raw != 'no';
  }

  String _thinkingModeLabel(AiThinkingMode mode, L10n l10n) {
    switch (mode) {
      case AiThinkingMode.off:
        return l10n.aiThinkingOff;
      case AiThinkingMode.auto:
        return l10n.aiThinkingAuto;
      case AiThinkingMode.minimal:
        return l10n.aiThinkingMinimal;
      case AiThinkingMode.low:
        return l10n.aiThinkingLow;
      case AiThinkingMode.medium:
        return l10n.aiThinkingMedium;
      case AiThinkingMode.high:
        return l10n.aiThinkingHigh;
    }
  }

  List<AiThinkingMode> _supportedThinkingModes(AiProviderMeta provider) {
    final stored = Prefs().getAiConfig(provider.id);
    final model = (stored['model'] ?? '').trim().toLowerCase();

    switch (provider.type) {
      case AiProviderType.openaiCompatible:
      case AiProviderType.openaiResponses:
        return const [
          AiThinkingMode.off,
          AiThinkingMode.auto,
          AiThinkingMode.minimal,
          AiThinkingMode.low,
          AiThinkingMode.medium,
          AiThinkingMode.high,
        ];
      case AiProviderType.anthropic:
        return const [
          AiThinkingMode.off,
          AiThinkingMode.auto,
          AiThinkingMode.low,
          AiThinkingMode.medium,
          AiThinkingMode.high,
        ];
      case AiProviderType.gemini:
        // Best-effort gating based on Gemini official doc.
        if (model.contains('gemini-3-pro')) {
          return const [
            AiThinkingMode.auto,
            AiThinkingMode.low,
            AiThinkingMode.high,
          ];
        }
        if (model.contains('gemini-2.5-pro')) {
          // Doc says: cannot disable thinking.
          return const [
            AiThinkingMode.auto,
            AiThinkingMode.low,
            AiThinkingMode.medium,
            AiThinkingMode.high,
          ];
        }
        return const [
          AiThinkingMode.off,
          AiThinkingMode.auto,
          AiThinkingMode.minimal,
          AiThinkingMode.low,
          AiThinkingMode.medium,
          AiThinkingMode.high,
        ];
    }
  }

  IconData _thinkingIcon(AiThinkingMode mode) {
    switch (mode) {
      case AiThinkingMode.off:
        return Icons.lightbulb_outline;
      case AiThinkingMode.auto:
        return Icons.auto_awesome;
      case AiThinkingMode.minimal:
        return Icons.lightbulb_outline;
      case AiThinkingMode.low:
        return Icons.lightbulb_outline;
      case AiThinkingMode.medium:
        return Icons.lightbulb;
      case AiThinkingMode.high:
        return Icons.lightbulb;
    }
  }

  String _localizedSkillName(BuildContext context, AiSkill skill) {
    final l = L10n.of(context);
    switch (skill.id) {
      case 'paper_analyzer':
        return l.aiSkillPaperAnalyzerName;
      case 'flashcard_generator':
        return l.aiSkillFlashcardGeneratorName;
      case 'debate_partner':
        return l.aiSkillDebatePartnerName;
      case 'vocab_extractor':
        return l.aiSkillVocabExtractorName;
      case 'reading_companion':
        return l.aiSkillReadingCompanionName;
      case 'seminar_mode':
        return l.aiSkillSeminarModeName;
      default:
        return skill.name;
    }
  }

  String _localizedSkillDesc(BuildContext context, AiSkill skill) {
    final l = L10n.of(context);
    switch (skill.id) {
      case 'paper_analyzer':
        return l.aiSkillPaperAnalyzerDesc;
      case 'flashcard_generator':
        return l.aiSkillFlashcardGeneratorDesc;
      case 'debate_partner':
        return l.aiSkillDebatePartnerDesc;
      case 'vocab_extractor':
        return l.aiSkillVocabExtractorDesc;
      case 'reading_companion':
        return l.aiSkillReadingCompanionDesc;
      case 'seminar_mode':
        return l.aiSkillSeminarModeDesc;
      default:
        return skill.description;
    }
  }

  static const String _noSkillSentinel = '__none__';

  Widget _buildSkillButton(BuildContext context) {
    final activeId = Prefs().activeAiSkillId;
    final active = AiSkillRegistry.byId(activeId);
    final isActive = active != null;

    // Use a non-null sentinel for the "no skill" item. PopupMenuButton<T?>
    // treats `value: null` the same as "menu dismissed", so onSelected never
    // fires — we can't distinguish a tap on "no skill" from tapping outside.
    return PopupMenuButton<String>(
      icon: Icon(
        isActive ? Icons.auto_fix_high : Icons.auto_fix_high_outlined,
        size: 18,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
      tooltip: L10n.of(context).aiSkillsTooltip,
      onSelected: (value) {
        setState(() {
          Prefs().activeAiSkillId = value == _noSkillSentinel ? null : value;
        });
      },
      itemBuilder: (context) {
        final skills = AiSkillRegistry.allSkills();
        return [
          PopupMenuItem<String>(
            value: _noSkillSentinel,
            child: Row(
              children: [
                Icon(Icons.block,
                    size: 16,
                    color: !isActive
                        ? Theme.of(context).colorScheme.primary
                        : null),
                const SizedBox(width: 8),
                Text(L10n.of(context).aiSkillNone),
                if (!isActive) ...[
                  const Spacer(),
                  Icon(Icons.check,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          ),
          const PopupMenuDivider(),
          ...skills.map((skill) {
            final selected = skill.id == activeId;
            return PopupMenuItem<String>(
              value: skill.id,
              child: Row(
                children: [
                  Icon(
                    Icons.auto_fix_high,
                    size: 16,
                    color:
                        selected ? Theme.of(context).colorScheme.primary : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_localizedSkillName(context, skill),
                            style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            )),
                        Text(_localizedSkillDesc(context, skill),
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            );
          }),
        ];
      },
    );
  }

  Future<void> _editThinkingMode() async {
    if (_isStreaming) return;

    final l10n = L10n.of(context);
    final provider = _currentProvider;
    final supported = _supportedThinkingModes(provider);

    await PTBottomSheet.show<void>(
      context,
      title: l10n.aiThinkingTitle,
      subtitle: provider.name,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final liveCurrent = _thinkingModeForProvider(provider.id);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (provider.type == AiProviderType.gemini)
                  SwitchListTile.adaptive(
                    title:
                        Text(l10n.settingsAiProviderCenterIncludeThoughtsTitle),
                    subtitle:
                        Text(l10n.settingsAiProviderCenterIncludeThoughtsDesc),
                    value: _includeThoughtsForProvider(provider),
                    onChanged: (v) {
                      final next = Map<String, String>.from(
                        Prefs().getAiConfig(provider.id),
                      );
                      next['include_thoughts'] = v ? 'true' : 'false';
                      Prefs().saveAiConfig(provider.id, next);
                      setState(() {});
                      setLocalState(() {});
                    },
                  ),
                for (final mode in AiThinkingMode.values)
                  Opacity(
                    opacity: supported.contains(mode) ? 1.0 : 0.4,
                    child: IgnorePointer(
                      ignoring: !supported.contains(mode),
                      child: PTPickerRow<AiThinkingMode>(
                        value: mode,
                        groupValue: liveCurrent,
                        title: _thinkingModeLabel(mode, l10n),
                        leading: _thinkingIcon(mode),
                        onChanged: (v) {
                          final next = Map<String, String>.from(
                            Prefs().getAiConfig(provider.id),
                          );
                          next['thinking_mode'] = aiThinkingModeToString(v);
                          Prefs().saveAiConfig(provider.id, next);
                          setState(() {});
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editCurrentModel() async {
    if (_isStreaming) return;

    final l10n = L10n.of(context);
    final provider = _currentProvider;

    final existing = Prefs().getAiConfig(provider.id);
    final controller = TextEditingController(
      text: (existing['model'] ?? '').trim(),
    );
    final cached =
        Prefs().getAiModelsCacheV1(provider.id)?.models ?? const <String>[];

    try {
      final ok = await PTBottomSheet.show<bool>(
        context,
        title: l10n.aiChatEditModelTitle,
        subtitle: provider.name,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocalState) {
              String selected = controller.text.trim();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cached.isNotEmpty) ...[
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final m in cached)
                            PTPickerRow<String>(
                              value: m,
                              groupValue: selected,
                              title: m,
                              onChanged: (v) {
                                controller.text = v;
                                setLocalState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.aiChatModelLabel,
                    ),
                    onChanged: (_) => setLocalState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(l10n.commonCancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(l10n.commonSave),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      );

      if (ok != true || !mounted) return;

      final nextModel = controller.text.trim();
      final next = Map<String, String>.from(existing);
      if (nextModel.isEmpty) {
        next.remove('model');
      } else {
        next['model'] = nextModel;
      }

      Prefs().saveAiConfig(provider.id, next);
      setState(() {});
    } finally {
      controller.dispose();
    }
  }

  List<String> _pickSuggestedPrompts() {
    final prompts = List<String>.from(_starterPrompts)..shuffle();
    return prompts.take(3).toList(growable: false);
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_pinnedToBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (_scrollController.hasClients) {
          final target = _scrollController.position.maxScrollExtent;
          // Use jumpTo during streaming to reduce jank.
          if (_isStreaming) {
            _scrollController.jumpTo(target);
          } else {
            _scrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        }
      } catch (_) {
        // Ignore (e.g. controller disposed/replaced while minimizing).
      }
    });
  }

  Widget _buildHistoryDrawer(BuildContext context) {
    final historyState = ref.watch(aiHistoryProvider);
    final reading = ref.watch(currentReadingProvider);
    final currentBookId = reading.isReading ? reading.book?.id : null;
    final selectedScope = currentBookId == null
        ? AiHistoryScope.all
        : _historyScopeBookId == currentBookId
            ? _historyScope
            : AiHistoryScope.currentBook;
    return Container(
      color: ClaudePalette.bg(context),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      L10n.of(context).conversationHistory,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: ClaudePalette.fg(context),
                      ),
                    ),
                  ),
                  DeleteConfirm(
                    delete: () => _confirmClearHistory(context),
                    deleteIcon: Icon(
                      Icons.delete_sweep_outlined,
                      size: 22,
                      color: ClaudePalette.secondary(context),
                    ),
                  ),
                ],
              ),
            ),
            if (currentBookId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: AnxSegmentedButton<AiHistoryScope>(
                    selected: {selectedScope},
                    showSelectedIcon: false,
                    segments: [
                      SegmentButtonItem(
                        value: AiHistoryScope.currentBook,
                        label: _currentBookScopeLabel(context),
                        icon: const Icon(Icons.menu_book_outlined),
                      ),
                      SegmentButtonItem(
                        value: AiHistoryScope.all,
                        label: L10n.of(context).settingsShareInboxFilterAll,
                        icon: const Icon(Icons.forum_outlined),
                      ),
                    ],
                    onSelectionChanged: (selection) {
                      final next = selection.isEmpty ? null : selection.first;
                      if (next == null) return;
                      setState(() {
                        _historyScopeBookId = currentBookId;
                        _historyScope = next;
                      });
                    },
                  ),
                ),
              ),
            Expanded(
              child: historyState.when(
                data: (items) {
                  final scopedItems = filterAiHistoryForBook(
                    items,
                    currentBookId: currentBookId,
                    scope: selectedScope,
                  );
                  if (scopedItems.isEmpty) {
                    return Center(
                      child: Text(
                        L10n.of(context).noConversationTip,
                        style: TextStyle(
                          fontSize: 13,
                          color: ClaudePalette.secondary(context),
                        ),
                      ),
                    );
                  }
                  final currentSessionId =
                      ref.watch(aiChatProvider.notifier).currentSessionId;
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: scopedItems.length,
                    separatorBuilder: (_, __) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: ClaudePalette.divider(context),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final entry = scopedItems[index];
                      return _buildHistoryTile(
                        context,
                        entry,
                        isSelected: entry.id == currentSessionId,
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Text(
                    L10n.of(context).failedToLoadHistoryTip,
                    style: TextStyle(
                      fontSize: 13,
                      color: ClaudePalette.secondary(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _currentBookScopeLabel(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode == 'zh' ? '当前书' : 'Current book';
  }

  Widget _buildHistoryTile(
    BuildContext context,
    AiChatHistoryEntry entry, {
    bool isSelected = false,
  }) {
    final provider = _providerByIdFromPrefs(entry.serviceId) ??
        _providerById(entry.serviceId);
    final title = _deriveTitle(entry);
    final subtitle = _buildHistorySubtitle(provider, entry);

    return Dismissible(
      key: ValueKey('history-${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: ClaudePalette.accent(context),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
          size: 22,
        ),
      ),
      confirmDismiss: (_) async {
        await _confirmDeleteHistory(context, entry);
        return true;
      },
      child: Material(
        color:
            isSelected ? ClaudePalette.accentTint(context) : Colors.transparent,
        child: InkWell(
          onTap: () => _handleHistoryTap(context, entry),
          onLongPress: () => _renameHistoryEntry(context, entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ClaudePalette.fg(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: ClaudePalette.secondary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(entry.updatedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: ClaudePalette.tertiary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildHistorySubtitle(
    AiProviderMeta? provider,
    AiChatHistoryEntry entry,
  ) {
    final serviceLabel = provider?.name ?? entry.serviceId;
    if (entry.model.isEmpty) {
      return serviceLabel;
    }
    return '$serviceLabel · ${entry.model}';
  }

  AiProviderMeta? _providerByIdFromPrefs(String id) {
    return Prefs().getAiProviderMeta(id);
  }

  String _deriveTitle(AiChatHistoryEntry entry) {
    final stored = (entry.title ?? '').trim();
    if (stored.isNotEmpty) {
      return stored;
    }
    for (final message in entry.messages) {
      if (message is AIChatMessage) {
        final content = message.contentAsString.trim();
        if (content.isNotEmpty) {
          final firstLine = content.split('\n').first.trim();
          return firstLine;
        }
      }
    }
    if (entry.messages.isNotEmpty) {
      return 'Conversation';
    }
    return 'Empty conversation';
  }

  String _formatTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final date =
        '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)}';
    final time = '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
    return '$date $time';
  }

  Future<void> _handleHistoryTap(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    if (_isStreaming) {
      unawaited(ref.read(aiChatProvider.notifier).cancelStreaming());
    }

    ref.read(aiChatProvider.notifier).loadHistoryEntry(entry);
    if (mounted) {
      setState(() {
        _selectedProviderId = entry.serviceId;
        _sourceRefByUserIndex.clear();
        _draftSourceRef = null;
        _draftSourceRefSeedText = null;
      });
    }

    Navigator.of(context).pop();
    _pinnedToBottom = true;
    _scrollToBottom(force: true);
  }

  Future<void> _renameHistoryEntry(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    final controller = TextEditingController(text: _deriveTitle(entry));
    final renamed = await PTDialog.show<String>(
      context,
      title: 'Rename conversation',
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Title',
        ),
      ),
      actions: [
        PTDialogAction(
          label: L10n.of(context).commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        PTDialogAction(
          label: L10n.of(context).commonSave,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        ),
      ],
    );

    final nextTitle = (renamed ?? '').trim();
    if (nextTitle.isEmpty) {
      return;
    }

    final updated = entry.copyWith(
      title: nextTitle,
      titleSource: 'manual',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(aiHistoryProvider.notifier).upsert(updated);
  }

  Future<void> _confirmDeleteHistory(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    await ref.read(aiHistoryProvider.notifier).remove(entry.id);

    final currentSessionId = ref.read(aiChatProvider.notifier).currentSessionId;
    if (currentSessionId == entry.id) {
      ref.read(aiChatProvider.notifier).clear();
    }
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    await ref.read(aiHistoryProvider.notifier).clear();
    ref.read(aiChatProvider.notifier).clear();
    if (mounted) {
      setState(() {
        _sourceRefByUserIndex.clear();
        _draftSourceRef = null;
        _draftSourceRefSeedText = null;
      });
    }
  }

  // Streaming lifecycle is managed by [aiChatProvider] so UI minimize/close
  // does not interrupt generation.

  void sendCurrentDraft() {
    _sendMessage();
  }

  void _sendMessage() {
    if (_isStreaming) {
      return;
    }

    final message = inputController.text.trim();
    if (message.isEmpty && _attachments.isEmpty) return;
    final draftSourceRef = _sourceRefForCurrentDraft(message);

    inputController.clear();
    _draftSourceRef = null;
    _draftSourceRefSeedText = null;

    final attachments =
        _attachments.isEmpty ? null : List<AttachmentItem>.from(_attachments);
    if (_attachments.isNotEmpty) {
      setState(() {
        _attachments.clear();
      });
    }

    _pinnedToBottom = true;
    ref.read(aiChatProvider.notifier).startStreaming(
          message,
          false,
          attachments: attachments,
          userSourceRef: draftSourceRef,
        );
    if (draftSourceRef != null) {
      final messages =
          ref.read(aiChatProvider).asData?.value ?? const <ChatMessage>[];
      final userIndex = _findLastHumanIndex(messages);
      if (userIndex != null) {
        _sourceRefByUserIndex[userIndex] = draftSourceRef;
      }
    }
    _scrollToBottom(force: true);
  }

  SourceRef? _sourceRefForCurrentDraft(String message) {
    final sourceRef = _draftSourceRef;
    if (sourceRef == null) return null;

    final current = _normalizeDraftSourceMatchText(message);
    if (current.isEmpty) return null;

    final seed = _normalizeDraftSourceMatchText(
      _draftSourceRefSeedText ?? sourceRef.sourceTextSnippet ?? '',
    );
    final snippet = _normalizeDraftSourceMatchText(
      sourceRef.sourceTextSnippet ?? '',
    );

    if (_containsSourceText(current, seed) ||
        _containsSourceText(current, snippet)) {
      return sourceRef;
    }
    return null;
  }

  bool _containsSourceText(String current, String sourceText) {
    if (sourceText.isEmpty) return false;
    if (current == sourceText) return true;
    if (sourceText.length < 12) return false;
    return current.contains(sourceText);
  }

  String _normalizeDraftSourceMatchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  void _regenerateFromUserIndex(int userIndex) {
    if (_isStreaming) {
      return;
    }

    _pinnedToBottom = true;
    ref.read(aiChatProvider.notifier).startStreaming(
          '',
          true,
          regenerateFromUserIndex: userIndex,
        );
    _scrollToBottom(force: true);
  }

  void _editUserMessageAndRegenerate(
    int userIndex,
    String newText, {
    List<AttachmentItem>? attachments,
  }) {
    if (_isStreaming) {
      return;
    }

    _pinnedToBottom = true;
    ref.read(aiChatProvider.notifier).startStreaming(
          newText,
          true,
          regenerateFromUserIndex: userIndex,
          replaceUserMessage: true,
          attachments: attachments,
        );
    _scrollToBottom(force: true);
  }

  void _copyPlainText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AnxToast.show(L10n.of(context).notesPageCopied);
  }

  Future<void> _confirmRegenerateFromUserIndex(
    int userIndex, {
    required bool isLastTurn,
  }) async {
    if (_isStreaming) {
      return;
    }

    if (!isLastTurn) {
      final confirmed = await PTDialog.show<bool>(
        context,
        title: L10n.of(context).aiChatRegenerateFromHereConfirmTitle,
        message: L10n.of(context).aiChatRegenerateFromHereConfirmBody,
        actions: [
          PTDialogAction(
            label: L10n.of(context).commonCancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          PTDialogAction(
            label: L10n.of(context).commonConfirm,
            isDefault: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
      if (confirmed != true) {
        return;
      }
    }

    _regenerateFromUserIndex(userIndex);
  }

  Future<void> _showEditUserMessageDialog(
    int userIndex,
    HumanChatMessage message,
  ) async {
    if (_isStreaming) {
      return;
    }

    final controller = TextEditingController(
      text: _extractUserTextFromHuman(message),
    );
    final editableAttachments =
        _extractAttachmentItemsFromHuman(message).toList(growable: true);
    try {
      final edited = await PTDialog.show<_EditUserMessageResult>(
        context,
        title: L10n.of(context).aiChatEditUserMessageTitle,
        content: SizedBox(
          width: 520,
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      maxLength: 20000,
                      maxLines: 6,
                      minLines: 1,
                      autofocus: true,
                    ),
                    if (editableAttachments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '附件 ${editableAttachments.length}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < editableAttachments.length; i++)
                            _buildEditableAttachmentChip(
                              editableAttachments[i],
                              onRemove: () {
                                setStateDialog(() {
                                  editableAttachments.removeAt(i);
                                });
                              },
                              onPreview: editableAttachments[i].type ==
                                      AttachmentType.image
                                  ? () {
                                      final imageIndexes = <int>[];
                                      for (var j = 0;
                                          j < editableAttachments.length;
                                          j++) {
                                        if (editableAttachments[j].type ==
                                            AttachmentType.image) {
                                          imageIndexes.add(j);
                                        }
                                      }
                                      final initialImageIndex =
                                          imageIndexes.indexOf(i);
                                      final images = editableAttachments
                                          .where((a) =>
                                              a.type == AttachmentType.image)
                                          .map((a) => a.bytes)
                                          .toList(growable: false);
                                      _showImageGallery(
                                        images,
                                        initialIndex: initialImageIndex < 0
                                            ? 0
                                            : initialImageIndex,
                                      );
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          PTDialogAction(
            label: L10n.of(context).commonCancel,
            onPressed: () => Navigator.of(context).pop(),
          ),
          PTDialogAction(
            label: L10n.of(context).commonSave,
            isDefault: true,
            onPressed: () {
              Navigator.of(context).pop(
                _EditUserMessageResult(
                  text: controller.text.trim(),
                  attachments: List<AttachmentItem>.from(editableAttachments),
                ),
              );
            },
          ),
        ],
      );

      if (edited == null) {
        return;
      }

      final confirmed = await PTDialog.show<bool>(
        context,
        title: L10n.of(context).aiChatRegenerateFromHereConfirmTitle,
        message: L10n.of(context).aiChatRegenerateFromHereConfirmBody,
        actions: [
          PTDialogAction(
            label: L10n.of(context).commonCancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          PTDialogAction(
            label: L10n.of(context).commonConfirm,
            isDefault: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );

      if (confirmed != true) {
        return;
      }

      _editUserMessageAndRegenerate(
        userIndex,
        edited.text,
        attachments: edited.attachments,
      );
    } finally {
      controller.dispose();
    }
  }

  void _useQuickPrompt(String prompt) {
    inputController.text = '$prompt ${inputController.text}';
    _sendMessage();
  }

  // Wave L: default icon mapping for the quick-suggestion chip strip. The
  // existing quick prompt bank is string-only, so we pick a reasonable glyph
  // by index and fall back to a lightbulb for custom user-defined prompts.
  static const List<IconData> _quickSuggestionIcons = [
    Icons.auto_awesome_outlined,
    Icons.psychology_outlined,
    Icons.summarize_outlined,
    Icons.insights_outlined,
    Icons.lightbulb_outline,
    Icons.translate_outlined,
    Icons.style_outlined,
    Icons.help_outline,
  ];

  // Wave S: detect whether the composer is attached to a reading surface so
  // we can render a small mode label inside the pill. We use the chat context
  // notice as a cheap proxy — when the user is reading a book the AI chat
  // surface publishes a notice, otherwise we fall back to "Chat".
  Widget _buildQuickSuggestions(List<Map<String, String>> quickPrompts) {
    if (quickPrompts.isEmpty) {
      return const SizedBox.shrink();
    }
    // Wave S: ghost-pill chips — lighter background, tighter padding, and
    // secondary text/icon color so they read as context suggestions rather
    // than primary CTAs.
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: quickPrompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final prompt = quickPrompts[index];
          final icon =
              _quickSuggestionIcons[index % _quickSuggestionIcons.length];
          return Material(
            color: Colors.transparent,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () {
                HapticFeedback.selectionClick();
                _useQuickPrompt(prompt['prompt']!);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: ClaudePalette.bg(context).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ClaudePalette.divider(context),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: ClaudePalette.secondary(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      prompt['label'] ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: ClaudePalette.secondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _clearMessage() {
    if (_isStreaming) {
      return;
    }

    unawaited(_endCurrentSession());
  }

  Future<void> _showAttachmentPicker() async {
    if (_isStreaming) return;

    await PTBottomSheet.show<void>(
      context,
      builder: (ctx) {
        return AttachmentPickerDialog(
          onPicked: (items) {
            _addAttachments(items);
          },
        );
      },
    );
  }

  // Local-only state for toggles surfaced in the Add-to-Chat sheet but not
  // yet wired to a backend. Persistence is intentionally out of scope for
  // this wave (UI only).
  bool _webSearchEnabled = false;

  Future<void> _showAddToChatSheet(BuildContext context) async {
    if (_isStreaming) return;
    final l10n = L10n.of(context);
    final activeSkill = AiSkillRegistry.byId(Prefs().activeAiSkillId);

    Widget bigCard({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: ClaudePalette.elevated(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: ClaudePalette.divider(context),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 26, color: ClaudePalette.accent(context)),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ClaudePalette.fg(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget toggleRow({
      required IconData icon,
      required String title,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ClaudePalette.secondary(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  color: ClaudePalette.fg(context),
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: ClaudePalette.accent(context),
            ),
          ],
        ),
      );
    }

    Widget navRow({
      required IconData icon,
      required String title,
      String? trailingValue,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: ClaudePalette.secondary(context)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      color: ClaudePalette.fg(context),
                    ),
                  ),
                ),
                if (trailingValue != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      trailingValue,
                      style: TextStyle(
                        fontSize: 13,
                        color: ClaudePalette.tertiary(context),
                      ),
                    ),
                  ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: ClaudePalette.tertiary(context)),
              ],
            ),
          ),
        ),
      );
    }

    Widget seminarFeatureCard(BuildContext sheetContext) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(sheetContext).pop();
            _openSeminarRuntimeFromChat();
          },
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.22),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.groups_2_outlined,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.aiChatSeminarFeatureTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ClaudePalette.fg(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.aiChatSeminarFeatureDesc,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: ClaudePalette.secondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('ai-chat-seminar-run-setup'),
                      tooltip: _skillSettingsText(
                        zh: '本次研讨设置',
                        en: 'Run setup',
                      ),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.tune_outlined, size: 18),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_showSeminarRunSetupSheet());
                      },
                    ),
                    Text(
                      l10n.aiChatSeminarFeatureAction,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    await PTBottomSheet.show<void>(
      context,
      title: l10n.aiChatAddToChatTitle,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final provider = _currentProvider;
            final thinkingMode = _thinkingModeForProvider(provider.id);
            final thinkingOn = thinkingMode != AiThinkingMode.off;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      bigCard(
                        icon: Icons.photo_camera_outlined,
                        label: l10n.aiChatAttachCamera,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showAttachmentPicker();
                        },
                      ),
                      const SizedBox(width: 10),
                      bigCard(
                        icon: Icons.photo_library_outlined,
                        label: l10n.aiChatAttachPhotos,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showAttachmentPicker();
                        },
                      ),
                      const SizedBox(width: 10),
                      bigCard(
                        icon: Icons.folder_outlined,
                        label: l10n.aiChatAttachFiles,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showAttachmentPicker();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: ClaudePalette.divider(context)),
                  const SizedBox(height: 6),
                  toggleRow(
                    icon: Icons.travel_explore_outlined,
                    title: l10n.aiChatWebSearch,
                    value: _webSearchEnabled,
                    onChanged: (v) {
                      setLocalState(() => _webSearchEnabled = v);
                      setState(() {});
                    },
                  ),
                  toggleRow(
                    icon: Icons.psychology_outlined,
                    title: l10n.aiChatExtendedThinking,
                    value: thinkingOn,
                    onChanged: (v) {
                      final next = Map<String, String>.from(
                        Prefs().getAiConfig(provider.id),
                      );
                      next['thinking_mode'] = aiThinkingModeToString(
                        v ? AiThinkingMode.high : AiThinkingMode.off,
                      );
                      Prefs().saveAiConfig(provider.id, next);
                      setLocalState(() {});
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: ClaudePalette.divider(context)),
                  const SizedBox(height: 6),
                  seminarFeatureCard(ctx),
                  const SizedBox(height: 6),
                  navRow(
                    icon: Icons.style_outlined,
                    title: l10n.aiChatChooseStyle,
                    trailingValue: activeSkill == null
                        ? l10n.aiSkillNone
                        : _localizedSkillName(context, activeSkill),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showSkillPickerSheet();
                    },
                  ),
                  navRow(
                    icon: Icons.tune,
                    title: l10n.aiChatEditModelTitle,
                    trailingValue: _modelLabel(_selectedProviderId),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _editCurrentModel();
                    },
                  ),
                  navRow(
                    icon: Icons.psychology_alt_outlined,
                    title: l10n.aiThinkingTitle,
                    trailingValue: _thinkingModeLabel(thinkingMode, l10n),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _editThinkingMode();
                    },
                  ),
                  navRow(
                    icon: Icons.folder_special_outlined,
                    title: l10n.aiChatAddToProject,
                    onTap: () {
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showSkillPickerSheet() async {
    final l10n = L10n.of(context);
    final activeId = Prefs().activeAiSkillId;
    await PTBottomSheet.show<void>(
      context,
      title: l10n.aiChatChooseStyle,
      builder: (ctx) {
        final skills = AiSkillRegistry.allSkills();
        return ListView(
          shrinkWrap: true,
          children: [
            PTPickerRow<String>(
              value: '',
              groupValue: activeId ?? '',
              title: l10n.aiSkillNone,
              leading: Icons.block,
              onChanged: (_) {
                Prefs().activeAiSkillId = null;
                setState(() {});
                Navigator.of(ctx).pop();
              },
            ),
            for (final skill in skills)
              if (skill.id == 'seminar_mode')
                _ConfigurableSkillPickerRow(
                  selected: activeId == skill.id,
                  title: _localizedSkillName(context, skill),
                  subtitle: _localizedSkillDesc(context, skill),
                  icon: Icons.groups_2_outlined,
                  configLabel: l10n.seminarConfigTitle,
                  onSelect: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      CupertinoStyleRoute(
                        page: const AiSeminarConfigPage(),
                      ),
                    );
                  },
                  onConfigure: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      CupertinoStyleRoute(
                        page: const AiSeminarConfigPage(),
                      ),
                    );
                  },
                )
              else if (!skill.isBuiltIn)
                _ConfigurableSkillPickerRow(
                  selected: activeId == skill.id,
                  title: _localizedSkillName(context, skill),
                  subtitle: _localizedSkillDesc(context, skill),
                  icon: Icons.extension_outlined,
                  configLabel: l10n.settingsAiCustomSkillsTitle,
                  onSelect: () {
                    Prefs().activeAiSkillId = skill.id;
                    setState(() {});
                    Navigator.of(ctx).pop();
                  },
                  onConfigure: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      CupertinoStyleRoute(
                        page: const CustomSkillsPage(),
                      ),
                    );
                  },
                )
              else
                _ConfigurableSkillPickerRow(
                  selected: activeId == skill.id,
                  title: _localizedSkillName(context, skill),
                  subtitle: _localizedSkillDesc(context, skill),
                  icon: Icons.auto_fix_high,
                  configLabel: _skillSettingsText(
                    zh: '技能设置',
                    en: 'Skill settings',
                  ),
                  onSelect: () {
                    Prefs().activeAiSkillId = skill.id;
                    setState(() {});
                    Navigator.of(ctx).pop();
                  },
                  onConfigure: () {
                    Navigator.of(ctx).pop();
                    unawaited(_showBuiltInSkillPromptSettings(skill));
                  },
                ),
          ],
        );
      },
    );
  }

  Future<void> _showBuiltInSkillPromptSettings(AiSkill skill) async {
    final l10n = L10n.of(context);
    await PTBottomSheet.show<void>(
      context,
      title: _skillSettingsTitle(skill),
      builder: (ctx) {
        return _BuiltInSkillPromptSettingsSheet(
          initialPrompt: Prefs().aiSkillCustomPromptFor(skill.id) ?? '',
          description: _skillSettingsText(
            zh: '这里的内容会附加到该风格的系统提示词里。它只影响新的 AI 请求，不会改变已有历史消息。',
            en: 'These instructions are appended to this style prompt. They affect new AI requests only and do not rewrite chat history.',
          ),
          label: _skillSettingsText(
            zh: '自定义附加提示词',
            en: 'Custom prompt add-on',
          ),
          hint: _skillSettingsText(
            zh: '例如：回答时先列出证据，再给出结论。',
            en: 'Example: list the evidence first, then state the conclusion.',
          ),
          clearLabel: _skillSettingsText(zh: '清除', en: 'Clear'),
          cancelLabel: l10n.commonCancel,
          saveLabel: l10n.commonSave,
          onClear: () {
            Prefs().setAiSkillCustomPrompt(skill.id, null);
            if (mounted) setState(() {});
            Navigator.of(ctx).pop();
            _showToastIfAvailable(l10n.commonSaved);
          },
          onSave: (value) {
            Prefs().setAiSkillCustomPrompt(skill.id, value);
            if (mounted) setState(() {});
            Navigator.of(ctx).pop();
            _showToastIfAvailable(l10n.commonSaved);
          },
        );
      },
    );
  }

  String _skillSettingsTitle(AiSkill skill) {
    final skillName = _localizedSkillName(context, skill);
    return _skillSettingsText(
      zh: '$skillName设置',
      en: '$skillName settings',
    );
  }

  String _skillSettingsText({
    required String zh,
    required String en,
  }) {
    return _isChineseLocale ? zh : en;
  }

  void _showToastIfAvailable(String message) {
    if (navigatorKey.currentContext == null) return;
    AnxToast.show(message);
  }

  Future<void> _showSeminarRunSetupSheet() async {
    final l10n = L10n.of(context);
    await PTBottomSheet.show<void>(
      context,
      title: _skillSettingsText(
        zh: '本次研讨设置',
        en: 'Run Seminar setup',
      ),
      builder: (ctx) {
        return _SeminarRunSetupSheet(
          initialQuestion: inputController.text.trim(),
          cancelLabel: l10n.commonCancel,
          startLabel: l10n.seminarStart,
          onStart: (question, config) {
            Navigator.of(ctx).pop();
            _openSeminarRuntimeFromChat(
              overrideQuestion: question,
              runConfig: config,
            );
          },
        );
      },
    );
  }

  void _openSeminarRuntimeFromChat({
    String? overrideQuestion,
    _SeminarRunConfig? runConfig,
  }) {
    if (!mounted) return;
    final reading = ref.read(currentReadingProvider);
    final question = (overrideQuestion ?? inputController.text).trim();
    final sourceRef = _draftSourceRefSeedText == inputController.text
        ? _draftSourceRef
        : null;
    final seminarSessionId = _newSeminarChatSessionId();
    unawaited(
      ref.read(aiChatProvider.notifier).appendSeminarRunCard(
            question: question,
            bookId: reading.book?.id,
            sourceRef: sourceRef,
            seminarSessionId: seminarSessionId,
            includeVerifier: runConfig?.includeVerifier,
            maxRounds: runConfig?.maxRounds,
            roleProfiles: runConfig?.roleProfiles,
          ),
    );
    _suppressDraftSync = true;
    inputController.clear();
    _suppressDraftSync = false;
    try {
      ref.read(aiChatDraftInputProvider.notifier).set('');
    } catch (_) {}

    setState(() {
      _inlineSeminarVisible = true;
      _inlineSeminarQuestion = question.isEmpty ? null : question;
      _inlineSeminarSessionId = seminarSessionId;
      _inlineSeminarBookId = reading.book?.id;
      _inlineSeminarSourceRef = sourceRef;
      _inlineSeminarRoleProfiles = runConfig?.roleProfiles;
      _inlineSeminarMaxRounds = runConfig?.maxRounds;
      _inlineSeminarIncludeVerifier = runConfig?.includeVerifier;
      _lastSeminarCardSignatures.remove(seminarSessionId);
    });
  }

  void openInlineSeminar({
    String? question,
    String? sessionId,
    int? bookId,
    SourceRef? sourceRef,
    List<AiSeminarRoleProfile>? roleProfiles,
    int? maxRounds,
    bool? includeVerifier,
    bool persistRunCard = false,
  }) {
    if (!mounted) return;
    final reading = ref.read(currentReadingProvider);
    final trimmedQuestion = question?.trim();
    final normalizedSessionId = sessionId?.trim();
    final resolvedSessionId =
        normalizedSessionId == null || normalizedSessionId.isEmpty
            ? _newSeminarChatSessionId()
            : normalizedSessionId;
    if (persistRunCard) {
      unawaited(
        ref.read(aiChatProvider.notifier).appendSeminarRunCard(
              question: trimmedQuestion ?? '',
              bookId: sourceRef?.bookId ?? bookId ?? reading.book?.id,
              sourceRef: sourceRef,
              seminarSessionId: resolvedSessionId,
              includeVerifier: includeVerifier,
              maxRounds: maxRounds,
              roleProfiles: roleProfiles,
            ),
      );
    }
    setState(() {
      _inlineSeminarVisible = true;
      _inlineSeminarQuestion =
          trimmedQuestion == null || trimmedQuestion.isEmpty
              ? null
              : trimmedQuestion;
      _inlineSeminarSessionId = resolvedSessionId;
      _inlineSeminarBookId = sourceRef?.bookId ?? bookId ?? reading.book?.id;
      _inlineSeminarSourceRef = sourceRef;
      _inlineSeminarRoleProfiles = roleProfiles;
      _inlineSeminarMaxRounds = maxRounds;
      _inlineSeminarIncludeVerifier = includeVerifier;
      _lastSeminarCardSignatures.remove(resolvedSessionId);
    });
  }

  void _syncInlineSeminarRunCard(AiSeminarRuntimeState state) {
    _syncSeminarRunCardSnapshot(_inlineSeminarSessionId, state);
  }

  void _syncSeminarRunCardSnapshot(
    String? rawSessionId,
    AiSeminarRuntimeState state,
  ) {
    final sessionId = rawSessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return;
    final runtimeSession = state.session;
    if (runtimeSession == null || runtimeSession.id != sessionId) return;

    final citedEvidence = _seminarCitedTraceableEvidenceFromState(state);
    final snapshot = _seminarRunCardSnapshotFromState(
      state,
      citedEvidence: citedEvidence,
    );
    final sourceRefCount = citedEvidence.length;
    final signature = jsonEncode({
      'sessionId': sessionId,
      'status': state.status.asString,
      'sourceRefCount': sourceRefCount,
      'snapshot': snapshot?.toJson(),
    });
    if (signature == _lastSeminarCardSignatures[sessionId]) return;
    _lastSeminarCardSignatures[sessionId] = signature;
    unawaited(
      Future<bool>.microtask(() {
        if (!mounted) return false;
        return ref.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
              seminarSessionId: sessionId,
              status: state.status.asString,
              sourceRefCount: sourceRefCount,
              snapshot: snapshot,
            );
      }),
    );
  }

  AiSeminarRunCardSnapshot? _seminarRunCardSnapshotFromState(
    AiSeminarRuntimeState state, {
    required List<AiSeminarEvidence> citedEvidence,
  }) {
    final evidence = citedEvidence
        .take(3)
        .map(
          (item) => AiSeminarRunCardEvidenceSnapshot(
            id: item.id,
            title: _seminarEvidenceSnapshotTitle(item),
            snippet: _seminarEvidenceSnapshotSnippet(item),
            sourceRef: item.sourceRef,
          ),
        )
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    final evidenceById = <String, AiSeminarEvidence>{
      for (final item in citedEvidence)
        if (item.id.trim().isNotEmpty) item.id.trim(): item,
    };
    final roleSummaries = state.turns
        .where((turn) => !turn.isFailed && turn.responseText.trim().isNotEmpty)
        .take(4)
        .map(
          (turn) => AiSeminarRunCardRoleSummary(
            roleId: turn.role.asString,
            label: _seminarRoleFallbackLabel(turn.role.asString),
            summary: turn.responseText.trim(),
            evidenceRefs: turn.evidenceRefIds
                .map((id) => evidenceById[id.trim()])
                .whereType<AiSeminarEvidence>()
                .map(
                  (item) => AiSeminarRunCardEvidenceSnapshot(
                    id: item.id,
                    title: _seminarEvidenceSnapshotTitle(item),
                    snippet: _seminarEvidenceSnapshotSnippet(item),
                    sourceRef: item.sourceRef,
                  ),
                )
                .where((item) => !item.isEmpty)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    final synthesis = state.synthesis;
    final disagreementDetails = _seminarDisagreementDetailsFromState(
      state,
      evidenceById,
    );
    final snapshot = AiSeminarRunCardSnapshot(
      evidence: evidence,
      roleSummaries: roleSummaries,
      synthesisSummary: synthesis?.summary.trim(),
      disagreements: synthesis?.disagreements ?? const <String>[],
      disagreementDetails: disagreementDetails,
      openQuestions: synthesis?.openQuestions ?? const <String>[],
    );
    return snapshot.isEmpty ? null : snapshot;
  }

  List<AiSeminarRunCardDisagreementDetail> _seminarDisagreementDetailsFromState(
    AiSeminarRuntimeState state,
    Map<String, AiSeminarEvidence> evidenceById,
  ) {
    final entries = <AiSeminarWhiteboardEntry>[];
    final seen = <String>{};

    void addEntry(AiSeminarWhiteboardEntry entry) {
      if (entry.kind != AiSeminarWhiteboardKind.disagreement) return;
      final id = entry.id.trim();
      final text = entry.text.trim();
      final key = id.isNotEmpty ? id : text;
      if (key.isEmpty || !seen.add(key)) return;
      entries.add(entry);
    }

    for (final turn in state.turns) {
      if (turn.isFailed) continue;
      for (final entry in turn.whiteboardEntries) {
        addEntry(entry);
      }
    }
    for (final entry in state.whiteboardEntries) {
      addEntry(entry);
    }

    return entries
        .take(4)
        .map(
          (entry) => AiSeminarRunCardDisagreementDetail(
            text: entry.text,
            roleIds: _seminarDisagreementRoleIds(entry, state.turns),
            evidenceRefs: entry.evidenceRefIds
                .map((id) => evidenceById[id.trim()])
                .whereType<AiSeminarEvidence>()
                .map(
                  (item) => AiSeminarRunCardEvidenceSnapshot(
                    id: item.id,
                    title: _seminarEvidenceSnapshotTitle(item),
                    snippet: _seminarEvidenceSnapshotSnippet(item),
                    sourceRef: item.sourceRef,
                  ),
                )
                .where((item) => !item.isEmpty)
                .toList(growable: false),
          ),
        )
        .where((detail) => !detail.isEmpty)
        .toList(growable: false);
  }

  List<String> _seminarDisagreementRoleIds(
    AiSeminarWhiteboardEntry entry,
    List<AiSeminarRoleTurn> turns,
  ) {
    final out = <String>[];
    void addRole(AiSeminarRole? role) {
      final roleId = role?.asString.trim();
      if (roleId == null || roleId.isEmpty || out.contains(roleId)) return;
      out.add(roleId);
    }

    addRole(entry.role);
    for (final turn in turns) {
      if (turn.isFailed) continue;
      final hasEntry = turn.whiteboardEntries.any((item) {
        final itemId = item.id.trim();
        final entryId = entry.id.trim();
        if (itemId.isNotEmpty && entryId.isNotEmpty && itemId == entryId) {
          return true;
        }
        return item.text.trim().isNotEmpty &&
            item.text.trim() == entry.text.trim();
      });
      if (hasEntry) addRole(turn.role);
    }
    return out;
  }

  List<AiSeminarEvidence> _seminarCitedTraceableEvidenceFromState(
    AiSeminarRuntimeState state,
  ) {
    final rawEvidence = state.synthesis?.evidence.isNotEmpty == true
        ? state.synthesis!.evidence
        : state.evidenceBundle?.evidence ?? const <AiSeminarEvidence>[];
    final traceableById = <String, AiSeminarEvidence>{};
    for (final item in rawEvidence) {
      final id = item.id.trim();
      if (id.isEmpty || !item.isTraceable) continue;
      traceableById.putIfAbsent(id, () => item);
    }
    if (traceableById.isEmpty) return const <AiSeminarEvidence>[];

    final citedIds = <String>[];
    final seen = <String>{};
    void addRefs(Iterable<String> refs) {
      for (final raw in refs) {
        final id = raw.trim();
        if (id.isEmpty || !traceableById.containsKey(id)) continue;
        if (seen.add(id)) citedIds.add(id);
      }
    }

    final synthesis = state.synthesis;
    if (synthesis != null) {
      addRefs(synthesis.evidenceRefIds);
      for (final card in synthesis.candidateCards) {
        addRefs(card.evidenceRefIds);
      }
    }
    for (final turn in state.turns) {
      if (turn.isFailed) continue;
      addRefs(turn.evidenceRefIds);
      for (final entry in turn.whiteboardEntries) {
        addRefs(entry.evidenceRefIds);
      }
    }

    return citedIds.map((id) => traceableById[id]!).toList(growable: false);
  }

  String _seminarEvidenceSnapshotTitle(AiSeminarEvidence evidence) {
    final ref = evidence.sourceRef;
    final direct = ref.sourceTitle?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final location = ref.locationLabel?.trim();
    if (location != null && location.isNotEmpty) return location;
    final href = ref.href?.trim();
    if (href != null && href.isNotEmpty) return href;
    final chunkId = ref.chunkId;
    if (chunkId != null) return 'Chunk $chunkId';
    return _seminarEvidenceScopeLabel(
      evidence.scope.asString,
      L10n.of(context),
    );
  }

  String _seminarEvidenceSnapshotSnippet(AiSeminarEvidence evidence) {
    final sourceSnippet = evidence.sourceRef.sourceTextSnippet?.trim();
    if (sourceSnippet != null && sourceSnippet.isNotEmpty) {
      return sourceSnippet;
    }
    return evidence.text.trim();
  }

  Widget _buildInlineSeminarPanel() {
    final height =
        (MediaQuery.of(context).size.height * 0.52).clamp(320.0, 560.0);
    return SizedBox(
      height: height,
      child: AiSeminarRuntimePanel(
        key: ValueKey(
          [
            _inlineSeminarQuestion ?? '',
            _inlineSeminarSessionId ?? '',
            _inlineSeminarBookId?.toString() ?? '',
            _inlineSeminarSourceRef?.bookId?.toString() ?? '',
            _inlineSeminarSourceRef?.href ?? '',
            _inlineSeminarSourceRef?.cfi ?? '',
            _inlineSeminarSourceRef?.chunkId ?? '',
            _inlineSeminarMaxRounds?.toString() ?? '',
          ].join('\u001f'),
        ),
        initialQuestion: _inlineSeminarQuestion,
        initialSessionId: _inlineSeminarSessionId,
        bookId: _inlineSeminarBookId,
        initialSourceRef: _inlineSeminarSourceRef,
        initialRoleProfiles: _inlineSeminarRoleProfiles,
        initialMaxRounds: _inlineSeminarMaxRounds,
        initialIncludeVerifier: _inlineSeminarIncludeVerifier,
        embedded: true,
        onClose: () {
          if (!mounted) return;
          setState(() => _inlineSeminarVisible = false);
        },
        onOpenFullPage: _openInlineSeminarRuntimePage,
      ),
    );
  }

  void _openInlineSeminarRuntimePage() {
    if (!mounted) return;
    Navigator.of(context).push(
      CupertinoStyleRoute(
        page: AiSeminarRuntimePage(
          initialQuestion: _inlineSeminarQuestion,
          initialSessionId: _inlineSeminarSessionId,
          bookId: _inlineSeminarBookId,
          initialSourceRef: _inlineSeminarSourceRef,
          initialRoleProfiles: _inlineSeminarRoleProfiles,
          initialMaxRounds: _inlineSeminarMaxRounds,
          initialIncludeVerifier: _inlineSeminarIncludeVerifier,
        ),
      ),
    );
  }

  void prefillDraft({
    String? message,
    List<AttachmentItem>? attachments,
    bool replaceAttachments = false,
    SourceRef? sourceRef,
  }) {
    if (message != null) {
      _draftSourceRef = sourceRef;
      _draftSourceRefSeedText = sourceRef == null ? null : message;
      _suppressDraftSync = true;
      inputController.text = message;
      inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: inputController.text.length),
      );
      _suppressDraftSync = false;
      try {
        ref.read(aiChatDraftInputProvider.notifier).set(inputController.text);
      } catch (_) {}
    }

    if (attachments != null && attachments.isNotEmpty) {
      if (replaceAttachments) {
        setState(() {
          _attachments.clear();
        });
      }
      _addAttachments(attachments);
    }
  }

  void _addAttachments(List<AttachmentItem> items) {
    if (items.isEmpty) return;

    final maxImages = Prefs().aiChatImageAttachmentMaxCountV1;
    var imageCount =
        _attachments.where((a) => a.type == AttachmentType.image).length;

    final selectedImages =
        items.where((a) => a.type == AttachmentType.image).length;
    final accepted = <AttachmentItem>[];
    var acceptedImages = 0;
    var exceeded = false;

    for (final attachment in items) {
      if (attachment.type == AttachmentType.image) {
        if (imageCount >= maxImages) {
          exceeded = true;
          continue;
        }
        imageCount += 1;
        acceptedImages += 1;
      }
      accepted.add(attachment);
    }

    if (exceeded) {
      final code = Localizations.localeOf(context).languageCode.toLowerCase();
      final message = code.startsWith('zh')
          ? '本次选了 $selectedImages 张图片，已按上限保留前 $acceptedImages 张。'
          : 'Selected $selectedImages images, kept the first $acceptedImages within the limit.';
      AnxToast.show(message);
    }

    if (accepted.isEmpty) return;

    setState(() {
      _attachments.addAll(accepted);
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      if (index >= 0 && index < _attachments.length) {
        _attachments.removeAt(index);
      }
    });
  }

  void _clearAttachments() {
    setState(() {
      _attachments.clear();
    });
  }

  void _drainPendingShareBookImports() {
    final pending = pendingShareBookImportPaths.value;
    if (pending.isEmpty) return;

    // Clear first to avoid re-entrancy loops.
    pendingShareBookImportPaths.value = <String>[];

    final files = pending
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map((p) => File(p))
        .toList();

    _addBookImportFiles(files);
  }

  void _addBookImportFiles(List<File> files) {
    if (files.isEmpty) return;

    final existing = _pendingBookImports.map((e) => e.file.path).toSet();
    final next = <BookImportItem>[];

    for (final f in files) {
      final path = f.path.trim();
      if (path.isEmpty) continue;
      if (existing.contains(path)) continue;
      next.add(BookImportItem(file: f, filename: p.basename(path)));
    }

    if (next.isEmpty) return;

    setState(() {
      _pendingBookImports.addAll(next);
    });
  }

  Future<void> _removeBookImportAt(int index) async {
    if (index < 0 || index >= _pendingBookImports.length) return;
    final item = _pendingBookImports[index];

    setState(() {
      if (index < 0 || index >= _pendingBookImports.length) return;
      _pendingBookImports.removeAt(index);
    });

    // Cleanup-after-use: if the user dismisses the card, we can delete our
    // managed inbox copy.
    if (!Prefs().sharePanelCleanupAfterUseV1) return;

    final info = ShareInboxPaths.tryParse(item.file.path);
    if (info == null) return;

    try {
      final within = await ShareInboxPaths.isWithinInboxRoot(
          item.file.path, info.inboxRoot);
      if (!within) return;

      if (await item.file.exists()) {
        await item.file.delete();
      }

      await ShareInboxCleanupService.cleanupEventDirsIfSafe(
        eventDirs: [info.eventDir],
      );
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _importBookImportAt(int index) async {
    if (index < 0 || index >= _pendingBookImports.length) return;

    final item = _pendingBookImports[index];
    final files = await ShareSafeImport.prepareImportFiles([item.file.path]);
    if (files.isEmpty) return;

    importBookList(files, context, ref);

    setState(() {
      _pendingBookImports.removeWhere((e) => e.file.path == item.file.path);
    });

    if (Prefs().sharePanelCleanupAfterUseV1) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        ShareInboxCleanupService.cleanupEventDirsIfSafe(
          eventDirs: [item.file.path],
        );
      });
    }
  }

  void _regenerateLastMessage() {
    if (_isStreaming) {
      return;
    }
    final messages = ref.read(aiChatProvider).value;
    if (messages == null || messages.isEmpty) {
      return;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message is HumanChatMessage) {
        _regenerateFromUserIndex(i);
        break;
      }
    }
  }

  String _assistantMemoryText(String content) {
    final parsed = parseReasoningContent(content);
    return _buildCopyableText(parsed, content).trim();
  }

  Future<bool> _confirmLongTermWrite(String previewText) async {
    final prefs = Prefs();
    if (!prefs.memoryLongTermConfirmEnabled) {
      return true;
    }

    final l10n = L10n.of(context);
    final confirmed = await PTDialog.show<bool>(
      context,
      title: l10n.memoryLongTermConfirmDialogTitle,
      content: Text(
        l10n.memoryLongTermConfirmDialogBody(
          previewText.trim().replaceAll(RegExp(r'\s+'), ' '),
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: ClaudePalette.secondary(context),
          height: 1.35,
        ),
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PTDialogAction(
          label: l10n.commonConfirm,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    return confirmed == true;
  }

  Future<void> _endCurrentSession() async {
    if (_isStreaming) {
      return;
    }

    final messages =
        ref.read(aiChatProvider).asData?.value ?? const <ChatMessage>[];
    if (messages.isEmpty) {
      _clearCurrentConversationState();
      return;
    }

    final prefs = Prefs();
    final l10n = L10n.of(context);
    final dailyStrategy = prefs.memoryWorkflowDailyStrategy;
    final body = !prefs.memorySessionDigestEnabled
        ? l10n.aiChatEndSessionBodyNoDigest
        : switch (dailyStrategy) {
            MemoryWorkflowDailyStrategy.smartDaily =>
              l10n.aiChatEndSessionBodySmartDaily,
            MemoryWorkflowDailyStrategy.autoDaily =>
              l10n.aiChatEndSessionBodyAutoDaily,
            MemoryWorkflowDailyStrategy.reviewInbox =>
              l10n.aiChatEndSessionBodyReviewInbox,
          };
    final confirmed = await PTDialog.show<bool>(
      context,
      title: l10n.aiChatEndSessionTitle,
      message: body,
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PTDialogAction(
          label: l10n.aiChatEndSessionAction,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirmed != true) {
      return;
    }

    ref.read(aiChatProvider.notifier).persistCurrentConversation(ref);

    if (prefs.memorySessionDigestEnabled) {
      try {
        final result = await _memoryWorkflow.captureSessionDigest(
          messages: messages,
          dailyStrategy: dailyStrategy,
          conversationId: ref.read(aiChatProvider.notifier).currentSessionId,
        );
        if (!mounted) return;
        if (result.candidates.isEmpty) {
          AnxToast.show(l10n.memorySessionDigestNoCandidates);
        } else if (result.directSaveCount > 0 && result.reviewInboxCount > 0) {
          AnxToast.show(
            '${l10n.memorySessionDigestSavedToDaily(result.directSaveCount)}; '
            '${l10n.memorySessionDigestAddedToInbox(result.reviewInboxCount)}',
          );
        } else if (result.directSaveCount > 0) {
          AnxToast.show(
            l10n.memorySessionDigestSavedToDaily(result.directSaveCount),
          );
        } else {
          AnxToast.show(
            l10n.memorySessionDigestAddedToInbox(result.reviewInboxCount),
          );
        }
      } catch (e) {
        if (!mounted) return;
        AnxToast.show('${l10n.memoryWorkflowActionFailed}: $e');
        return;
      }
    }

    _clearCurrentConversationState();
  }

  void _clearCurrentConversationState() {
    ref.read(aiChatProvider.notifier).clear();
    setState(() {
      _sourceRefByUserIndex.clear();
      _draftSourceRef = null;
      _draftSourceRefSeedText = null;
      _suggestedPrompts = _pickSuggestedPrompts();
    });
  }

  Future<void> _handleMessageMemoryAction(
    _MessageMemoryAction action, {
    required String text,
    required String sourceType,
    String? messageNodeId,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      AnxToast.show(L10n.of(context).memoryWorkflowNothingToSave);
      return;
    }

    final l10n = L10n.of(context);
    final conversationId = ref.read(aiChatProvider.notifier).currentSessionId;
    final actionKey = _messageMemoryActionKey(
      sourceType: sourceType,
      messageNodeId: messageNodeId,
      text: normalized,
    );
    final sourcePointer = conversationId == null
        ? messageNodeId
        : messageNodeId == null
            ? conversationId
            : '$conversationId#$messageNodeId';
    final rawContextRef =
        conversationId == null ? null : 'conversation:$conversationId';

    try {
      switch (action) {
        case _MessageMemoryAction.rememberNow:
          final candidate = await _memoryWorkflow.saveToDaily(
            text: normalized,
            sourceType: sourceType,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            displayText: normalized,
            sourcePointer: sourcePointer,
            rawContextRef: rawContextRef,
            triggerKind: 'manual_save',
          );
          if (!mounted) return;
          setState(() {
            _directMemoryByMessageKey[actionKey] = candidate;
          });
          AnxToast.show(l10n.memorySavedToDaily);
          break;
        case _MessageMemoryAction.saveToLongTerm:
          final confirmed = await _confirmLongTermWrite(normalized);
          if (!confirmed) {
            return;
          }
          final candidate = await _memoryWorkflow.saveToLongTerm(
            text: normalized,
            sourceType: sourceType,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            displayText: normalized,
            sourcePointer: sourcePointer,
            rawContextRef: rawContextRef,
            triggerKind: 'manual_save',
          );
          if (!mounted) return;
          setState(() {
            _directMemoryByMessageKey[actionKey] = candidate;
          });
          AnxToast.show(l10n.memorySavedToLongTerm);
          break;
        case _MessageMemoryAction.addToReviewInbox:
          await _memoryWorkflow.addToReviewInbox(
            text: normalized,
            targetDoc: MemoryDocTarget.daily,
            sourceType: sourceType,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            displayText: normalized,
            sourcePointer: sourcePointer,
            rawContextRef: rawContextRef,
            triggerKind: 'manual_save',
          );
          if (!mounted) return;
          AnxToast.show(l10n.memoryAddedToReviewInbox);
          break;
        case _MessageMemoryAction.undoDirectSave:
          final candidate = _directMemoryByMessageKey[actionKey];
          if (candidate == null) {
            AnxToast.show(l10n.memoryWorkflowNothingToSave);
            return;
          }
          await _memoryWorkflow.undoDirectSave(candidate.id);
          if (!mounted) return;
          setState(() {
            _directMemoryByMessageKey.remove(actionKey);
          });
          AnxToast.show(l10n.memoryDirectSaveUndone);
          break;
      }
    } catch (e) {
      if (!mounted) return;
      AnxToast.show('${l10n.memoryWorkflowActionFailed}: $e');
    }
  }

  String _messageMemoryActionKey({
    required String sourceType,
    required String? messageNodeId,
    required String text,
  }) {
    final node = messageNodeId?.trim();
    if (node != null && node.isNotEmpty) {
      return '$sourceType#$node';
    }
    return '$sourceType#${text.hashCode}';
  }

  Future<void> _handleAssistantKnowledgeCardAction({
    required String answer,
    String? userPrompt,
    required String messageNodeId,
    SourceRef? readerSourceRef,
  }) async {
    final normalizedAnswer = answer.trim();
    if (normalizedAnswer.isEmpty) {
      AnxToast.show(L10n.of(context).knowledgeCardAddFailed);
      return;
    }

    final l10n = L10n.of(context);
    final chatNotifier = ref.read(aiChatProvider.notifier);
    final conversationId = chatNotifier.currentSessionId;
    chatNotifier.persistCurrentConversation(ref);
    final reading = ref.read(currentReadingProvider);
    final useCurrentReaderFallback = readerSourceRef == null &&
        !chatNotifier.isLoadedHistoryConversation &&
        _readingCanCreateReaderSourceRef(reading);
    final book = useCurrentReaderFallback ? reading.book : null;

    try {
      final result = await _chatKnowledgeCards.createFromAssistantAnswer(
        assistantAnswer: normalizedAnswer,
        userPrompt: userPrompt,
        conversationId: conversationId,
        messageNodeId: messageNodeId,
        modelId: _modelLabel(_selectedProviderId),
        bookId: book?.id,
        bookTitle: book?.title,
        cfi: useCurrentReaderFallback ? reading.cfi?.trim() : null,
        chapterTitle: useCurrentReaderFallback ? reading.chapterTitle : null,
        readerSourceRef: readerSourceRef,
      );
      if (!mounted) return;
      final message = result.addedToReviewInbox
          ? (result.inserted
              ? l10n.knowledgeCardAddedToReviewInbox
              : l10n.knowledgeCardAlreadyInReviewInbox)
          : result.inserted
              ? l10n.knowledgeCardSavedInline
              : result.card.reviewState == KnowledgeCardReviewState.pending
                  ? l10n.knowledgeCardAlreadyInReviewInbox
                  : l10n.knowledgeCardAlreadySaved;
      AnxToast.show(message);
    } catch (_) {
      if (!mounted) return;
      AnxToast.show(l10n.knowledgeCardAddFailed);
    }
  }

  SourceRef? _readerSourceRefForUserIndex(int userIndex) {
    return _sourceRefByUserIndex[userIndex] ??
        ref.read(aiChatProvider.notifier).sourceRefForMessageIndex(userIndex);
  }

  bool _readingCanCreateReaderSourceRef(CurrentReadingState reading) {
    final bookId = reading.book?.id;
    final cfi = reading.cfi?.trim() ?? '';
    return reading.isReading && bookId != null && bookId > 0 && cfi.isNotEmpty;
  }

  _AiChatKnowledgeSourceStatus _knowledgeCardSourceStatus({
    required SourceRef? readerSourceRef,
  }) {
    final l10n = L10n.of(context);
    if (readerSourceRef != null &&
        (readerSourceRef.canJumpBack || readerSourceRef.hasBookAnchor)) {
      return _AiChatKnowledgeSourceStatus(
        label: l10n.reviewInboxTraceableSources(1),
        tooltip: _localizedSourceStatusText(
          zh: '可跳回原文',
          en: 'Can jump back to the source text',
        ),
        traceable: true,
      );
    }

    final reading = ref.watch(currentReadingProvider);
    final canUseCurrentReaderFallback =
        !ref.read(aiChatProvider.notifier).isLoadedHistoryConversation &&
            _readingCanCreateReaderSourceRef(reading);
    if (canUseCurrentReaderFallback) {
      return _AiChatKnowledgeSourceStatus(
        label: l10n.reviewInboxTraceableSources(1),
        tooltip: _localizedSourceStatusText(
          zh: '将使用当前阅读位置作为来源',
          en: 'Will use the current reading position as source',
        ),
        traceable: true,
      );
    }

    return _AiChatKnowledgeSourceStatus(
      label: l10n.reviewInboxUnavailableSources(1),
      tooltip: _localizedSourceStatusText(
        zh: '仅保留会话来源，不能跳回原文',
        en: 'Conversation source only; no reader deep link',
      ),
      traceable: false,
    );
  }

  String _localizedSourceStatusText({
    required String zh,
    required String en,
  }) {
    final language = Localizations.localeOf(context).languageCode;
    return language == 'zh' ? zh : en;
  }

  Widget _buildKnowledgeCardSourceStatusChip(
    _AiChatKnowledgeSourceStatus status,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        status.traceable ? colorScheme.primary : colorScheme.outline;
    final background = status.traceable
        ? colorScheme.primary.withValues(alpha: 0.08)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.72);

    return Tooltip(
      message: status.tooltip,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground.withValues(alpha: 0.24)),
        ),
        child: Text(
          status.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontSize: 11,
              ),
        ),
      ),
    );
  }

  Widget _buildMessageMemoryMenu({
    required String text,
    required String sourceType,
    String? messageNodeId,
  }) {
    final l10n = L10n.of(context);
    final normalized = text.trim();
    final enabled = normalized.isNotEmpty && !_isStreaming;
    final actionKey = _messageMemoryActionKey(
      sourceType: sourceType,
      messageNodeId: messageNodeId,
      text: normalized,
    );
    final directCandidate = _directMemoryByMessageKey[actionKey];

    return PopupMenuButton<_MessageMemoryAction>(
      enabled: enabled,
      tooltip: l10n.memoryMessageActionsTooltip,
      onSelected: (action) => _handleMessageMemoryAction(
        action,
        text: text,
        sourceType: sourceType,
        messageNodeId: messageNodeId,
      ),
      itemBuilder: (context) => [
        if (directCandidate == null) ...[
          PopupMenuItem(
            value: _MessageMemoryAction.rememberNow,
            child: Text(l10n.memoryRememberThisAction),
          ),
          PopupMenuItem(
            value: _MessageMemoryAction.saveToLongTerm,
            child: Text(l10n.memorySaveToLongTermAction),
          ),
          PopupMenuItem(
            value: _MessageMemoryAction.addToReviewInbox,
            child: Text(l10n.memoryAddToReviewInboxAction),
          ),
        ] else
          PopupMenuItem(
            value: _MessageMemoryAction.undoDirectSave,
            child: Text(l10n.memoryUndoDirectSaveAction),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          Icons.bookmark_add_outlined,
          size: 20,
          color: enabled ? null : Theme.of(context).disabledColor,
        ),
      ),
    );
  }

  void _copyMessageContent(String content) {
    final parsed = parseReasoningContent(content);
    final clipboardText = _buildCopyableText(parsed, content);
    Clipboard.setData(ClipboardData(text: clipboardText));
    AnxToast.show(L10n.of(context).notesPageCopied);
  }

  void _cancelStreaming() {
    // Be tolerant: streaming state might be briefly out-of-sync during rebuilds.
    unawaited(ref.read(aiChatProvider.notifier).cancelStreaming());
  }

  ChatMessage? _getLastAssistantMessage() {
    final messages = ref.watch(aiChatProvider).asData?.value;
    if (messages == null || messages.isEmpty) {
      return null;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is AIChatMessage) {
        return messages[i];
      }
    }
    return null;
  }

  void _ensureSelectedProviderValid() {
    if (_isProviderSelectable(_selectedProviderId)) {
      return;
    }

    final fallback = _fallbackProviderId(_providers);
    if (fallback == _selectedProviderId) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isProviderSelectable(fallback)) return;
      Prefs().selectedAiService = fallback;
      setState(() {
        _selectedProviderId = fallback;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sync external draft updates (e.g. Memory page insertion) into the input.
    ref.listen<String>(aiChatDraftInputProvider, (_, next) {
      if (!mounted) return;
      if (next == inputController.text) return;

      _suppressDraftSync = true;
      inputController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      _suppressDraftSync = false;
    });
    final inlineSeminarScopeId =
        _seminarRuntimeScopeId(_inlineSeminarSessionId);
    if (inlineSeminarScopeId == null) {
      ref.listen<AiSeminarRuntimeState>(aiSeminarRuntimeProvider, (_, next) {
        if (!mounted) return;
        _syncInlineSeminarRunCard(next);
      });
    } else {
      ref.listen<AiSeminarRuntimeState>(
        aiSeminarRuntimeScopedProvider(inlineSeminarScopeId),
        (_, next) {
          if (!mounted) return;
          _syncInlineSeminarRunCard(next);
        },
      );
    }

    final quickPrompts = _getQuickPrompts(context);
    final chatIsStreaming = ref.watch(aiChatStreamingProvider);
    final contextNotice = ref.watch(aiChatContextNoticeProvider);

    // Refresh providers in case user toggled enable/disable in Provider Center.
    _providers = Prefs().aiProvidersV1;
    _ensureSelectedProviderValid();

    final current = _currentProvider;
    final currentModel = _modelLabel(_selectedProviderId);

    var aiService = PopupMenuButton<String>(
      enabled: !chatIsStreaming,
      onSelected: _onProviderSelected,
      itemBuilder: (context) {
        final enabledProviders =
            _providers.where((provider) => provider.enabled).toList();

        return enabledProviders.map((provider) {
          final isSelected = provider.id == _selectedProviderId;
          final model = _modelLabel(provider.id);
          final logoKey = _providerLogoKey(provider);

          final label =
              model.isEmpty ? provider.name : '${provider.name} · $model';

          return PopupMenuItem<String>(
            value: provider.id,
            child: Row(
              children: [
                if (logoKey.isNotEmpty)
                  Image.asset(
                    logoKey,
                    width: 20,
                    height: 20,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  )
                else
                  const SizedBox(width: 20, height: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected) const Icon(Icons.check, size: 16),
              ],
            ),
          );
        }).toList(growable: false);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            _providerLogoKey(current),
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              currentModel.isEmpty
                  ? current.name
                  : '${current.name} · $currentModel',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
    );
    // Wave L: watch draft text so the send/mic swap and suggestion visibility
    // react to every keystroke without manual setState.
    final draftText = ref.watch(aiChatDraftInputProvider);
    final draftIsEmpty = draftText.trim().isEmpty;
    final chatMessagesAsync = ref.watch(aiChatProvider);
    final chatIsEmpty = chatMessagesAsync.asData?.value.isEmpty ?? true;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Wave L: rounded pill composer with embedded + / send buttons, matching
    // Claude's reference surface. Attachments / context notices still live in
    // the Column above the pill.
    // Wave S: composer pill now stacks (text field → optional mode label →
    // action row) so the action buttons sit at the bottom of the pill even
    // when the text field grows to its multi-line max. All three action
    // surfaces (+, mic, send) are 32x32 to match the Claude reference.
    final composerPill = Container(
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: ClaudePalette.divider(context),
          width: 0.5,
        ),
        boxShadow: isDarkMode
            ? [
                BoxShadow(
                  color: ClaudePalette.divider(context).withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Expanding multiline text field (up to 5 lines).
          TextField(
            controller: inputController,
            style: TextStyle(
              fontSize: 16,
              color: ClaudePalette.fg(context),
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: L10n.of(context).aiHintInputPlaceholder,
              hintStyle: TextStyle(
                fontSize: 16,
                color: ClaudePalette.secondary(context),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            maxLines: 5,
            minLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendMessage(),
          ),
          // Action row sits at the bottom of the pill. Provider picker
          // lives inline right next to the `+` button so nothing renders
          // under the pill (user feedback: the secondary row below was
          // cluttering the bottom and the 'Chat' mode label was noise).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                // Leading + button opens the Add-to-Chat sheet.
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _showAddToChatSheet(context);
                    },
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: ClaudePalette.fg(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Inline provider / model picker (was a separate row below
                // the pill). Constrained with Flexible so long model names
                // get truncated instead of pushing the send button off.
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: aiService,
                  ),
                ),
                const Spacer(),
                // Minimize button (collapse the sheet).
                if (widget.onRequestMinimize != null)
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onRequestMinimize!();
                      },
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color:
                              ClaudePalette.fg(context).withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                // Trailing send / stop / mic button.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: chatIsStreaming
                      ? Material(
                          key: const ValueKey('composer-stop'),
                          color: ClaudePalette.secondary(context),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _cancelStreaming();
                            },
                            child: const SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(
                                Icons.stop_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      : draftIsEmpty
                          ? Material(
                              key: const ValueKey('composer-mic'),
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                },
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 20,
                                    color: ClaudePalette.fg(context),
                                  ),
                                ),
                              ),
                            )
                          : Material(
                              key: const ValueKey('composer-send'),
                              color: ClaudePalette.accent(context),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _sendMessage();
                                },
                                child: const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget inputBox = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SafeArea(
        top: false,
        bottom: widget.inputSafeAreaBottom,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((contextNotice ?? '').trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    contextNotice!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              // Book import strip (UI-only)
              if (_pendingBookImports.isNotEmpty)
                Container(
                  height: 84,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pendingBookImports.length,
                    itemBuilder: (context, index) {
                      final item = _pendingBookImports[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          width: 220,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.menu_book, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.filename,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.extension.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: L10n.of(context).exportAndImportImport,
                                onPressed: () => _importBookImportAt(index),
                                icon: const Icon(Icons.download),
                              ),
                              IconButton(
                                tooltip: L10n.of(context).commonRemove,
                                onPressed: () => _removeBookImportAt(index),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Attachments strip
              if (_attachments.isNotEmpty)
                Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _attachments.length,
                    itemBuilder: (context, index) {
                      final attachment = _attachments[index];
                      Widget thumbnail;
                      if (attachment.type == AttachmentType.image) {
                        thumbnail = ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            attachment.bytes,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        );
                      } else {
                        thumbnail = Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Icon(Icons.description, size: 28),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            thumbnail,
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => _removeAttachment(index),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              composerPill,
              // Quick suggestion chip strip — rendered BELOW the pill
              // (Claude Code mobile reference) and only while the
              // conversation is empty so it feels like a first-run surface.
              if (chatIsEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: _buildQuickSuggestions(quickPrompts),
                ),
              // Minimize affordance (only when the chat is a nested sheet
              // inside the reader) — tiny row with no provider info now
              // that aiService lives inside the pill.
              if (widget.onRequestMinimize != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: ClaudePalette.secondary(context),
                      ),
                      onPressed: widget.onRequestMinimize,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.onRequestMinimize != null) {
      inputBox = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          _inputSwipeDownDy = 0;
        },
        onVerticalDragUpdate: (details) {
          final delta = details.primaryDelta ?? 0;
          if (delta > 0) {
            _inputSwipeDownDy += delta;
          }
        },
        onVerticalDragEnd: (_) {
          if (_inputSwipeDownDy > 24) {
            HapticFeedback.selectionClick();
            widget.onRequestMinimize?.call();
          }
          _inputSwipeDownDy = 0;
        },
        child: inputBox,
      );
    }

    Widget buildEmptyState() {
      if (widget.emptyStateBuilder != null) {
        final content = widget.emptyStateBuilder!(
          context,
          (prompt) {
            inputController.text = prompt;
            _sendMessage();
          },
        );

        // Keep scroll controller attached for DraggableScrollableSheet.
        return CustomScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: content,
            ),
          ],
        );
      }

      final theme = Theme.of(context);

      Widget buildQuickChipColumn() {
        if (widget.quickPromptChips.isEmpty) {
          return const SizedBox.shrink();
        }

        Widget actionButton(AiQuickPromptChip chip) {
          return SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () {
                inputController.text = chip.prompt;
                _sendMessage();
              },
              icon: Icon(chip.icon, size: 18),
              label: Text(
                chip.label,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          );
        }

        final buttons = widget.quickPromptChips
            .map(
              (chip) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: actionButton(chip),
              ),
            )
            .toList(growable: false);

        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: buttons,
                ),
              ),
            ),
          ),
        );
      }

      final content = Stack(
        children: [
          if (widget.quickPromptChips.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.of(context).tryAQuickPrompt,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestedPrompts
                        .map(
                          (prompt) => ActionChip(
                            label: Text(prompt),
                            onPressed: () {
                              inputController.text = prompt;
                              _sendMessage();
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          buildQuickChipColumn(),
        ],
      );

      // IMPORTANT:
      // When used inside DraggableScrollableSheet, we must always attach the
      // provided ScrollController to a ScrollView; otherwise the sheet
      // controller won't be attached and programmatic minimize won't work.
      //
      // Use SliverFillRemaining to make the empty state fill the available
      // space, avoiding the "invisible frame" / clipped chip area.
      return CustomScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: content,
          ),
        ],
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          L10n.of(context).aiChat,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: ClaudePalette.fg(context),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left_rounded,
            size: 28,
            color: ClaudePalette.fg(context),
          ),
          tooltip: L10n.of(context).history,
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.text_fields,
              size: 22,
              color: ClaudePalette.fg(context),
            ),
            tooltip: L10n.of(context).font,
            onPressed: _showFontScaleSheet,
          ),
          IconButton(
            icon: Icon(
              Icons.edit_document,
              size: 22,
              color: ClaudePalette.fg(context),
            ),
            tooltip: L10n.of(context).aiChatEndSessionAction,
            onPressed: _clearMessage,
          ),
          if (widget.trailing != null) ...widget.trailing!,
        ],
      ),
      drawer: Drawer(
        child: _buildHistoryDrawer(context),
      ),
      body: Column(
        children: [
          Expanded(
            child: ref.watch(aiChatProvider).when(
                  data: (messages) {
                    if (messages.isEmpty) {
                      return buildEmptyState();
                    }

                    return _buildMessageList(messages);
                  },
                  loading: () => Skeletonizer.zone(child: Bone.multiText()),
                  error: (error, stack) => Center(child: Text('error: $error')),
                ),
          ),
          if (_inlineSeminarVisible) _buildInlineSeminarPanel(),
          inputBox,
        ],
      ),
    );
  }

  double get _messageTextScale =>
      Prefs().aiChatFontScale.clamp(0.8, 1.4).toDouble();

  Widget _buildScaledMessageContent(Widget child) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_messageTextScale),
      ),
      child: child,
    );
  }

  TextStyle _messageBodyTextStyle(BuildContext context) {
    return (Theme.of(context).textTheme.bodyMedium ??
            const TextStyle(fontSize: 14))
        .copyWith(height: 1.55);
  }

  Widget _buildMessageList(List<ChatMessage> messages) {
    final lastHumanIndex = _findLastHumanIndex(messages);
    final isStreaming = ref.watch(aiChatStreamingProvider);

    return ListView.builder(
      controller: _scrollController,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isLastMessage = index == messages.length - 1;
        return _buildLinearMessageItem(
          messages,
          message,
          index,
          isStreaming && isLastMessage,
          lastHumanIndex: lastHumanIndex,
        );
      },
    );
  }

  List<_ChatItem> _buildChatItems(List<ChatMessage> messages) {
    final items = <_ChatItem>[];
    var i = 0;
    while (i < messages.length) {
      final message = messages[i];
      if (message is HumanChatMessage) {
        items.add(_UserChatItem(index: i, message: message));

        final variants = <AIChatMessage>[];
        var j = i + 1;
        while (j < messages.length && messages[j] is AIChatMessage) {
          variants.add(messages[j] as AIChatMessage);
          j++;
        }
        if (variants.isNotEmpty) {
          items.add(
            _AssistantGroupChatItem(
              groupKey: i,
              userIndex: i,
              variants: variants,
            ),
          );
        }
        i = j;
        continue;
      }

      if (message is AIChatMessage) {
        // Orphan assistant messages (should be rare). Group them to keep the UI
        // consistent.
        final variants = <AIChatMessage>[];
        var j = i;
        while (j < messages.length && messages[j] is AIChatMessage) {
          variants.add(messages[j] as AIChatMessage);
          j++;
        }
        items.add(
          _AssistantGroupChatItem(
            groupKey: -(i + 1),
            userIndex: null,
            variants: variants,
          ),
        );
        i = j;
        continue;
      }

      i++;
    }

    return items;
  }

  int? _findLastHumanIndex(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is HumanChatMessage) {
        return i;
      }
    }
    return null;
  }

  int? _findPrevHumanIndex(List<ChatMessage> messages, int fromIndex) {
    for (var i = fromIndex; i >= 0; i--) {
      if (messages[i] is HumanChatMessage) {
        return i;
      }
    }
    return null;
  }

  Widget _buildVariantSwitcher(
    int messageIndex,
    bool isStreaming,
  ) {
    final notifier = ref.read(aiChatProvider.notifier);
    final count = notifier.variantCountForMessageIndex(messageIndex);
    if (count <= 1) {
      return const SizedBox.shrink();
    }

    final selected = notifier.selectedVariantIndexForMessageIndex(messageIndex);
    final canNavigate = !_isStreaming && !isStreaming;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 18),
          onPressed: canNavigate && selected > 0
              ? () {
                  notifier.switchVariantAtMessageIndexAndPersist(
                    messageIndex,
                    -1,
                    ref,
                  );
                }
              : null,
        ),
        Text('${selected + 1}/$count'),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 18),
          onPressed: canNavigate && selected < count - 1
              ? () {
                  notifier.switchVariantAtMessageIndexAndPersist(
                    messageIndex,
                    1,
                    ref,
                  );
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildLinearMessageItem(
    List<ChatMessage> allMessages,
    ChatMessage message,
    int index,
    bool isStreaming, {
    required int? lastHumanIndex,
  }) {
    final isUser = message is HumanChatMessage;
    final content =
        isUser ? _extractUserTextFromHuman(message) : message.contentAsString;

    final prevHumanIndex =
        isUser ? index : _findPrevHumanIndex(allMessages, index);
    final isLastTurn =
        prevHumanIndex != null && prevHumanIndex == lastHumanIndex;
    final seminarRunCard = isUser
        ? null
        : ref
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(index);
    final assistantReaderSourceRef = !isUser && prevHumanIndex != null
        ? _readerSourceRefForUserIndex(prevHumanIndex)
        : null;
    final assistantSourceStatus = isUser || seminarRunCard != null
        ? null
        : _knowledgeCardSourceStatus(
            readerSourceRef: assistantReaderSourceRef,
          );

    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.8;

    Widget? footer;
    if (!isUser && seminarRunCard == null) {
      final segMeta =
          ref.read(aiChatProvider.notifier).segmentMetaForMessageIndex(index);
      final segText = segMeta?.footerText() ?? '';
      final isLastAssistant =
          index == allMessages.lastIndexWhere((m) => m is AIChatMessage);
      final usageSummary = ref.watch(aiChatUsageSummaryProvider);
      final cumulative =
          isLastAssistant && (usageSummary ?? '').trim().isNotEmpty
              ? '会话累计 $usageSummary'
              : '';
      final pieces = [segText, cumulative].where((s) => s.isNotEmpty).toList();
      if (pieces.isNotEmpty) {
        footer = Padding(
          padding: const EdgeInsets.only(top: 2, left: 2),
          child: Text(
            pieces.join('  ·  '),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        );
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isUser ? 8.0 : 12.0,
        4.0,
        isUser ? 8.0 : 12.0,
        8.0,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: isUser ? maxBubbleWidth : double.infinity),
              child: Container(
                padding: isUser
                    ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                    : EdgeInsets.zero,
                decoration: isUser
                    ? BoxDecoration(
                        color: ClaudePalette.accentTint(context),
                        borderRadius: BorderRadius.circular(18),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildScaledMessageContent(
                      isUser
                          ? _buildHumanMessageBody(message)
                          : seminarRunCard == null
                              ? _buildAssistantSections(content, isStreaming)
                              : _buildSeminarRunCard(seminarRunCard),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        _buildVariantSwitcher(index, isStreaming),
                        if (isUser) ...[
                          TextButton(
                            onPressed: () => _showEditUserMessageDialog(
                              index,
                              message,
                            ),
                            child: Text(L10n.of(context).commonEdit),
                          ),
                          TextButton(
                            onPressed: () => _copyPlainText(content),
                            child: Text(L10n.of(context).commonCopy),
                          ),
                          _buildMessageMemoryMenu(
                            text: content,
                            sourceType: 'chat',
                            messageNodeId: 'user:$index',
                          ),
                        ] else if (seminarRunCard == null) ...[
                          if (prevHumanIndex != null)
                            TextButton(
                              onPressed: () => _confirmRegenerateFromUserIndex(
                                prevHumanIndex,
                                isLastTurn: isLastTurn,
                              ),
                              child: Text(L10n.of(context).aiRegenerate),
                            ),
                          TextButton(
                            onPressed: () => _copyMessageContent(content),
                            child: Text(L10n.of(context).commonCopy),
                          ),
                          if (assistantSourceStatus != null)
                            _buildKnowledgeCardSourceStatusChip(
                              assistantSourceStatus,
                            ),
                          TextButton(
                            onPressed: isStreaming
                                ? null
                                : () => _handleAssistantKnowledgeCardAction(
                                      answer: _assistantMemoryText(content),
                                      userPrompt: prevHumanIndex == null
                                          ? null
                                          : _humanTextAt(
                                              allMessages,
                                              prevHumanIndex,
                                            ),
                                      messageNodeId: 'assistant:$index',
                                      readerSourceRef: assistantReaderSourceRef,
                                    ),
                            child:
                                Text(L10n.of(context).contextMenuKnowledgeCard),
                          ),
                          _buildMessageMemoryMenu(
                            text: _assistantMemoryText(content),
                            sourceType: 'chat',
                            messageNodeId: 'assistant:$index',
                          ),
                        ],
                      ],
                    ),
                    if (footer != null) footer,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeminarRunCard(AiSeminarRunCardMeta card) {
    final l10n = L10n.of(context);
    final question = card.question.trim();
    final runtimeState = _watchSeminarRuntimeState(card.sessionId);
    _syncSeminarRunCardSnapshot(card.sessionId, runtimeState);
    final canSendToReview = card.sessionId != null &&
        runtimeState.session?.id == card.sessionId &&
        runtimeState.canSendToReview;
    final canSaveKnowledgeCard = card.sessionId != null &&
        runtimeState.session?.id == card.sessionId &&
        _seminarSynthesisKnowledgeCardSourceRefs(runtimeState).isNotEmpty;
    final canAddSpacedReview = canSaveKnowledgeCard;
    final canAddConceptGraph = canSaveKnowledgeCard;
    final knowledgeCardId = _seminarSynthesisKnowledgeCardId(card.sessionId);
    final hasSavedKnowledgeCard = knowledgeCardId != null &&
        _seminarCardSavedKnowledgeCardIds.contains(knowledgeCardId);
    final reviewFlashcardId =
        _seminarSynthesisReviewFlashcardId(card.sessionId);
    final hasAddedSpacedReview = reviewFlashcardId != null &&
        _seminarCardSpacedReviewFlashcardIds.contains(reviewFlashcardId);
    final conceptNodeId = _seminarSynthesisConceptNodeId(card.sessionId);
    final hasAddedConceptGraph = conceptNodeId != null &&
        _seminarCardConceptNodeIds.contains(conceptNodeId);
    final normalizedSessionId = card.sessionId?.trim();
    final hasIgnoredActions = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        _seminarCardIgnoredActionSessionIds.contains(normalizedSessionId);
    final hasAnyAssetAction = canSaveKnowledgeCard ||
        canAddSpacedReview ||
        canAddConceptGraph ||
        canSendToReview;
    final canIgnoreAssetActions = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        !hasSavedKnowledgeCard &&
        !hasAddedSpacedReview &&
        !hasAddedConceptGraph &&
        hasAnyAssetAction;

    void openCard() {
      openInlineSeminar(
        question: question.isEmpty ? null : question,
        sessionId: card.sessionId,
        bookId: card.sourceRef?.bookId ?? card.bookId,
        sourceRef: card.sourceRef,
        roleProfiles: card.roleProfiles,
        maxRounds: card.maxRounds,
        includeVerifier: card.roleIds.contains(AiSeminarRole.verifier.asString),
      );
    }

    Widget openTarget(
      Widget child, {
      Key? key,
    }) {
      return InkWell(
        key: key,
        borderRadius: BorderRadius.circular(6),
        onTap: openCard,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: child,
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
          color: ClaudePalette.card(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.groups_2_outlined,
                  size: 18,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: openCard,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        l10n.aiChatSeminarFeatureTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ClaudePalette.fg(context),
                            ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.seminarConfigTitle,
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  onPressed: () => Navigator.of(context).push(
                    CupertinoStyleRoute(
                      page: const AiSeminarConfigPage(),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: openCard,
                  child: Text(l10n.aiChatSeminarFeatureAction),
                ),
              ],
            ),
            const SizedBox(height: 8),
            openTarget(
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _seminarMetaChips(card),
              ),
            ),
            if (question.isNotEmpty) ...[
              const SizedBox(height: 7),
              openTarget(
                Text(
                  question,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ClaudePalette.fg(context),
                        height: 1.35,
                      ),
                ),
                key: card.sessionId == null
                    ? null
                    : ValueKey('seminar-chat-card-question-${card.sessionId}'),
              ),
            ],
            if (card.snapshot != null && !card.snapshot!.isEmpty) ...[
              const SizedBox(height: 9),
              openTarget(
                _buildSeminarRunSnapshot(
                  card.sessionId,
                  card.snapshot!,
                  runtimeState,
                ),
                key: card.sessionId == null
                    ? null
                    : ValueKey('seminar-chat-card-snapshot-${card.sessionId}'),
              ),
            ],
            if (_shouldShowSeminarCardResumeBanner(card, runtimeState)) ...[
              const SizedBox(height: 12),
              _buildSeminarRunCardResumeBanner(
                card,
                runtimeState,
                onOpen: openCard,
                onContinue: () => _continueSeminarRunCardFromCheckpoint(
                  card.sessionId,
                ),
              ),
            ],
            if (_shouldShowSeminarCardDisagreementActions(
              card,
              runtimeState,
            )) ...[
              const SizedBox(height: 12),
              _buildSeminarRunCardDisagreementActions(card, runtimeState),
            ],
            if (_shouldShowSeminarCardComposer(card, runtimeState)) ...[
              const SizedBox(height: 12),
              _buildSeminarRunCardComposer(card, runtimeState),
            ],
            if (hasIgnoredActions) ...[
              const SizedBox(height: 12),
              _buildSeminarRunCardIgnoredActionsNotice(card.sessionId),
            ] else if (hasAnyAssetAction) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canSaveKnowledgeCard)
                    hasSavedKnowledgeCard
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.undo_outlined, size: 18),
                            label: Text(
                              _localizedSeminarCardText(
                                zh: '撤销保存',
                                en: 'Undo save',
                              ),
                            ),
                            onPressed: () =>
                                _undoActiveSeminarRunCardKnowledgeCard(
                              card.sessionId,
                            ),
                          )
                        : FilledButton.icon(
                            icon: const Icon(Icons.style_outlined, size: 18),
                            label: Text(
                              _localizedSeminarCardText(
                                zh: '保存知识卡',
                                en: 'Save card',
                              ),
                            ),
                            onPressed: () =>
                                _saveActiveSeminarRunCardKnowledgeCard(
                              card.sessionId,
                            ),
                          ),
                  if (canSaveKnowledgeCard && !hasSavedKnowledgeCard)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.edit_note_outlined, size: 18),
                      label: Text(
                        _localizedSeminarCardText(
                          zh: '编辑后保存',
                          en: 'Edit and save',
                        ),
                      ),
                      onPressed: () => _editActiveSeminarRunCardKnowledgeCard(
                        card.sessionId,
                      ),
                    ),
                  if (canAddSpacedReview)
                    hasAddedSpacedReview
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.undo_outlined, size: 18),
                            label: Text(
                              _localizedSeminarCardText(
                                zh: '撤销复习',
                                en: 'Undo review',
                              ),
                            ),
                            onPressed: () =>
                                _undoActiveSeminarRunCardSpacedReview(
                              card.sessionId,
                            ),
                          )
                        : FilledButton.tonalIcon(
                            icon: const Icon(Icons.school_outlined, size: 18),
                            label: Text(
                              _localizedSeminarCardText(
                                zh: '加入复习',
                                en: 'Add review',
                              ),
                            ),
                            onPressed: () =>
                                _addActiveSeminarRunCardSpacedReview(
                              card.sessionId,
                            ),
                          ),
                  if (canAddConceptGraph)
                    hasAddedConceptGraph
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.undo_outlined, size: 18),
                            label: Text(
                              _localizedSeminarCardText(
                                zh: '撤销图谱',
                                en: 'Undo graph',
                              ),
                            ),
                            onPressed: () =>
                                _undoActiveSeminarRunCardConceptGraph(
                              card.sessionId,
                            ),
                          )
                        : FilledButton.tonalIcon(
                            icon: const Icon(
                              Icons.account_tree_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _localizedSeminarCardText(
                                zh: '加入我的图谱',
                                en: 'Add to graph',
                              ),
                            ),
                            onPressed: () =>
                                _addActiveSeminarRunCardConceptGraph(
                              card.sessionId,
                            ),
                          ),
                  if (canSendToReview)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: Text(l10n.seminarSendToReview),
                      onPressed: () => _sendActiveSeminarRunCardToReview(
                        card.sessionId,
                      ),
                    ),
                  if (canIgnoreAssetActions)
                    TextButton.icon(
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: Text(
                        _localizedSeminarCardText(
                          zh: '忽略',
                          en: 'Ignore',
                        ),
                      ),
                      onPressed: () =>
                          _ignoreSeminarRunCardAssetActions(card.sessionId),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeminarRunCardIgnoredActionsNotice(String? sessionId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: ClaudePalette.bg(context).withValues(alpha: 0.55),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 17,
            color: ClaudePalette.fg(context).withValues(alpha: 0.62),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _localizedSeminarCardText(
                zh: '已忽略本次沉淀建议',
                en: 'Suggestions ignored',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.fg(context).withValues(alpha: 0.62),
                  ),
            ),
          ),
          TextButton(
            onPressed: () => _restoreSeminarRunCardAssetActions(sessionId),
            child: Text(
              _localizedSeminarCardText(
                zh: '恢复操作',
                en: 'Restore',
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldShowSeminarCardResumeBanner(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return false;
    return runtimeState.session?.id == sessionId &&
        runtimeState.canResumeRestoredRunning;
  }

  Widget _buildSeminarRunCardResumeBanner(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState, {
    required VoidCallback onOpen,
    required VoidCallback onContinue,
  }) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) {
      return const SizedBox.shrink();
    }
    final isSubmitting = _seminarCardSubmittingSessionIds.contains(sessionId);
    final completedRoleCount = runtimeState.turns
        .where((turn) => turn.responseText.trim().isNotEmpty)
        .length;
    final provider = runtimeState.providerDiagnostics;
    final providerLabel = provider == null || provider.modelId.trim().isEmpty
        ? ''
        : ' · ${provider.providerName} / ${provider.modelId}';
    final detail = _localizedSeminarCardText(
      zh: '已完成 $completedRoleCount 个角色，可直接继续缺失角色，也可打开查看恢复详情$providerLabel。',
      en: '$completedRoleCount roles completed. Continue missing roles directly, or open details$providerLabel.',
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.restore_outlined,
                  size: 18,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _localizedSeminarCardText(
                          zh: '可从中断处继续',
                          en: 'Resumable checkpoint',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: ClaudePalette.fg(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: ValueKey('seminar-chat-card-continue-$sessionId'),
                  onPressed: isSubmitting ? null : onContinue,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_outlined, size: 18),
                  label: Text(
                    _localizedSeminarCardText(
                      zh: '继续研讨',
                      en: 'Continue seminar',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: ValueKey('seminar-chat-card-resume-$sessionId'),
                  onPressed: isSubmitting ? null : onOpen,
                  icon: const Icon(Icons.open_in_new_outlined, size: 18),
                  label: Text(
                    _localizedSeminarCardText(
                      zh: '打开恢复',
                      en: 'Open resume',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _continueSeminarRunCardFromCheckpoint(
    String? rawSessionId,
  ) async {
    final sessionId = rawSessionId?.trim();
    if (sessionId == null ||
        sessionId.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(sessionId)) {
      return;
    }
    final runtimeState = _readSeminarRuntimeState(sessionId);
    if (runtimeState.session?.id != sessionId ||
        !runtimeState.canResumeRestoredRunning) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(sessionId));
    try {
      await _readSeminarRuntimeNotifier(sessionId).resumeRestoredRunning();
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      _seminarCardSubmittingSessionIds.remove(sessionId);
      if (mounted) setState(() {});
    }
  }

  bool _shouldShowSeminarCardComposer(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return false;
    if (runtimeState.session?.id != sessionId) return false;
    if (runtimeState.evidenceBundle == null) return false;
    return runtimeState.status == AiSeminarRunStatus.completed ||
        runtimeState.directorState?.needsUserInput == true;
  }

  bool _shouldShowSeminarCardDisagreementActions(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    if (!_shouldShowSeminarCardComposer(card, runtimeState)) return false;
    final snapshot = card.snapshot;
    if (snapshot == null) return false;
    return snapshot.disagreements.any((item) => item.trim().isNotEmpty);
  }

  TextEditingController _seminarCardReplyController(String sessionId) {
    return _seminarCardReplyControllers.putIfAbsent(
      sessionId,
      () => TextEditingController(),
    );
  }

  List<AiSeminarRole> _seminarCardAvailableRoles(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionRoles = runtimeState.session?.roles;
    final roles = sessionRoles != null && sessionRoles.isNotEmpty
        ? sessionRoles
        : card.roleIds
            .map(AiSeminarRole.fromString)
            .nonNulls
            .toList(growable: false);
    final effectiveRoles = roles.isEmpty ? AiSeminarRole.defaultRoles : roles;
    final nonSynthesizerRoles = effectiveRoles
        .where((role) => role != AiSeminarRole.synthesizer)
        .toList(growable: false);
    return nonSynthesizerRoles.isEmpty
        ? effectiveRoles.toList(growable: false)
        : nonSynthesizerRoles;
  }

  AiSeminarRole _seminarCardSelectedRole(
    String sessionId,
    List<AiSeminarRole> roles,
  ) {
    final fallback = roles.isEmpty ? AiSeminarRole.critical : roles.first;
    final selected = _seminarCardSelectedRoles[sessionId];
    if (selected == null || !roles.contains(selected)) {
      _seminarCardSelectedRoles[sessionId] = fallback;
      return fallback;
    }
    return selected;
  }

  Widget _buildSeminarRunCardComposer(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return const SizedBox.shrink();
    final controller = _seminarCardReplyController(sessionId);
    final roles = _seminarCardAvailableRoles(card, runtimeState);
    final selectedRole = _seminarCardSelectedRole(sessionId, roles);
    final isSubmitting = _seminarCardSubmittingSessionIds.contains(sessionId);
    final canSubmit = controller.text.trim().isNotEmpty && !isSubmitting;
    final borderColor = ClaudePalette.divider(context);
    final isAwaitingReader = runtimeState.directorState?.needsUserInput == true;
    final askUserQuestion =
        isAwaitingReader ? _seminarCardFirstOpenQuestion(runtimeState) : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.45),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _localizedSeminarCardText(
                      zh: '读者参与',
                      en: 'Reader turn',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: ClaudePalette.fg(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isAwaitingReader
                  ? _localizedSeminarCardText(
                      zh: '主持人正在等待你的回应',
                      en: 'The Director is waiting for your reply',
                    )
                  : _localizedSeminarCardText(
                      zh: '你的输入会作为读者回合记录，可以要求角色继续反驳、重新找证据或整理总结，不会被当成书内证据。',
                      en: 'Your reply is stored as a reader turn. It can steer a role, refresh evidence, or synthesize the run, and is not treated as book evidence.',
                    ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isAwaitingReader
                        ? ClaudePalette.fg(context)
                        : ClaudePalette.secondary(context),
                    fontWeight:
                        isAwaitingReader ? FontWeight.w700 : FontWeight.w400,
                    height: 1.32,
                  ),
            ),
            if (askUserQuestion != null) ...[
              const SizedBox(height: 3),
              Text(
                askUserQuestion,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                      height: 1.32,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('seminar-chat-card-reply-$sessionId'),
              controller: controller,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _localizedSeminarCardText(
                  zh: '你的研讨回复',
                  en: 'Your Seminar reply',
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AiSeminarRole>(
              key: ValueKey('seminar-chat-card-role-$sessionId'),
              initialValue: selectedRole,
              decoration: InputDecoration(
                labelText: _localizedSeminarCardText(
                  zh: '回应角色',
                  en: 'Target role',
                ),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final role in roles)
                  DropdownMenuItem(
                    value: role,
                    child: Text(_seminarRoleFallbackLabel(role.asString)),
                  ),
              ],
              onChanged: isSubmitting
                  ? null
                  : (role) {
                      if (role == null) return;
                      setState(() {
                        _seminarCardSelectedRoles[sessionId] = role;
                      });
                    },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: ValueKey('seminar-chat-card-ask-role-$sessionId'),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.record_voice_over_outlined),
                  label: Text(
                    _localizedSeminarCardText(
                      zh: '让所选角色回应',
                      en: 'Ask selected role',
                    ),
                  ),
                  onPressed: canSubmit
                      ? () => _submitSeminarCardIntervention(
                            sessionId: sessionId,
                            action: AiSeminarUserInterventionAction.askRole,
                            targetRole:
                                _seminarCardSelectedRole(sessionId, roles),
                          )
                      : null,
                ),
                OutlinedButton.icon(
                  key: ValueKey(
                    'seminar-chat-card-refresh-evidence-$sessionId',
                  ),
                  icon: const Icon(Icons.travel_explore_outlined),
                  label: Text(
                    _localizedSeminarCardText(
                      zh: '重新找证据',
                      en: 'Refresh evidence',
                    ),
                  ),
                  onPressed: canSubmit
                      ? () => _submitSeminarCardIntervention(
                            sessionId: sessionId,
                            action:
                                AiSeminarUserInterventionAction.refreshEvidence,
                          )
                      : null,
                ),
                OutlinedButton.icon(
                  key: ValueKey('seminar-chat-card-synthesize-$sessionId'),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(
                    _localizedSeminarCardText(
                      zh: '整理总结',
                      en: 'Synthesize',
                    ),
                  ),
                  onPressed: canSubmit
                      ? () => _submitSeminarCardIntervention(
                            sessionId: sessionId,
                            action: AiSeminarUserInterventionAction.synthesize,
                          )
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _seminarCardFirstOpenQuestion(AiSeminarRuntimeState runtimeState) {
    final entries = <AiSeminarWhiteboardEntry>[
      ...runtimeState.whiteboardEntries,
      for (final turn in runtimeState.turns) ...turn.whiteboardEntries,
    ];
    for (final entry in entries) {
      if (entry.kind != AiSeminarWhiteboardKind.openQuestion) continue;
      final text = entry.text.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  Widget _buildSeminarRunCardDisagreementActions(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = card.sessionId?.trim();
    final snapshot = card.snapshot;
    if (sessionId == null || sessionId.isEmpty || snapshot == null) {
      return const SizedBox.shrink();
    }
    final disagreement = snapshot.disagreements
        .map((item) => item.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    if (disagreement.isEmpty) return const SizedBox.shrink();
    final roles = _seminarCardAvailableRoles(card, runtimeState);
    final targetRole = roles.contains(AiSeminarRole.critical)
        ? AiSeminarRole.critical
        : _seminarCardSelectedRole(sessionId, roles);
    final isSubmitting = _seminarCardSubmittingSessionIds.contains(sessionId);
    final targetLabel = _seminarRoleFallbackLabel(targetRole.asString);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: Theme.of(context)
            .colorScheme
            .tertiaryContainer
            .withValues(alpha: 0.42),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.report_problem_outlined,
                  size: 16,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _localizedSeminarCardText(
                      zh: '分歧继续讨论',
                      en: 'Continue from disagreement',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: ClaudePalette.fg(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              disagreement,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.32,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: ValueKey(
                    'seminar-chat-card-ask-critical-disagreement-$sessionId',
                  ),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.record_voice_over_outlined),
                  label: Text(
                    targetRole == AiSeminarRole.critical
                        ? _localizedSeminarCardText(
                            zh: '让批判者反驳',
                            en: 'Ask Critical to rebut',
                          )
                        : _localizedSeminarCardText(
                            zh: '让$targetLabel回应',
                            en: 'Ask $targetLabel to respond',
                          ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () => _submitSeminarCardInterventionText(
                            sessionId: sessionId,
                            text: _localizedSeminarCardText(
                              zh: '围绕分歧继续反驳：$disagreement',
                              en: 'Continue the rebuttal around this disagreement: $disagreement',
                            ),
                            action: AiSeminarUserInterventionAction.askRole,
                            targetRole: targetRole,
                          ),
                ),
                OutlinedButton.icon(
                  key: ValueKey(
                    'seminar-chat-card-refresh-disagreement-$sessionId',
                  ),
                  icon: const Icon(Icons.travel_explore_outlined),
                  label: Text(
                    _localizedSeminarCardText(
                      zh: '围绕分歧重找证据',
                      en: 'Refresh evidence for this',
                    ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () => _submitSeminarCardInterventionText(
                            sessionId: sessionId,
                            text: _localizedSeminarCardText(
                              zh: '围绕分歧重新找证据：$disagreement',
                              en: 'Refresh evidence around this disagreement: $disagreement',
                            ),
                            action:
                                AiSeminarUserInterventionAction.refreshEvidence,
                          ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitSeminarCardIntervention({
    required String sessionId,
    required AiSeminarUserInterventionAction action,
    AiSeminarRole? targetRole,
  }) async {
    final controller = _seminarCardReplyControllers[sessionId];
    final text = controller?.text.trim() ?? '';
    await _submitSeminarCardInterventionText(
      sessionId: sessionId,
      text: text,
      action: action,
      targetRole: targetRole,
      onSuccess: () => controller?.clear(),
    );
  }

  Future<void> _submitSeminarCardInterventionText({
    required String sessionId,
    required String text,
    required AiSeminarUserInterventionAction action,
    AiSeminarRole? targetRole,
    VoidCallback? onSuccess,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(sessionId)) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(sessionId));
    try {
      final notifier = _readSeminarRuntimeNotifier(sessionId);
      await notifier.recordUserIntervention(
        text: trimmed,
        requestedAction: action,
        targetRole: targetRole,
      );
      await notifier.executeDirectorNextStep();
      if (!mounted) return;
      onSuccess?.call();
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      _seminarCardSubmittingSessionIds.remove(sessionId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _sendActiveSeminarRunCardToReview(String? sessionId) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final runtimeState = _readSeminarRuntimeState(sessionId);
    if (sessionId == null ||
        runtimeState.session?.id != sessionId ||
        !runtimeState.canSendToReview) {
      return;
    }
    try {
      final result =
          await _readSeminarRuntimeNotifier(sessionId).sendToReview();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.seminarSentToReview(result.knowledgeCardIds.length),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _ignoreSeminarRunCardAssetActions(String? sessionId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    setState(() {
      _seminarCardIgnoredActionSessionIds.add(normalizedSessionId);
    });
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '已忽略本次沉淀建议。',
              en: 'Suggestions ignored for this Seminar.',
            ),
          ),
        ),
      );
  }

  void _restoreSeminarRunCardAssetActions(String? sessionId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    setState(() {
      _seminarCardIgnoredActionSessionIds.remove(normalizedSessionId);
    });
  }

  Future<void> _saveActiveSeminarRunCardKnowledgeCard(
    String? sessionId, {
    String? editedTitle,
    String? editedExplanation,
  }) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    final cardId = _seminarSynthesisKnowledgeCardId(normalizedSessionId);
    if (cardId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    final synthesis = runtimeState.synthesis;
    final sourceRefs = _seminarSynthesisKnowledgeCardSourceRefs(runtimeState);
    if (runtimeState.session?.id != normalizedSessionId ||
        synthesis == null ||
        synthesis.summary.trim().isEmpty ||
        sourceRefs.isEmpty) {
      return;
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final quote = sourceRefs
        .map((ref) => ref.sourceTextSnippet ?? '')
        .firstWhere((text) => text.trim().isNotEmpty, orElse: () => '');
    final title = editedTitle?.trim().isNotEmpty == true
        ? editedTitle!.trim()
        : 'AI Seminar synthesis';
    final explanation = editedExplanation?.trim().isNotEmpty == true
        ? editedExplanation!.trim()
        : synthesis.summary.trim();
    final card = KnowledgeCard(
      id: cardId,
      title: title,
      quote: quote,
      explanation: explanation,
      sourceRefs: sourceRefs,
      reviewState: KnowledgeCardReviewState.draft,
      origin: KnowledgeCardOrigin.seminar,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    try {
      final result =
          await ref.read(aiSeminarKnowledgeCardStoreProvider).upsertCandidate(
                card,
              );
      if (!mounted) return;
      if (result.inserted || result.card.id == cardId) {
        setState(() => _seminarCardSavedKnowledgeCardIds.add(cardId));
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '已保存为知识卡。',
              en: 'Saved as a KnowledgeCard.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _editActiveSeminarRunCardKnowledgeCard(
    String? sessionId,
  ) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    final synthesis = runtimeState.synthesis;
    if (runtimeState.session?.id != normalizedSessionId ||
        synthesis == null ||
        synthesis.summary.trim().isEmpty ||
        _seminarSynthesisKnowledgeCardSourceRefs(runtimeState).isEmpty) {
      return;
    }
    final edited = await _showSeminarKnowledgeCardEditDialog(
      initialTitle: 'AI Seminar synthesis',
      initialExplanation: synthesis.summary.trim(),
    );
    if (!mounted || edited == null) return;
    await _saveActiveSeminarRunCardKnowledgeCard(
      normalizedSessionId,
      editedTitle: edited['title'],
      editedExplanation: edited['explanation'],
    );
  }

  Future<Map<String, String>?> _showSeminarKnowledgeCardEditDialog({
    required String initialTitle,
    required String initialExplanation,
  }) async {
    var title = initialTitle;
    var explanation = initialExplanation;
    String? explanationError;
    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                _localizedSeminarCardText(
                  zh: '编辑知识卡',
                  en: 'Edit KnowledgeCard',
                ),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        key: const ValueKey('seminar-card-edit-title'),
                        initialValue: initialTitle,
                        decoration: InputDecoration(
                          labelText: _localizedSeminarCardText(
                            zh: '标题',
                            en: 'Title',
                          ),
                        ),
                        onChanged: (value) => title = value,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('seminar-card-edit-explanation'),
                        initialValue: initialExplanation,
                        minLines: 4,
                        maxLines: 8,
                        decoration: InputDecoration(
                          labelText: _localizedSeminarCardText(
                            zh: '解释',
                            en: 'Explanation',
                          ),
                          errorText: explanationError,
                        ),
                        onChanged: (value) => explanation = value,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    _localizedSeminarCardText(
                      zh: '取消',
                      en: 'Cancel',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final normalizedExplanation = explanation.trim();
                    if (normalizedExplanation.isEmpty) {
                      setDialogState(() {
                        explanationError = _localizedSeminarCardText(
                          zh: '解释不能为空',
                          en: 'Explanation is required',
                        );
                      });
                      return;
                    }
                    final normalizedTitle = title.trim();
                    Navigator.of(dialogContext).pop({
                      'title': normalizedTitle.isEmpty
                          ? initialTitle
                          : normalizedTitle,
                      'explanation': normalizedExplanation,
                    });
                  },
                  child: Text(
                    _localizedSeminarCardText(
                      zh: '保存',
                      en: 'Save',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _undoActiveSeminarRunCardKnowledgeCard(
    String? sessionId,
  ) async {
    final cardId = _seminarSynthesisKnowledgeCardId(sessionId);
    if (cardId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removed = await ref
          .read(aiSeminarKnowledgeCardStoreProvider)
          .removeDraftCandidate(cardId);
      if (!mounted) return;
      setState(() => _seminarCardSavedKnowledgeCardIds.remove(cardId));
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? _localizedSeminarCardText(
                    zh: '已撤销知识卡保存。',
                    en: 'KnowledgeCard save undone.',
                  )
                : _localizedSeminarCardText(
                    zh: '这张知识卡已确认或已不存在，不能撤销。',
                    en: 'This KnowledgeCard was already confirmed or removed.',
                  ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _addActiveSeminarRunCardSpacedReview(
    String? sessionId,
  ) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    final flashcardId = _seminarSynthesisReviewFlashcardId(normalizedSessionId);
    if (flashcardId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    final synthesis = runtimeState.synthesis;
    final sourceRefs = _seminarSynthesisKnowledgeCardSourceRefs(runtimeState);
    if (runtimeState.session?.id != normalizedSessionId ||
        synthesis == null ||
        synthesis.summary.trim().isEmpty ||
        sourceRefs.isEmpty) {
      return;
    }
    try {
      await ref.read(spacedReviewStoreProvider).upsertInlineFlashcard(
            flashcardId: flashcardId,
            prompt: _localizedSeminarCardText(
              zh: '复习这场 AI Seminar 的结论',
              en: 'Review this AI Seminar synthesis',
            ),
            answer: synthesis.summary.trim(),
            sourceRefs: sourceRefs,
          );
      if (!mounted) return;
      setState(() => _seminarCardSpacedReviewFlashcardIds.add(flashcardId));
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '已加入复习。',
              en: 'Added to spaced review.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _undoActiveSeminarRunCardSpacedReview(
    String? sessionId,
  ) async {
    final flashcardId = _seminarSynthesisReviewFlashcardId(sessionId);
    if (flashcardId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removed =
          await ref.read(spacedReviewStoreProvider).removeInlineFlashcard(
                flashcardId,
              );
      if (!mounted) return;
      setState(() => _seminarCardSpacedReviewFlashcardIds.remove(flashcardId));
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? _localizedSeminarCardText(
                    zh: '已撤销复习。',
                    en: 'Spaced review undone.',
                  )
                : _localizedSeminarCardText(
                    zh: '这条复习已经有记录或已不存在，不能撤销。',
                    en: 'This review item was already reviewed or removed.',
                  ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _addActiveSeminarRunCardConceptGraph(
    String? sessionId,
  ) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    final nodeId = _seminarSynthesisConceptNodeId(normalizedSessionId);
    if (nodeId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    final synthesis = runtimeState.synthesis;
    final sourceRefs = _seminarSynthesisKnowledgeCardSourceRefs(runtimeState);
    if (runtimeState.session?.id != normalizedSessionId ||
        synthesis == null ||
        synthesis.summary.trim().isEmpty ||
        sourceRefs.isEmpty) {
      return;
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final summary = synthesis.summary.trim();
    try {
      await ref.read(conceptGraphStoreProvider).upsertNode(
            ConceptNode(
              id: nodeId,
              type: ConceptNodeType.claim,
              label: _seminarConceptNodeLabel(summary),
              summary: summary,
              sourceRefs: sourceRefs,
              ownership: AiOutputOwnership.aiGeneratedDraft,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
      if (!mounted) return;
      setState(() => _seminarCardConceptNodeIds.add(nodeId));
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '已加入我的图谱。',
              en: 'Added to my graph.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _undoActiveSeminarRunCardConceptGraph(
    String? sessionId,
  ) async {
    final nodeId = _seminarSynthesisConceptNodeId(sessionId);
    if (nodeId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removed = await ref.read(conceptGraphStoreProvider).removeDraftNode(
            nodeId,
          );
      if (!mounted) return;
      setState(() => _seminarCardConceptNodeIds.remove(nodeId));
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? _localizedSeminarCardText(
                    zh: '已撤销图谱保存。',
                    en: 'Graph save undone.',
                  )
                : _localizedSeminarCardText(
                    zh: '这个图谱节点已确认或已不存在，不能撤销。',
                    en: 'This graph node was already confirmed or removed.',
                  ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _seminarConceptNodeLabel(String summary) {
    final normalized = summary.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 80) return normalized;
    return '${normalized.substring(0, 77)}...';
  }

  List<SourceRef> _seminarSynthesisKnowledgeCardSourceRefs(
    AiSeminarRuntimeState runtimeState,
  ) {
    final synthesis = runtimeState.synthesis;
    if (synthesis == null || synthesis.summary.trim().isEmpty) {
      return const <SourceRef>[];
    }
    final evidenceById = <String, AiSeminarEvidence>{
      for (final evidence in synthesis.evidence)
        if (evidence.id.trim().isNotEmpty) evidence.id.trim(): evidence,
    };
    final refs = <SourceRef>[];
    final seen = <String>{};
    for (final id in synthesis.evidenceRefIds) {
      final evidence = evidenceById[id.trim()];
      if (evidence == null || !evidence.sourceRef.hasEvidence) continue;
      final key = evidence.sourceRef.sourceHash ??
          evidence.sourceRef.jumpLink ??
          '${evidence.sourceRef.bookId}:${evidence.sourceRef.href}:${evidence.sourceRef.cfi}:${evidence.sourceRef.chunkId}:${evidence.sourceRef.sourceTextSnippet}';
      if (!seen.add(key)) continue;
      refs.add(evidence.sourceRef);
    }
    return refs;
  }

  Widget _buildSeminarRunSnapshot(
    String? sessionId,
    AiSeminarRunCardSnapshot snapshot,
    AiSeminarRuntimeState runtimeState,
  ) {
    final allEvidence = snapshot.evidence
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    final evidence = allEvidence.take(3).toList(growable: false);
    final roles = snapshot.roleSummaries.take(4).toList(growable: false);
    final synthesis = snapshot.synthesisSummary?.trim();
    final disagreements = snapshot.disagreements
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final disagreementDetails = snapshot.disagreementDetails
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    final disagreementDetailTexts = disagreementDetails
        .map((item) => item.text.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final legacyOnlyDisagreements = disagreements
        .where((item) => !disagreementDetailTexts.contains(item))
        .toList(growable: false);
    final disagreementTexts = <String>[
      ...disagreementDetailTexts,
      ...legacyOnlyDisagreements,
    ];
    final openQuestions = snapshot.openQuestions
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final availableSubViews = _seminarSnapshotAvailableSubviews(
      evidence: evidence,
      roles: roles,
      synthesis: synthesis,
      disagreements: disagreementTexts,
      openQuestions: openQuestions,
    );
    final selectedSubview = _seminarSnapshotSelectedSubview(
      sessionId,
      availableSubViews,
    );
    final showOverview = selectedSubview == _SeminarRunSnapshotSubview.overview;
    final showTimeline = showOverview && roles.isNotEmpty;
    final showEvidence =
        showOverview || selectedSubview == _SeminarRunSnapshotSubview.evidence;
    final showRoles = selectedSubview == _SeminarRunSnapshotSubview.roles;
    final showSummary =
        showOverview || selectedSubview == _SeminarRunSnapshotSubview.summary;
    final showReview = selectedSubview == _SeminarRunSnapshotSubview.review;
    final showWhiteboard = showOverview ||
        selectedSubview == _SeminarRunSnapshotSubview.whiteboard;
    final showDisagreements =
        selectedSubview == _SeminarRunSnapshotSubview.disagreements;
    final activeSynthesis =
        runtimeState.session?.id == sessionId ? runtimeState.synthesis : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sessionId != null && availableSubViews.length > 2) ...[
          _seminarSnapshotSubviewTabs(
            sessionId: sessionId,
            subviews: availableSubViews,
            selected: selectedSubview,
          ),
          const SizedBox(height: 8),
        ],
        if (showTimeline) ...[
          _seminarSnapshotDiscussionTimeline(roles),
          if ((showEvidence && evidence.isNotEmpty) ||
              (showSummary && synthesis != null && synthesis.isNotEmpty) ||
              disagreementTexts.isNotEmpty ||
              openQuestions.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (showEvidence && evidence.isNotEmpty) ...[
          _seminarSnapshotHeading(
            Icons.fact_check_outlined,
            _localizedSeminarCardText(
              zh: '证据快照',
              en: 'Evidence snapshot',
            ),
          ),
          const SizedBox(height: 6),
          for (final item in evidence) _seminarSnapshotEvidenceTile(item),
        ],
        if (showRoles && roles.isNotEmpty) ...[
          if (showEvidence && evidence.isNotEmpty) const SizedBox(height: 10),
          _seminarSnapshotHeading(
            Icons.forum_outlined,
            _localizedSeminarCardText(
              zh: '角色观点',
              en: 'Role views',
            ),
          ),
          const SizedBox(height: 6),
          for (final role in roles) _seminarSnapshotRoleTile(role),
        ],
        if (showSummary && synthesis != null && synthesis.isNotEmpty) ...[
          if ((showEvidence && evidence.isNotEmpty) ||
              (showRoles && roles.isNotEmpty))
            const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _seminarSnapshotHeading(
                  Icons.auto_awesome_outlined,
                  _localizedSeminarCardText(
                    zh: '研讨总结',
                    en: 'Seminar summary',
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (snapshot.disagreements.isNotEmpty ||
                      disagreementDetails.isNotEmpty)
                    _seminarSnapshotTinyChip(
                      _seminarCountLabel(
                        disagreementTexts.length,
                        zhUnit: '个分歧',
                        enSingular: 'disagreement',
                        enPlural: 'disagreements',
                      ),
                    ),
                  if (snapshot.openQuestions.isNotEmpty)
                    _seminarSnapshotTinyChip(
                      _seminarCountLabel(
                        snapshot.openQuestions.length,
                        zhUnit: '个问题',
                        enSingular: 'question',
                        enPlural: 'questions',
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            synthesis,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.fg(context),
                  height: 1.35,
                ),
          ),
        ],
        if (showDisagreements && disagreementTexts.isNotEmpty) ...[
          _seminarSnapshotHeading(
            Icons.report_problem_outlined,
            _localizedSeminarCardText(
              zh: '分歧视图',
              en: 'Disagreements view',
            ),
          ),
          const SizedBox(height: 6),
          if (disagreementDetails.isNotEmpty)
            _seminarSnapshotDisagreementDetails(disagreementDetails),
          if (legacyOnlyDisagreements.isNotEmpty)
            _seminarSnapshotWhiteboardGroup(
              icon: Icons.report_problem_outlined,
              label: _localizedSeminarCardText(
                zh: '分歧',
                en: 'Disagreements',
              ),
              items: legacyOnlyDisagreements,
            ),
        ],
        if (showReview) ...[
          _seminarSnapshotReviewPreview(
            synthesis: synthesis,
            evidenceCount: allEvidence.length,
            activeSynthesis: activeSynthesis,
          ),
        ],
        if (showWhiteboard &&
            (disagreementTexts.isNotEmpty || openQuestions.isNotEmpty)) ...[
          if ((showEvidence && evidence.isNotEmpty) ||
              (showRoles && roles.isNotEmpty) ||
              (showSummary && synthesis != null))
            const SizedBox(height: 10),
          _seminarSnapshotWhiteboardSection(
            disagreements: disagreementTexts,
            openQuestions: openQuestions,
          ),
        ],
      ],
    );
  }

  List<_SeminarRunSnapshotSubview> _seminarSnapshotAvailableSubviews({
    required List<AiSeminarRunCardEvidenceSnapshot> evidence,
    required List<AiSeminarRunCardRoleSummary> roles,
    required String? synthesis,
    required List<String> disagreements,
    required List<String> openQuestions,
  }) {
    return [
      _SeminarRunSnapshotSubview.overview,
      if (evidence.isNotEmpty) _SeminarRunSnapshotSubview.evidence,
      if (roles.isNotEmpty) _SeminarRunSnapshotSubview.roles,
      if (disagreements.isNotEmpty) _SeminarRunSnapshotSubview.disagreements,
      if (disagreements.isNotEmpty || openQuestions.isNotEmpty)
        _SeminarRunSnapshotSubview.whiteboard,
      if (synthesis != null && synthesis.isNotEmpty)
        _SeminarRunSnapshotSubview.summary,
      if ((synthesis != null && synthesis.isNotEmpty) || evidence.isNotEmpty)
        _SeminarRunSnapshotSubview.review,
    ];
  }

  _SeminarRunSnapshotSubview _seminarSnapshotSelectedSubview(
    String? sessionId,
    List<_SeminarRunSnapshotSubview> available,
  ) {
    final selected =
        sessionId == null ? null : _seminarCardSnapshotSubviews[sessionId];
    if (selected != null && available.contains(selected)) return selected;
    return _SeminarRunSnapshotSubview.overview;
  }

  Widget _seminarSnapshotSubviewTabs({
    required String sessionId,
    required List<_SeminarRunSnapshotSubview> subviews,
    required _SeminarRunSnapshotSubview selected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final subview in subviews) ...[
            ChoiceChip(
              key: ValueKey(
                'seminar-chat-card-snapshot-tab-${subview.id}-$sessionId',
              ),
              label: Text(_seminarSnapshotSubviewLabel(subview)),
              selected: selected == subview,
              onSelected: (_) {
                setState(() {
                  _seminarCardSnapshotSubviews[sessionId] = subview;
                });
              },
            ),
            if (subview != subviews.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  String _seminarSnapshotSubviewLabel(_SeminarRunSnapshotSubview subview) {
    switch (subview) {
      case _SeminarRunSnapshotSubview.overview:
        return _localizedSeminarCardText(zh: '全部', en: 'All');
      case _SeminarRunSnapshotSubview.evidence:
        return _localizedSeminarCardText(zh: '证据', en: 'Evidence');
      case _SeminarRunSnapshotSubview.roles:
        return _localizedSeminarCardText(zh: '角色', en: 'Roles');
      case _SeminarRunSnapshotSubview.disagreements:
        return _localizedSeminarCardText(zh: '分歧', en: 'Disputes');
      case _SeminarRunSnapshotSubview.whiteboard:
        return _localizedSeminarCardText(zh: '白板', en: 'Whiteboard');
      case _SeminarRunSnapshotSubview.summary:
        return _localizedSeminarCardText(zh: '总结', en: 'Summary');
      case _SeminarRunSnapshotSubview.review:
        return _localizedSeminarCardText(zh: '异常', en: 'Triage');
    }
  }

  Widget _seminarSnapshotHeading(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: ClaudePalette.secondary(context)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ClaudePalette.secondary(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }

  Widget _seminarSnapshotEvidenceTile(
    AiSeminarRunCardEvidenceSnapshot evidence,
  ) {
    final title = evidence.title.trim();
    final snippet = evidence.snippet.trim();
    final sourceRef = evidence.sourceRef;
    final sourceIntent = sourceRef == null
        ? null
        : PaperReaderReaderIntent.fromSourceRef(sourceRef);
    final canShowSourceAction = sourceRef != null && sourceRef.hasEvidence;
    final sourceAction = canShowSourceAction
        ? TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 26),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            icon: Icon(
              sourceIntent == null
                  ? Icons.info_outline
                  : Icons.open_in_new_outlined,
              size: 14,
            ),
            label: Text(
              sourceIntent == null
                  ? _localizedSeminarCardText(
                      zh: '来源不可用',
                      en: 'Source unavailable',
                    )
                  : _localizedSeminarCardText(
                      zh: '打开来源',
                      en: 'Open source',
                    ),
            ),
            onPressed: sourceIntent == null
                ? () => showPaperReaderSourceUnavailable(
                      context,
                      [sourceRef],
                      _localizedSeminarCardText(
                        zh: '没有可跳转的来源。',
                        en: 'No jumpable source available.',
                      ),
                    )
                : () => _sourceOpener(
                      ref,
                      sourceIntent.toUri(),
                    ),
          )
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: ClaudePalette.fg(context),
                                ),
                      ),
                    ),
                    if (sourceAction != null) ...[
                      const SizedBox(width: 6),
                      sourceAction,
                    ],
                  ],
                ),
              if (snippet.isNotEmpty) ...[
                if (title.isNotEmpty) const SizedBox(height: 3),
                Text(
                  snippet,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                        height: 1.32,
                      ),
                ),
              ],
              if (title.isEmpty && sourceAction != null) ...[
                if (snippet.isNotEmpty) const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: sourceAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _seminarSnapshotRoleTile(AiSeminarRunCardRoleSummary role) {
    final label = role.label.trim().isNotEmpty
        ? role.label.trim()
        : _seminarRoleFallbackLabel(role.roleId);
    final summary = role.summary.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _seminarRoleIconById(role.roleId),
            size: 16,
            color: ClaudePalette.accent(context),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ClaudePalette.fg(context),
                      ),
                ),
                if (summary.isNotEmpty)
                  Text(
                    summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                          height: 1.32,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seminarSnapshotDiscussionTimeline(
    List<AiSeminarRunCardRoleSummary> roles,
  ) {
    final turns = roles.where((role) => !role.isEmpty).take(4).toList();
    if (turns.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _seminarSnapshotHeading(
          Icons.chat_bubble_outline,
          _localizedSeminarCardText(
            zh: '研讨时间线',
            en: 'Discussion timeline',
          ),
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < turns.length; index += 1)
          _seminarSnapshotTimelineTurn(turns[index], index + 1),
      ],
    );
  }

  Widget _seminarSnapshotTimelineTurn(
    AiSeminarRunCardRoleSummary role,
    int turnNumber,
  ) {
    final label = role.label.trim().isNotEmpty
        ? role.label.trim()
        : _seminarRoleFallbackLabel(role.roleId);
    final evidenceRefs = role.evidenceRefs
        .where((item) => !item.isEmpty)
        .take(2)
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.elevated(context).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _seminarRoleIconById(role.roleId),
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$turnNumber · $label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (role.summary.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        role.summary.trim(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    if (evidenceRefs.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      _seminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '本轮证据',
                          en: 'Evidence used by this turn',
                        ),
                      ),
                      const SizedBox(height: 5),
                      for (final evidence in evidenceRefs)
                        _seminarSnapshotEvidenceTile(evidence),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seminarSnapshotDisagreementDetails(
    List<AiSeminarRunCardDisagreementDetail> details,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final detail in details)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ClaudePalette.divider(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.text.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ClaudePalette.fg(context),
                            height: 1.32,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (detail.roleIds
                        .where((roleId) => roleId.trim().isNotEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      _seminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '关联角色',
                          en: 'Linked roles',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _seminarRoleLabels(detail.roleIds),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                    if (detail.evidenceRefs
                        .where((item) => !item.isEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      _seminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '关联证据',
                          en: 'Linked evidence',
                        ),
                      ),
                      const SizedBox(height: 5),
                      for (final evidence
                          in detail.evidenceRefs.where((item) => !item.isEmpty))
                        _seminarSnapshotEvidenceTile(evidence),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _seminarSnapshotDetailLabel(String label) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ClaudePalette.secondary(context),
            fontWeight: FontWeight.w700,
          ),
    );
  }

  String _seminarRoleLabels(List<String> roleIds) {
    final seen = <String>{};
    final labels = <String>[];
    for (final raw in roleIds) {
      final roleId = raw.trim();
      if (roleId.isEmpty || !seen.add(roleId)) continue;
      labels.add(_seminarRoleFallbackLabel(roleId));
    }
    if (labels.isEmpty) {
      return _localizedSeminarCardText(zh: '未标明角色', en: 'Unlabeled role');
    }
    return labels.join(_isChineseLocale ? '、' : ', ');
  }

  Widget _seminarSnapshotWhiteboardSection({
    required List<String> disagreements,
    required List<String> openQuestions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _seminarSnapshotHeading(
          Icons.dashboard_customize_outlined,
          _localizedSeminarCardText(
            zh: '研讨白板',
            en: 'Shared whiteboard',
          ),
        ),
        const SizedBox(height: 6),
        if (disagreements.isNotEmpty)
          _seminarSnapshotWhiteboardGroup(
            icon: Icons.report_problem_outlined,
            label: _localizedSeminarCardText(
              zh: '分歧',
              en: 'Disagreements',
            ),
            items: disagreements,
          ),
        if (openQuestions.isNotEmpty)
          _seminarSnapshotWhiteboardGroup(
            icon: Icons.help_outline,
            label: _localizedSeminarCardText(
              zh: '开放问题',
              en: 'Open questions',
            ),
            items: openQuestions,
          ),
      ],
    );
  }

  Widget _seminarSnapshotReviewPreview({
    required String? synthesis,
    required int evidenceCount,
    AiSeminarSynthesis? activeSynthesis,
  }) {
    final summary = synthesis?.trim() ?? '';
    final canPreviewHandoff = activeSynthesis != null &&
        activeSynthesis.readyForReview &&
        activeSynthesis.hasTraceableHandoff;
    final candidateCardItems = canPreviewHandoff
        ? _seminarReviewCandidateCardItems(activeSynthesis)
        : const <_SeminarReviewPreviewItem>[];
    final reviewQuestions = canPreviewHandoff
        ? _seminarReviewQuestionItems(activeSynthesis)
        : const <_SeminarReviewPreviewItem>[];
    final reviewReasons = canPreviewHandoff
        ? _seminarReviewReasonTexts(activeSynthesis)
        : const <String>[];
    final candidateCardCount =
        canPreviewHandoff ? activeSynthesis.candidateCards.length : 0;
    final flashcardCandidateCount = reviewQuestions.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _seminarSnapshotHeading(
              Icons.fact_check_outlined,
              _localizedSeminarCardText(
                zh: '异常处理预览',
                en: 'Exception triage preview',
              ),
            ),
            const SizedBox(height: 8),
            _seminarSnapshotReviewLine(
              Icons.outbox_outlined,
              _localizedSeminarCardText(
                zh: '只在低置信、冲突或来源异常时发送到 Review Inbox',
                en: 'Send to Review Inbox only for low-confidence, conflict, or broken-source cases',
              ),
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              _seminarSnapshotDetailLabel(
                _localizedSeminarCardText(
                  zh: '综合总结',
                  en: 'Synthesis',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                summary,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.fg(context),
                      height: 1.35,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            _seminarSnapshotReviewLine(
              Icons.link_outlined,
              _localizedSeminarCardText(
                zh: '可追踪证据：$evidenceCount 条',
                en: evidenceCount == 1
                    ? 'Traceable evidence: 1 source'
                    : 'Traceable evidence: $evidenceCount sources',
              ),
            ),
            if (reviewReasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              _seminarSnapshotDetailLabel(
                _localizedSeminarCardText(
                  zh: '异常原因',
                  en: 'Review reasons',
                ),
              ),
              const SizedBox(height: 4),
              for (final reason in reviewReasons) ...[
                _seminarSnapshotReviewLine(
                  Icons.warning_amber_outlined,
                  reason,
                ),
                const SizedBox(height: 4),
              ],
            ],
            if (canPreviewHandoff) ...[
              const SizedBox(height: 8),
              _seminarSnapshotDetailLabel(
                _localizedSeminarCardText(
                  zh: '异常送审内容',
                  en: 'Exception Review payload',
                ),
              ),
              const SizedBox(height: 4),
              _seminarSnapshotReviewLine(
                Icons.summarize_outlined,
                _localizedSeminarCardText(
                  zh: '综合总结：1 项',
                  en: 'Synthesis: 1 item',
                ),
              ),
              const SizedBox(height: 4),
              _seminarSnapshotReviewLine(
                Icons.style_outlined,
                _localizedSeminarCardText(
                  zh: '知识卡候选：$candidateCardCount 项',
                  en: candidateCardCount == 1
                      ? 'KnowledgeCard candidates: 1 item'
                      : 'KnowledgeCard candidates: $candidateCardCount items',
                ),
              ),
              if (candidateCardItems.isNotEmpty) ...[
                const SizedBox(height: 3),
                _seminarSnapshotReviewItems(
                  label: _localizedSeminarCardText(
                    zh: '知识卡候选明细',
                    en: 'KnowledgeCard candidate details',
                  ),
                  evidenceLabel: _localizedSeminarCardText(
                    zh: '候选证据',
                    en: 'Candidate evidence',
                  ),
                  items: candidateCardItems,
                ),
              ],
              const SizedBox(height: 4),
              _seminarSnapshotReviewLine(
                Icons.quiz_outlined,
                _localizedSeminarCardText(
                  zh: '复习候选：$flashcardCandidateCount 项',
                  en: flashcardCandidateCount == 1
                      ? 'Spaced Review candidates: 1 item'
                      : 'Spaced Review candidates: $flashcardCandidateCount items',
                ),
              ),
              if (reviewQuestions.isNotEmpty) ...[
                const SizedBox(height: 3),
                _seminarSnapshotReviewItems(
                  label: _localizedSeminarCardText(
                    zh: '复习候选明细',
                    en: 'Spaced Review candidate details',
                  ),
                  evidenceLabel: _localizedSeminarCardText(
                    zh: '综合证据',
                    en: 'Synthesis evidence',
                  ),
                  items: reviewQuestions,
                ),
              ],
            ],
            const SizedBox(height: 6),
            Text(
              _localizedSeminarCardText(
                zh: '普通学习保存请优先使用知识卡、复习或我的图谱。',
                en: 'For normal learning saves, use KnowledgeCard, Spaced Review, or My Graph first.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.32,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _seminarReviewReasonTexts(AiSeminarSynthesis synthesis) {
    final disagreementCount = synthesis.disagreements
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .length;
    final cardCount = synthesis.candidateCards
        .map((item) => item.text.trim())
        .where((item) => item.isNotEmpty)
        .length;
    final reviewQuestionCount = synthesis.candidateReviewQuestions
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .length;

    return [
      if (disagreementCount > 0)
        _localizedSeminarCardText(
          zh: '存在未解决分歧：$disagreementCount 项',
          en: disagreementCount == 1
              ? 'Unresolved disagreements: 1 item'
              : 'Unresolved disagreements: $disagreementCount items',
        ),
      if (cardCount > 0)
        _localizedSeminarCardText(
          zh: '包含知识卡候选：$cardCount 项',
          en: cardCount == 1
              ? 'KnowledgeCard candidates included: 1 item'
              : 'KnowledgeCard candidates included: $cardCount items',
        ),
      if (reviewQuestionCount > 0)
        _localizedSeminarCardText(
          zh: '包含复习候选：$reviewQuestionCount 项',
          en: reviewQuestionCount == 1
              ? 'Spaced Review candidates included: 1 item'
              : 'Spaced Review candidates included: $reviewQuestionCount items',
        ),
    ];
  }

  List<_SeminarReviewPreviewItem> _seminarReviewCandidateCardItems(
    AiSeminarSynthesis synthesis,
  ) {
    final evidenceById = <String, AiSeminarEvidence>{
      for (final item in synthesis.evidence)
        if (item.id.trim().isNotEmpty) item.id.trim(): item,
    };
    return synthesis.candidateCards
        .map((card) {
          final title = card.text.trim();
          final evidenceRefs = card.evidenceRefIds
              .map((id) => evidenceById[id.trim()])
              .whereType<AiSeminarEvidence>()
              .where((item) => item.isTraceable)
              .take(2)
              .map(
                (item) => AiSeminarRunCardEvidenceSnapshot(
                  id: item.id,
                  title: _seminarEvidenceSnapshotTitle(item),
                  snippet: _seminarEvidenceSnapshotSnippet(item),
                  sourceRef: item.sourceRef,
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false);
          return _SeminarReviewPreviewItem(
            text: title,
            evidenceRefs: evidenceRefs,
          );
        })
        .where((item) => !item.isEmpty)
        .toList(growable: false);
  }

  List<_SeminarReviewPreviewItem> _seminarReviewQuestionItems(
    AiSeminarSynthesis synthesis,
  ) {
    final evidenceById = <String, AiSeminarEvidence>{
      for (final item in synthesis.evidence)
        if (item.id.trim().isNotEmpty) item.id.trim(): item,
    };
    final synthesisEvidenceRefs = synthesis.evidenceRefIds
        .map((id) => evidenceById[id.trim()])
        .whereType<AiSeminarEvidence>()
        .where((item) => item.isTraceable)
        .take(2)
        .map(
          (item) => AiSeminarRunCardEvidenceSnapshot(
            id: item.id,
            title: _seminarEvidenceSnapshotTitle(item),
            snippet: _seminarEvidenceSnapshotSnippet(item),
            sourceRef: item.sourceRef,
          ),
        )
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    final seen = <String>{};
    final items = <_SeminarReviewPreviewItem>[];
    for (final raw in synthesis.candidateReviewQuestions) {
      final question = raw.trim();
      if (question.isEmpty) continue;
      if (!seen.add(question.toLowerCase())) continue;
      items.add(
        _SeminarReviewPreviewItem(
          text: question,
          evidenceRefs: synthesisEvidenceRefs,
        ),
      );
    }
    return items;
  }

  Widget _seminarSnapshotReviewItems({
    required String label,
    required String evidenceLabel,
    required List<_SeminarReviewPreviewItem> items,
  }) {
    final visibleItems = items.take(3).toList(growable: false);
    final remainingCount = items.length - visibleItems.length;
    return Padding(
      padding: const EdgeInsets.only(left: 21),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _seminarSnapshotDetailLabel(label),
          const SizedBox(height: 3),
          for (final item in visibleItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                            ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  if (item.evidenceRefs.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _seminarSnapshotDetailLabel(
                            evidenceLabel,
                          ),
                          const SizedBox(height: 5),
                          for (final evidence in item.evidenceRefs)
                            _seminarSnapshotEvidenceTile(evidence),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (remainingCount > 0)
            Text(
              _localizedSeminarCardText(
                zh: '还有 $remainingCount 项',
                en: remainingCount == 1
                    ? '1 more item'
                    : '$remainingCount more items',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.3,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _seminarSnapshotReviewLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: ClaudePalette.accent(context)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                  height: 1.32,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  Widget _seminarSnapshotWhiteboardGroup({
    required IconData icon,
    required String label,
    required List<String> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: ClaudePalette.accent(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                            ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seminarSnapshotTinyChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.62),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ClaudePalette.fg(context),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  IconData _seminarRoleIconById(String roleId) {
    switch (roleId.trim()) {
      case 'critical':
        return Icons.report_problem_outlined;
      case 'supportive':
        return Icons.thumb_up_alt_outlined;
      case 'verifier':
        return Icons.verified_outlined;
      case 'synthesizer':
        return Icons.auto_awesome_outlined;
      default:
        return Icons.person_outline;
    }
  }

  String _seminarRoleFallbackLabel(String roleId) {
    switch (roleId.trim()) {
      case 'critical':
        return _localizedSeminarCardText(zh: '批判者', en: 'Critical');
      case 'supportive':
        return _localizedSeminarCardText(zh: '支持者', en: 'Supportive');
      case 'verifier':
        return _localizedSeminarCardText(zh: '验证者', en: 'Verifier');
      case 'synthesizer':
        return _localizedSeminarCardText(zh: '综合者', en: 'Synthesizer');
      default:
        return roleId.trim().isEmpty ? 'Role' : roleId.trim();
    }
  }

  String _seminarCountLabel(
    int count, {
    required String zhUnit,
    required String enSingular,
    required String enPlural,
  }) {
    if (_isChineseLocale) return '$count $zhUnit';
    return count == 1 ? '1 $enSingular' : '$count $enPlural';
  }

  List<Widget> _seminarMetaChips(AiSeminarRunCardMeta card) {
    final l10n = L10n.of(context);
    final chips = <Widget>[
      _seminarMetaChip(
        Icons.flag_outlined,
        _seminarStatusLabel(card.status, l10n),
      ),
      _seminarMetaChip(
        Icons.groups_2_outlined,
        _seminarRoleCountLabel(card.roleIds.length),
      ),
      _seminarMetaChip(
        Icons.manage_search_outlined,
        _seminarEvidenceScopeSummary(card.evidenceScopeIds, l10n),
      ),
    ];
    if (card.sourceRefCount > 0) {
      chips.add(
        _seminarMetaChip(
          Icons.link_outlined,
          _seminarSourceCountLabel(card.sourceRefCount),
        ),
      );
    }
    if (card.writeRequiresApproval) {
      chips.add(
        _seminarMetaChip(
          Icons.fact_check_outlined,
          _localizedSeminarCardText(
            zh: '写入需确认',
            en: 'Approval before write',
          ),
        ),
      );
    }
    if (card.allowWeb) {
      chips.add(
        _seminarMetaChip(
          Icons.public_outlined,
          _localizedSeminarCardText(
            zh: '允许联网',
            en: 'Web allowed',
          ),
        ),
      );
    }
    if (card.maxRounds > 1) {
      chips.add(
        _seminarMetaChip(
          Icons.repeat_outlined,
          _localizedSeminarCardText(
            zh: '最多 ${card.maxRounds} 轮',
            en: 'Up to ${card.maxRounds} rounds',
          ),
        ),
      );
    }
    return chips;
  }

  Widget _seminarMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: ClaudePalette.accentTint(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: ClaudePalette.accent(context),
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.52,
            ),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ClaudePalette.fg(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _seminarStatusLabel(String status, L10n l10n) {
    switch (status) {
      case 'draft':
        return l10n.seminarRunStatusDraft;
      case 'running':
        return l10n.seminarRunStatusRunning;
      case 'completed':
        return l10n.seminarRunStatusCompleted;
      case 'needs-evidence':
        return l10n.seminarRunStatusNeedsEvidence;
      case 'cancelled':
        return l10n.seminarRunStatusCancelled;
      case 'failed':
        return l10n.seminarRunStatusFailed;
      case 'ready':
      default:
        return _localizedSeminarCardText(
          zh: '待开始',
          en: 'Ready',
        );
    }
  }

  String _seminarRoleCountLabel(int count) {
    final safeCount = count <= 0 ? 3 : count;
    return _localizedSeminarCardText(
      zh: '$safeCount 个角色',
      en: '$safeCount roles',
    );
  }

  String _seminarEvidenceScopeSummary(
    List<String> scopeIds,
    L10n l10n,
  ) {
    final safeScopeIds =
        scopeIds.isEmpty ? const <String>['current-book'] : scopeIds;
    final separator = _isChineseLocale ? '、' : ', ';
    final labels = safeScopeIds
        .map((scopeId) => _seminarEvidenceScopeLabel(scopeId, l10n))
        .toList(growable: false)
        .join(separator);
    return _localizedSeminarCardText(
      zh: '证据：$labels',
      en: 'Evidence: $labels',
    );
  }

  String _seminarEvidenceScopeLabel(String scopeId, L10n l10n) {
    switch (scopeId) {
      case 'current-chapter':
        return l10n.seminarEvidenceScopeCurrentChapter;
      case 'current-book':
        return l10n.seminarEvidenceScopeCurrentBook;
      case 'library':
        return l10n.seminarEvidenceScopeLibrary;
      case 'notes':
        return l10n.seminarEvidenceScopeNotes;
      case 'memory':
        return l10n.seminarEvidenceScopeMemory;
      case 'concept-graph':
        return l10n.seminarEvidenceScopeConceptGraph;
      default:
        return scopeId;
    }
  }

  String _seminarSourceCountLabel(int count) {
    return _localizedSeminarCardText(
      zh: '$count 条来源',
      en: count == 1 ? '1 source' : '$count sources',
    );
  }

  String _localizedSeminarCardText({
    required String zh,
    required String en,
  }) {
    return _isChineseLocale ? zh : en;
  }

  bool get _isChineseLocale =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

  Widget _buildUserMessageItem(_UserChatItem item) {
    final content = _extractUserTextFromHuman(item.message);
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.8;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: ClaudePalette.accentTint(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildScaledMessageContent(
                        _buildHumanMessageBody(item.message)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _showEditUserMessageDialog(
                            item.index,
                            item.message,
                          ),
                          child: Text(L10n.of(context).commonEdit),
                        ),
                        TextButton(
                          onPressed: () => _copyPlainText(content),
                          child: Text(L10n.of(context).commonCopy),
                        ),
                        _buildMessageMemoryMenu(
                          text: content,
                          sourceType: 'chat',
                          messageNodeId: 'user:${item.index}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantGroupItem(
    _AssistantGroupChatItem item, {
    required int? lastHumanIndex,
    required ChatMessage? lastMessage,
  }) {
    var selected = _selectedVariantByUserIndex[item.groupKey] ??
        (item.variants.length - 1);
    if (selected < 0) selected = 0;
    if (selected >= item.variants.length) selected = item.variants.length - 1;

    final message = item.variants[selected];
    final content = message.contentAsString;
    final isStreaming =
        ref.watch(aiChatStreamingProvider) && identical(lastMessage, message);

    final canNavigateVariants =
        item.variants.length > 1 && !_isStreaming && !isStreaming;

    final isLastTurn =
        item.userIndex != null && item.userIndex == lastHumanIndex;
    final assistantReaderSourceRef = item.userIndex == null
        ? null
        : _readerSourceRefForUserIndex(item.userIndex!);
    final assistantSourceStatus = _knowledgeCardSourceStatus(
      readerSourceRef: assistantReaderSourceRef,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildScaledMessageContent(
            _buildAssistantSections(content, isStreaming),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              if (item.variants.length > 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 18),
                      onPressed: canNavigateVariants && selected > 0
                          ? () {
                              setState(() {
                                _selectedVariantByUserIndex[item.groupKey] =
                                    selected - 1;
                              });
                            }
                          : null,
                    ),
                    Text('${selected + 1}/${item.variants.length}'),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 18),
                      onPressed: canNavigateVariants &&
                              selected < item.variants.length - 1
                          ? () {
                              setState(() {
                                _selectedVariantByUserIndex[item.groupKey] =
                                    selected + 1;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              if (item.userIndex != null)
                TextButton(
                  onPressed: () => _confirmRegenerateFromUserIndex(
                    item.userIndex!,
                    isLastTurn: isLastTurn,
                  ),
                  child: Text(L10n.of(context).aiRegenerate),
                ),
              TextButton(
                onPressed: () => _copyMessageContent(content),
                child: Text(L10n.of(context).commonCopy),
              ),
              _buildKnowledgeCardSourceStatusChip(assistantSourceStatus),
              TextButton(
                onPressed: isStreaming
                    ? null
                    : () => _handleAssistantKnowledgeCardAction(
                          answer: _assistantMemoryText(content),
                          userPrompt: item.userIndex == null
                              ? null
                              : _humanTextAt(
                                  ref.read(aiChatProvider).asData?.value ??
                                      const <ChatMessage>[],
                                  item.userIndex!,
                                ),
                          messageNodeId:
                              'assistant-group:${item.groupKey}:$selected',
                          readerSourceRef: assistantReaderSourceRef,
                        ),
                child: Text(L10n.of(context).contextMenuKnowledgeCard),
              ),
              _buildMessageMemoryMenu(
                text: _assistantMemoryText(content),
                sourceType: 'chat',
                messageNodeId: 'assistant-group:${item.groupKey}:$selected',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildCopyableText(ParsedReasoning parsed, String fallback) {
    final buffer = StringBuffer();
    var hasWrittenSection = false;

    void startSection() {
      if (hasWrittenSection) {
        buffer.writeln();
      } else {
        hasWrittenSection = true;
      }
    }

    // void appendField(String label, String? value) {
    //   final trimmed = value?.trim();
    //   if (trimmed != null && trimmed.isNotEmpty) {
    //     buffer.writeln('$label: $trimmed');
    //   }
    // }

    for (final entry in parsed.timeline) {
      switch (entry.type) {
        case ParsedReasoningEntryType.reply:
          final text = entry.text?.trim();
          if (text != null && text.isNotEmpty) {
            startSection();
            buffer.writeln(text);
          }
          break;
        case ParsedReasoningEntryType.tool:
          // final step = entry.toolStep;
          // if (step != null) {
          //   startSection();
          //   buffer.writeln('[${step.name} (${step.status})]');
          //   appendField('Input', step.input);
          //   appendField('Output', step.output);
          //   appendField('Error', step.error);
          // }
          break;
      }
    }

    final copyText = buffer.toString().trimRight();
    if (copyText.isEmpty) {
      return fallback;
    }
    return copyText;
  }

  /// Walk the raw assistant content top-to-bottom and produce a chronological
  /// list of inline parts (text / thinking / tool). Render-only; the original
  /// model content is never mutated.
  List<_AssistantPart> _splitIntoParts(String content) {
    final parts = <_AssistantPart>[];
    final thinkRegex = RegExp(r'<think>([\s\S]*?)<\/think>');

    void emitNonThink(String chunk) {
      if (chunk.isEmpty) return;
      // Reuse the existing reasoning parser for the non-think slice so that
      // `<tool-step .../>` tags are extracted in order alongside the
      // surrounding reply text.
      final parsed = parseReasoningContent(chunk);
      for (final entry in parsed.timeline) {
        if (entry.type == ParsedReasoningEntryType.reply) {
          final text = (entry.text ?? '').trim();
          if (text.isEmpty) continue;
          parts.add(_TextPart(entry.text!));
        } else {
          final step = entry.toolStep;
          if (step != null) parts.add(_ToolPart(step));
        }
      }
    }

    var cursor = 0;
    for (final match in thinkRegex.allMatches(content)) {
      if (match.start > cursor) {
        emitNonThink(content.substring(cursor, match.start));
      }
      final thinkText = (match.group(1) ?? '').trim();
      if (thinkText.isNotEmpty) {
        parts.add(_ThinkingPart(thinkText));
      }
      cursor = match.end;
    }
    if (cursor < content.length) {
      emitNonThink(content.substring(cursor));
    }
    return parts;
  }

  Widget _buildAssistantSections(String content, bool isStreaming) {
    final parts = _splitIntoParts(content);
    final children = <Widget>[];

    if (parts.isEmpty) {
      children.add(
        isStreaming
            ? Skeletonizer.zone(child: Bone.multiText())
            : const SizedBox.shrink(),
      );
    } else {
      for (final part in parts) {
        switch (part) {
          case _TextPart(:final md):
            children.add(StyledMarkdown(data: md, selectable: true));
          case _ThinkingPart(:final text):
            children.add(_buildInlineThinking(text));
          case _ToolPart(:final step):
            children.add(
              PTCollapsibleCard(
                icon: Icons.build_outlined,
                title: AiToolRegistry.displayNameForId(step.name,
                    l10n: L10n.of(context)),
                subtitle: step.name,
                iconTint: ToolTileBase.statusColorFor(step.status, context),
                body: _buildToolTile(step),
              ),
            );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildInlineThinking(String text) {
    return PTCollapsibleCard(
      icon: Icons.psychology_outlined,
      title: L10n.of(context).aiSectionThinking,
      iconTint: ClaudePalette.tertiary(context),
      body: Text(
        text,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          fontSize: 13,
          color: ClaudePalette.secondary(context),
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildToolTile(ParsedToolStep step) {
    if (step.name == 'bookshelf_organize') {
      return OrganizeBookshelfStepTile(step: step);
    }
    if (step.name == 'mindmap_draw') {
      return MindmapStepTile(step: step);
    }
    if (step.name == 'apply_book_tags') {
      return ApplyBookTagsStepTile(step: step);
    }
    return ToolStepTile(step: step, contentOnly: true);
  }

  void _showFontScaleSheet() {
    final l10n = L10n.of(context);
    const minScale = 0.8;
    const maxScale = 1.4;

    // Use a dialog instead of a bottom sheet.
    //
    // The AI chat itself can be hosted inside a bottom sheet (iPhone/iPad sheet
    // mode). Stacking a sheet-on-sheet may auto-dismiss on some platforms.
    double scale = Prefs().aiChatFontScale.clamp(minScale, maxScale);

    PTDialog.show<void>(
      context,
      title: l10n.font,
      content: SizedBox(
        width: 320,
        child: StatefulBuilder(
          builder: (context, setModalState) {
            void update(double next) {
              final clamped = next.clamp(minScale, maxScale).toDouble();
              setModalState(() {
                scale = clamped;
              });
              Prefs().aiChatFontScale = clamped;
              // Force rebuild to apply scale immediately.
              setState(() {});
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${(scale * 100).round()}%',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => update(1.0),
                      child: Text(l10n.commonReset),
                    ),
                  ],
                ),
                Slider(
                  value: scale,
                  min: minScale,
                  max: maxScale,
                  divisions: 12,
                  label: '${(scale * 100).round()}%',
                  onChanged: update,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonOk,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // --- Multimodal user message helpers ---

  static const String _textFileAttachmentPrefix = '[[file:';
  static const String _textFileAttachmentSuffix = ']]';

  String _extractUserTextFromHuman(HumanChatMessage message) {
    final content = message.content;
    if (content is ChatMessageContentText) {
      return content.text;
    }

    if (content is ChatMessageContentMultiModal) {
      final buffer = StringBuffer();
      for (final part in content.parts) {
        if (part is! ChatMessageContentText) continue;
        final text = part.text;
        if (text.startsWith(_textFileAttachmentPrefix)) {
          continue; // Hide file contents from chat bubble text.
        }
        final trimmed = text.trim();
        if (trimmed.isEmpty) continue;
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(trimmed);
      }
      return buffer.toString();
    }

    // Image-only message.
    return '';
  }

  String? _humanTextAt(List<ChatMessage> messages, int index) {
    if (index < 0 || index >= messages.length) return null;
    final message = messages[index];
    if (message is! HumanChatMessage) return null;
    final text = _extractUserTextFromHuman(message).trim();
    return text.isEmpty ? null : text;
  }

  List<_TextFileAttachmentInfo> _extractTextFilesFromHuman(
    HumanChatMessage message,
  ) {
    final content = message.content;
    if (content is! ChatMessageContentMultiModal) {
      return const [];
    }

    final out = <_TextFileAttachmentInfo>[];
    for (final part in content.parts) {
      if (part is! ChatMessageContentText) continue;
      final text = part.text;
      if (!text.startsWith(_textFileAttachmentPrefix)) continue;

      final suffixIndex = text.indexOf(_textFileAttachmentSuffix);
      if (suffixIndex <= _textFileAttachmentPrefix.length) continue;

      final filename =
          text.substring(_textFileAttachmentPrefix.length, suffixIndex).trim();
      final body =
          text.substring(suffixIndex + _textFileAttachmentSuffix.length);
      final normalizedBody = body.startsWith('\n') ? body.substring(1) : body;

      out.add(
        _TextFileAttachmentInfo(
          filename: filename.isEmpty ? 'text' : filename,
          text: normalizedBody,
        ),
      );
    }
    return out;
  }

  List<AttachmentItem> _extractAttachmentItemsFromHuman(
      HumanChatMessage message) {
    final items = <AttachmentItem>[];
    final files = _extractTextFilesFromHuman(message);
    for (final f in files) {
      items.add(
        AttachmentItem.textFile(
          filename: f.filename,
          bytes: Uint8List.fromList(utf8.encode(f.text)),
          text: f.text,
        ),
      );
    }

    final content = message.content;
    final images = <ChatMessageContentImage>[];
    if (content is ChatMessageContentImage) {
      images.add(content);
    } else if (content is ChatMessageContentMultiModal) {
      images.addAll(content.parts.whereType<ChatMessageContentImage>());
    }

    for (final imgPart in images) {
      try {
        final decoded = base64Decode(imgPart.data);
        items.add(AttachmentItem.image(bytes: decoded, base64: imgPart.data));
      } catch (_) {
        // ignore malformed image payloads
      }
    }

    return items;
  }

  List<Uint8List> _extractImagesFromHuman(HumanChatMessage message) {
    final content = message.content;
    final images = <ChatMessageContentImage>[];

    if (content is ChatMessageContentImage) {
      images.add(content);
    } else if (content is ChatMessageContentMultiModal) {
      images.addAll(content.parts.whereType<ChatMessageContentImage>());
    }

    final out = <Uint8List>[];
    for (final imgPart in images) {
      final key = imgPart.data;

      // LRU-ish: if present, move to the end.
      final cached = _decodedImageCache.remove(key);
      if (cached != null) {
        _decodedImageCache[key] = cached;
        out.add(cached);
        continue;
      }

      try {
        final decoded = base64Decode(key);
        _decodedImageCache[key] = decoded;
        out.add(decoded);

        while (_decodedImageCache.length > _decodedImageCacheMaxEntries) {
          _decodedImageCache.remove(_decodedImageCache.keys.first);
        }
      } catch (_) {
        // ignore
      }
    }
    return out;
  }

  Future<void> _showTextFileAttachmentActions(_TextFileAttachmentInfo f) async {
    final l10n = L10n.of(context);

    final choice = await PTDialog.show<String>(
      context,
      title: f.filename,
      content: SingleChildScrollView(
        child: Text(
          f.text.length > 2000 ? '${f.text.substring(0, 2000)}…' : f.text,
          style: TextStyle(
            fontSize: 14,
            color: ClaudePalette.secondary(context),
            height: 1.35,
          ),
        ),
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        PTDialogAction(
          label: l10n.exportAndImportImport,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop('import'),
        ),
      ],
    );

    if (choice == 'import') {
      await _importTextFileAttachmentToBookshelf(f);
    }
  }

  Future<void> _importTextFileAttachmentToBookshelf(
    _TextFileAttachmentInfo f,
  ) async {
    try {
      final cacheDir = await getAnxCacheDir();
      final dir = Directory(p.join(cacheDir.path, 'ai_text_import'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final safe = f.filename
          .replaceAll(RegExp(r'[\\/\n\r\t]'), '_')
          .replaceAll(':', '_');
      final base = safe.replaceAll(RegExp(r'\.[^.]+$'), '');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outName = '${base.isEmpty ? 'text' : base}_$ts.txt';
      final outFile = File(p.join(dir.path, outName));

      await outFile.writeAsString(f.text, encoding: utf8);

      importBookList([outFile], context, ref);
      AnxToast.show(L10n.of(context).exportAndImportImport);
    } catch (e) {
      AnxToast.show(e.toString());
    }
  }

  void _showImageGallery(
    List<Uint8List> images, {
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => _AiImageGalleryDialog(
        images: images,
        initialIndex: initialIndex,
      ),
    );
  }

  Widget _buildEditableAttachmentChip(
    AttachmentItem attachment, {
    required VoidCallback onRemove,
    VoidCallback? onPreview,
  }) {
    if (attachment.type == AttachmentType.image) {
      return Stack(
        children: [
          GestureDetector(
            onTap: onPreview,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                attachment.bytes,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    return InputChip(
      avatar: const Icon(Icons.description, size: 18),
      label: Text(
        attachment.filename ?? 'text',
        overflow: TextOverflow.ellipsis,
      ),
      onDeleted: onRemove,
    );
  }

  Widget _buildHumanMessageBody(HumanChatMessage message) {
    final text = _extractUserTextFromHuman(message);
    final files = _extractTextFilesFromHuman(message);
    final images = _extractImagesFromHuman(message);

    final isLongMessage = text.length > 300;

    final children = <Widget>[];

    if (text.isNotEmpty) {
      children.add(_buildCollapsibleText(text, isLongMessage));
    }

    if (files.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in files)
              Tooltip(
                message: f.text.length > 400
                    ? '${f.text.substring(0, 400)}…'
                    : f.text,
                child: ActionChip(
                  avatar: const Icon(Icons.description, size: 18),
                  label: Text(
                    f.filename,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => _showTextFileAttachmentActions(f),
                ),
              ),
          ],
        ),
      );
    }

    if (images.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '图片 ${images.length} 张',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      );
      children.add(
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final bytes = images[index];
              return GestureDetector(
                onTap: () => _showImageGallery(images, initialIndex: index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      Image.memory(
                        bytes,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemCount: images.length,
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildCollapsibleText(String text, bool isLongMessage) {
    final style = _messageBodyTextStyle(context);
    if (!isLongMessage) {
      return SelectableText(
        text,
        style: style,
        selectionControls: MaterialTextSelectionControls(),
      );
    }
    return _CollapsibleText(text: text, style: style);
  }
}

sealed class _AssistantPart {
  const _AssistantPart();
}

class _TextPart extends _AssistantPart {
  const _TextPart(this.md);
  final String md;
}

class _ThinkingPart extends _AssistantPart {
  const _ThinkingPart(this.text);
  final String text;
}

class _ToolPart extends _AssistantPart {
  const _ToolPart(this.step);
  final ParsedToolStep step;
}

class _EditUserMessageResult {
  const _EditUserMessageResult({
    required this.text,
    required this.attachments,
  });

  final String text;
  final List<AttachmentItem> attachments;
}

class _TextFileAttachmentInfo {
  const _TextFileAttachmentInfo({
    required this.filename,
    required this.text,
  });

  final String filename;
  final String text;
}

class _AiImageGalleryDialog extends StatefulWidget {
  const _AiImageGalleryDialog({
    required this.images,
    this.initialIndex = 0,
  });

  final List<Uint8List> images;
  final int initialIndex;

  @override
  State<_AiImageGalleryDialog> createState() => _AiImageGalleryDialogState();
}

class _AiImageGalleryDialogState extends State<_AiImageGalleryDialog> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _controller,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: MemoryImage(widget.images[index]),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                heroAttributes:
                    PhotoViewHeroAttributes(tag: 'ai-chat-image-$index'),
              );
            },
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (context, _) => const Center(
              child: CircularProgressIndicator(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${widget.images.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

sealed class _ChatItem {
  const _ChatItem();
}

class _UserChatItem extends _ChatItem {
  const _UserChatItem({
    required this.index,
    required this.message,
  });

  final int index;
  final HumanChatMessage message;
}

class _AssistantGroupChatItem extends _ChatItem {
  const _AssistantGroupChatItem({
    required this.groupKey,
    required this.userIndex,
    required this.variants,
  });

  /// Stable within the current in-memory message list.
  ///
  /// - For normal turns: equals [userIndex].
  /// - For orphan assistant groups: negative.
  final int groupKey;

  /// The index of the user message this assistant group belongs to.
  ///
  /// If null, this is an orphan assistant group.
  final int? userIndex;

  final List<AIChatMessage> variants;
}

class _SeminarReviewPreviewItem {
  const _SeminarReviewPreviewItem({
    required this.text,
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
  });

  final String text;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;

  bool get isEmpty => text.trim().isEmpty && evidenceRefs.isEmpty;
}

class _AiChatKnowledgeSourceStatus {
  const _AiChatKnowledgeSourceStatus({
    required this.label,
    required this.tooltip,
    required this.traceable,
  });

  final String label;
  final String tooltip;
  final bool traceable;
}

class _CollapsibleText extends StatefulWidget {
  const _CollapsibleText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isExpanded)
          SelectableText(
            widget.text,
            style: widget.style,
            selectionControls: MaterialTextSelectionControls(),
          )
        else
          Stack(
            children: [
              SelectableText(
                widget.text.substring(0, 300),
                style: widget.style,
                selectionControls: MaterialTextSelectionControls(),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainer
                            .withValues(alpha: 0),
                        Theme.of(context).colorScheme.surfaceContainer,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        TextButton(
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Text(_isExpanded
              ? L10n.of(context).aiHintCollapse
              : L10n.of(context).aiHintExpand),
        ),
      ],
    );
  }
}
