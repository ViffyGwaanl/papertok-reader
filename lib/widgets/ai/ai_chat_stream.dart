import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/ai_reasoning_panel.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:langchain_core/chat_models.dart';

class AiChatStream extends ConsumerStatefulWidget {
  const AiChatStream(
      {super.key, this.initialMessage, this.sendImmediate = false});

  final String? initialMessage;
  final bool sendImmediate;

  @override
  ConsumerState<AiChatStream> createState() => AiChatStreamState();
}

class AiChatStreamState extends ConsumerState<AiChatStream> {
  final TextEditingController inputController = TextEditingController();
  Stream<List<ChatMessage>>? _messageStream;
  StreamController<List<ChatMessage>>? _messageController;
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  final ScrollController _scrollController = ScrollController();
  final Map<int, bool> _expandedState = <int, bool>{};
  final Set<int> _userControlled = <int>{};
  bool _isStreaming = false;
  late List<AiServiceOption> _serviceOptions;
  late String _selectedServiceId;
  late List<String> _suggestedPrompts;

  static const List<String> _starterPrompts = [
    'What books did I read in the last 7 days?',
    'Summarize my latest reading session.',
    'Which books have the highest reading progress?',
    'List all notes I took yesterday.',
    'Show unread books in my shelf.',
    'Recommend a book based on my recent reads.',
    'Summarize today\'s highlights.',
    'Which book took the most time this week?',
    'Give me a quote from my notes.',
    'What should I read next?',
  ];

  List<Map<String, String>> _getQuickPrompts(BuildContext context) {
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

  @override
  void initState() {
    super.initState();
    _serviceOptions = buildDefaultAiServices();
    _selectedServiceId = Prefs().selectedAiService;
    final availableIds = _serviceOptions.map((option) => option.identifier);
    if (!availableIds.contains(_selectedServiceId)) {
      _selectedServiceId = _serviceOptions.first.identifier;
      Prefs().selectedAiService = _selectedServiceId;
    }
    inputController.text = widget.initialMessage ?? '';
    _suggestedPrompts = _pickSuggestedPrompts();
    if (widget.sendImmediate) {
      _sendMessage();
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    inputController.dispose();
    _messageSubscription?.cancel();
    _messageController?.close();
    _scrollController.dispose();
    super.dispose();
  }

  AiServiceOption get _currentService => _serviceOptions.firstWhere(
        (option) => option.identifier == _selectedServiceId,
        orElse: () => _serviceOptions.first,
      );

  String _modelLabel(String serviceId) {
    final option = _serviceOptions.firstWhere(
      (element) => element.identifier == serviceId,
      orElse: () => _serviceOptions.first,
    );
    final stored = Prefs().getAiConfig(serviceId);
    final model = stored['model'];
    if (model != null && model.trim().isNotEmpty) {
      return model;
    }
    return option.defaultModel;
  }

  void _onServiceSelected(String identifier) {
    if (_isStreaming || identifier == _selectedServiceId) return;
    Prefs().selectedAiService = identifier;
    setState(() {
      _selectedServiceId = identifier;
    });
  }

  List<String> _pickSuggestedPrompts() {
    final prompts = List<String>.from(_starterPrompts)..shuffle();
    return prompts.take(3).toList(growable: false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage({bool isRegenerate = false}) {
    if (_isStreaming) {
      return;
    }

    if (inputController.text.trim().isEmpty) return;
    final message = inputController.text.trim();
    inputController.clear();

    _messageSubscription?.cancel();
    _messageController?.close();

    final controller = StreamController<List<ChatMessage>>();
    final stream = ref.read(aiChatProvider.notifier).sendMessageStream(
          message,
          ref,
          isRegenerate,
        );

    setState(() {
      _messageController = controller;
      _messageStream = controller.stream;
      _isStreaming = true;
    });

    _messageSubscription = stream.listen(
      (event) {
        controller.add(event);
        _scrollToBottom();
      },
      onError: (error, stack) {
        controller.addError(error, stack);
        if (!controller.isClosed) {
          controller.close();
        }
        if (mounted) {
          setState(() {
            _isStreaming = false;
          });
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
        if (mounted) {
          setState(() {
            _isStreaming = false;
          });
        }
      },
      cancelOnError: false,
    );
  }

  void _useQuickPrompt(String prompt) {
    inputController.text = '$prompt ${inputController.text}';
    _sendMessage();
  }

  void _clearMessage() {
    if (_isStreaming) {
      return;
    }
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageController?.close();
    _messageController = null;
    setState(() {
      ref.read(aiChatProvider.notifier).clear();
      _messageStream = null;
      _suggestedPrompts = _pickSuggestedPrompts();
    });
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
        final history = messages.take(i).toList(growable: false);
        ref.read(aiChatProvider.notifier).restore(history);
        setState(() {
          inputController.text = message.contentAsString;
          _sendMessage(isRegenerate: true);
        });
        break;
      }
    }
  }

  void _copyMessageContent(String content) {
    Clipboard.setData(ClipboardData(text: content));
    AnxToast.show(L10n.of(context).notesPageCopied);
  }

  void _cancelStreaming() {
    if (!_isStreaming) return;
    cancelActiveAiRequest();
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _messageController?.close();
    _messageController = null;
    setState(() {
      _isStreaming = false;
      _messageStream = null;
    });
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

  @override
  Widget build(BuildContext context) {
    final quickPrompts = _getQuickPrompts(context);

    var aiService = PopupMenuButton<String>(
      enabled: !_isStreaming,
      onSelected: _onServiceSelected,
      itemBuilder: (context) {
        return _serviceOptions.map((option) {
          final isSelected = option.identifier == _selectedServiceId;
          final label = _modelLabel(option.identifier);
          return PopupMenuItem<String>(
            value: option.identifier,
            child: Row(
              children: [
                Image.asset(
                  option.logo,
                  width: 20,
                  height: 20,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${option.title} · $label',
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
            _currentService.logo,
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${_currentService.title} · ${_modelLabel(_selectedServiceId)}',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
    );
    Widget inputBox = FilledContainer(
      padding: const EdgeInsets.all(4),
      radius: 10,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox.shrink(),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    spacing: 8,
                    children: quickPrompts.map((prompt) {
                      return ActionChip(
                        // labelPadding: EdgeInsets.all(0),
                        label: Text(prompt['label']!),
                        onPressed: () => _useQuickPrompt(prompt['prompt']!),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          TextField(
            controller: inputController,
            decoration: InputDecoration(
              isDense: true,
              hintText: L10n.of(context).aiHintInputPlaceholder,
              border: InputBorder.none,
            ),
            maxLines: 5,
            minLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendMessage(),
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: _clearMessage,
                    ),
                    Flexible(child: aiService),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(_isStreaming ? Icons.stop : Icons.send, size: 18),
                onPressed: _isStreaming ? _cancelStreaming : _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );

    Widget buildEmptyState() {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Try a quick prompt:',
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
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Expanded(
            child: _messageStream != null
                ? StreamBuilder<List<ChatMessage>>(
                    stream: _messageStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Skeletonizer.zone(child: Bone.multiText());
                      }

                      final messages = snapshot.data!;
                      if (messages.isEmpty) {
                        return buildEmptyState();
                      }

                      return _buildMessageList(messages);
                    },
                  )
                : ref.watch(aiChatProvider).when(
                      data: (messages) {
                        if (messages.isEmpty) {
                          return buildEmptyState();
                        }

                        return _buildMessageList(messages);
                      },
                      loading: () => Skeletonizer.zone(child: Bone.multiText()),
                      error: (error, stack) =>
                          Center(child: Text('error: $error')),
                    ),
          ),
          inputBox,
        ],
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isStreaming =
            _messageStream != null && index == messages.length - 1;
        return _buildMessageItem(message, index, isStreaming);
      },
    );
  }

  Widget _buildMessageItem(
    ChatMessage message,
    int index,
    bool isStreaming,
  ) {
    final isUser = message is HumanChatMessage;
    final content = message.contentAsString;
    final parsed = parseReasoningContent(content);
    final isLongMessage = content.length > 300;
    final lastAssistantMessage = _getLastAssistantMessage();

    if (!isUser && (parsed.hasThink || parsed.hasToolSteps)) {
      _syncMessageExpansion(index, parsed, isStreaming);
    }

    final expanded = _expandedState[index] ?? (!parsed.hasAnswer);

    return Padding(
      padding: EdgeInsets.only(
        bottom: 8.0,
        left: isUser ? 8.0 : 0,
        right: isUser ? 0 : 8.0,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.only(
                  topLeft: isUser ? const Radius.circular(12) : Radius.zero,
                  topRight: isUser ? Radius.zero : const Radius.circular(12),
                  bottomLeft: isUser ? Radius.zero : const Radius.circular(12),
                  bottomRight: isUser ? const Radius.circular(12) : Radius.zero,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isUser
                      ? _buildCollapsibleText(content, isLongMessage)
                      : _buildAssistantBubble(
                          parsed,
                          expanded,
                          () => _toggleMessageExpansion(index, !expanded),
                        ),
                  if (!isUser)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (identical(message, lastAssistantMessage))
                          TextButton(
                            onPressed: _regenerateLastMessage,
                            child: Text(L10n.of(context).aiRegenerate),
                          ),
                        TextButton(
                          onPressed: () => _copyMessageContent(content),
                          child: Text(L10n.of(context).commonCopy),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  void _toggleMessageExpansion(int key, bool value) {
    setState(() {
      _expandedState[key] = value;
      _userControlled.add(key);
    });
  }

  void _syncMessageExpansion(
    int key,
    ParsedReasoning parsed,
    bool isStreaming,
  ) {
    if (_userControlled.contains(key)) return;
    final shouldExpand = !(parsed.hasAnswer && !isStreaming);
    final current = _expandedState[key];
    if (current == null) {
      _expandedState[key] = shouldExpand;
      return;
    }
    if (current != shouldExpand) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _userControlled.contains(key)) return;
        setState(() {
          _expandedState[key] = shouldExpand;
        });
      });
    }
  }

  Widget _buildAssistantBubble(
    ParsedReasoning parsed,
    bool expanded,
    VoidCallback onToggle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parsed.timeline.isNotEmpty)
          ReasoningPanel(
            timeline: parsed.timeline,
            expanded: expanded,
            streaming: !parsed.hasAnswer,
            onToggle: onToggle,
            margin: const EdgeInsets.only(bottom: 8.0),
          ),
        if (parsed.hasAnswer)
          MarkdownBody(
            data: parsed.answer,
            selectable: true,
          )
        else if (!parsed.hasToolSteps)
          Skeletonizer.zone(child: Bone.multiText()),
      ],
    );
  }

  Widget _buildCollapsibleText(String text, bool isLongMessage) {
    if (!isLongMessage) {
      return SelectableText(
        text,
        selectionControls: MaterialTextSelectionControls(),
      );
    }

    return _CollapsibleText(text: text);
  }
}

class _CollapsibleText extends StatefulWidget {
  const _CollapsibleText({required this.text});

  final String text;

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
            selectionControls: MaterialTextSelectionControls(),
          )
        else
          Stack(
            children: [
              SelectableText(
                widget.text.substring(0, 300),
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
                            .secondaryContainer
                            .withValues(alpha: 0),
                        Theme.of(context).colorScheme.secondaryContainer,
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
