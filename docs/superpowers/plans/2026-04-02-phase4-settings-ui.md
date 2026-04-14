# Phase 4 Settings UI Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add settings UI for all Phase 4 features (KAIROS, Local Embedding, Web Search API Key, Skills) so users can discover and configure them.

**Architecture:** Add a new "AI Features" `SettingsSection` to the existing AI settings page (`lib/page/settings_page/ai.dart`) containing KAIROS level picker, local embedding endpoint config, and web search API key. The Skills button is already in the chat input bar but needs better visibility. All settings use the existing `Prefs()` singleton + `SettingsTile` widget family.

**Tech Stack:** Flutter, Riverpod, SharedPreferences (Prefs singleton), SettingsTile widget family

---

### Task 1: Add "AI Features" Section to AI Settings Page

**Files:**
- Modify: `lib/page/settings_page/ai.dart` (insert new SettingsSection between "Quick Prompts" and "AI Cache" sections, around line 355)
- Modify: `lib/service/ai/skills/ai_skill_registry.dart` (import for skill name list)

- [ ] **Step 1: Add skill registry import to ai.dart**

At the top of `lib/page/settings_page/ai.dart`, add:

```dart
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
```

- [ ] **Step 2: Add "AI Features" SettingsSection after Quick Prompts section**

In the `settingsSections(sections: [...])` list in `lib/page/settings_page/ai.dart`, insert a new section after the Quick Prompts section (after line 355) and before the AI Cache section:

```dart
      SettingsSection(
        title: const Text('AI Features'),
        tiles: [
          // KAIROS proactive reading assistant
          SettingsTile.navigation(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('KAIROS Reading Assistant'),
            description: Text(
              Prefs().kairosLevel == 0
                  ? 'Off'
                  : ['', 'Light (30s)', 'Medium (20s)', 'Eager (10s)'][Prefs().kairosLevel],
            ),
            onPressed: (context) {
              _showKairosLevelPicker(context);
            },
          ),
          // Active skill display
          SettingsTile.navigation(
            leading: const Icon(Icons.auto_fix_high),
            title: const Text('Active Skill'),
            description: Text(
              AiSkillRegistry.byId(Prefs().activeAiSkillId)?.name ?? 'None',
            ),
            onPressed: (context) {
              _showSkillPicker(context);
            },
          ),
          // Web search API key
          SettingsTile.navigation(
            leading: const Icon(Icons.search),
            title: const Text('Web Search API Key'),
            description: Text(
              _hasWebSearchApiKey() ? 'Serper.dev configured' : 'Using DuckDuckGo (no key needed)',
            ),
            onPressed: (context) {
              _showWebSearchApiKeyDialog(context);
            },
          ),
          // Local embedding endpoint
          SettingsTile.navigation(
            leading: const Icon(Icons.memory),
            title: const Text('Local Embedding'),
            description: Text(
              (Prefs().localEmbeddingEndpoint ?? '').isNotEmpty
                  ? '${Prefs().localEmbeddingEndpoint} (${Prefs().localEmbeddingModel})'
                  : 'Not configured (using remote API)',
            ),
            onPressed: (context) {
              _showLocalEmbeddingDialog(context);
            },
          ),
        ],
      ),
```

- [ ] **Step 3: Run flutter analyze to verify no syntax errors**

Run: `flutter analyze --no-pub 2>&1 | grep "ai.dart" | grep error`
Expected: No errors from ai.dart (only pre-existing L10n errors)

- [ ] **Step 4: Commit**

```bash
git add lib/page/settings_page/ai.dart
git commit -m "feat(settings): add AI Features section with KAIROS, skills, web search, embedding tiles"
```

---

### Task 2: Implement KAIROS Level Picker Dialog

**Files:**
- Modify: `lib/page/settings_page/ai.dart` (add `_showKairosLevelPicker` method)

- [ ] **Step 1: Add _showKairosLevelPicker method to _AISettingsState**

Add this method to the state class in `lib/page/settings_page/ai.dart`:

```dart
  void _showKairosLevelPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              const ListTile(
                title: Text('KAIROS Reading Assistant'),
                subtitle: Text(
                  'Proactively offers AI help when you linger on a passage.',
                ),
              ),
              const Divider(),
              _kairosOption(context, 0, 'Off', 'No proactive suggestions'),
              _kairosOption(context, 1, 'Light', 'Suggest after 30 seconds'),
              _kairosOption(context, 2, 'Medium', 'Suggest after 20 seconds'),
              _kairosOption(context, 3, 'Eager', 'Suggest after 10 seconds'),
            ],
          ),
        );
      },
    );
  }

  Widget _kairosOption(
      BuildContext context, int level, String title, String subtitle) {
    final isSelected = Prefs().kairosLevel == level;
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        setState(() {
          Prefs().kairosLevel = level;
        });
        Navigator.pop(context);
      },
    );
  }
```

- [ ] **Step 2: Run flutter analyze to verify**

Run: `flutter analyze --no-pub 2>&1 | grep "ai.dart" | grep error`
Expected: No new errors

- [ ] **Step 3: Commit**

```bash
git add lib/page/settings_page/ai.dart
git commit -m "feat(settings): add KAIROS level picker modal"
```

---

### Task 3: Implement Skill Picker Dialog

**Files:**
- Modify: `lib/page/settings_page/ai.dart` (add `_showSkillPicker` method)

- [ ] **Step 1: Add _showSkillPicker method to _AISettingsState**

```dart
  void _showSkillPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final skills = AiSkillRegistry.allSkills();
        final activeId = Prefs().activeAiSkillId;

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              const ListTile(
                title: Text('AI Skill'),
                subtitle: Text(
                  'Activate a skill to shape the AI\'s behavior and expertise.',
                ),
              ),
              const Divider(),
              ListTile(
                title: const Text('None'),
                subtitle: const Text('Default assistant mode'),
                trailing: activeId == null
                    ? Icon(Icons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  setState(() {
                    Prefs().activeAiSkillId = null;
                  });
                  Navigator.pop(context);
                },
              ),
              ...skills.map((skill) {
                final isSelected = skill.id == activeId;
                return ListTile(
                  leading: Icon(
                    IconData(skill.iconCodePoint ?? 0xe14c,
                        fontFamily: 'MaterialIcons'),
                    size: 20,
                  ),
                  title: Text(skill.name),
                  subtitle: Text(skill.description, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: isSelected
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      Prefs().activeAiSkillId = skill.id;
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
```

- [ ] **Step 2: Run flutter analyze to verify**

Run: `flutter analyze --no-pub 2>&1 | grep "ai.dart" | grep error`
Expected: No new errors

- [ ] **Step 3: Commit**

```bash
git add lib/page/settings_page/ai.dart
git commit -m "feat(settings): add skill picker modal"
```

---

### Task 4: Implement Web Search API Key Dialog

**Files:**
- Modify: `lib/page/settings_page/ai.dart` (add `_showWebSearchApiKeyDialog` and `_hasWebSearchApiKey` methods)

- [ ] **Step 1: Add helper and dialog methods to _AISettingsState**

```dart
  bool _hasWebSearchApiKey() {
    try {
      final config = Prefs().getAiConfig(Prefs().selectedAiService);
      final key = config['webSearchApiKey']?.trim() ?? '';
      return key.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _showWebSearchApiKeyDialog(BuildContext context) {
    final config = Prefs().getAiConfig(Prefs().selectedAiService);
    final controller = TextEditingController(
      text: config['webSearchApiKey'] ?? '',
    );

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Web Search API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Optional. Enter a Serper.dev API key for higher-quality '
                'Google search results. Without a key, DuckDuckGo is used '
                'as a free fallback.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Serper API Key',
                  hintText: 'Leave empty to use DuckDuckGo',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final updated = Map<String, String>.from(config);
                final key = controller.text.trim();
                if (key.isEmpty) {
                  updated.remove('webSearchApiKey');
                } else {
                  updated['webSearchApiKey'] = key;
                }
                Prefs().saveAiConfig(Prefs().selectedAiService, updated);
                setState(() {});
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).then((_) => controller.dispose());
  }
```

- [ ] **Step 2: Run flutter analyze to verify**

Run: `flutter analyze --no-pub 2>&1 | grep "ai.dart" | grep error`
Expected: No new errors

- [ ] **Step 3: Commit**

```bash
git add lib/page/settings_page/ai.dart
git commit -m "feat(settings): add web search API key dialog"
```

---

### Task 5: Implement Local Embedding Config Dialog

**Files:**
- Modify: `lib/page/settings_page/ai.dart` (add `_showLocalEmbeddingDialog` method)

- [ ] **Step 1: Add dialog method to _AISettingsState**

```dart
  void _showLocalEmbeddingDialog(BuildContext context) {
    final endpointController = TextEditingController(
      text: Prefs().localEmbeddingEndpoint ?? '',
    );
    final modelController = TextEditingController(
      text: Prefs().localEmbeddingModel,
    );

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Local Embedding'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configure a local embedding server (Ollama, llama.cpp, etc.) '
                'for offline semantic search. Leave empty to use remote API.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endpointController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Endpoint URL',
                  hintText: 'http://localhost:11434',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Model name',
                  hintText: 'nomic-embed-text',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if ((Prefs().localEmbeddingEndpoint ?? '').isNotEmpty)
              TextButton(
                onPressed: () {
                  Prefs().localEmbeddingEndpoint = null;
                  Prefs().localEmbeddingModel = 'nomic-embed-text';
                  setState(() {});
                  Navigator.pop(context);
                },
                child: const Text('Clear'),
              ),
            FilledButton(
              onPressed: () {
                Prefs().localEmbeddingEndpoint = endpointController.text;
                Prefs().localEmbeddingModel = modelController.text.isEmpty
                    ? 'nomic-embed-text'
                    : modelController.text;
                setState(() {});
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).then((_) {
      endpointController.dispose();
      modelController.dispose();
    });
  }
```

- [ ] **Step 2: Run flutter analyze to verify all changes**

Run: `flutter analyze --no-pub 2>&1 | grep "ai.dart" | grep error | grep -v "L10n\|uri_does_not_exist"`
Expected: No output (no new errors)

- [ ] **Step 3: Commit all Task 5 changes**

```bash
git add lib/page/settings_page/ai.dart
git commit -m "feat(settings): add local embedding config dialog"
```

---

### Task 6: Final Integration Commit and Push

**Files:**
- No new changes — verify and push

- [ ] **Step 1: Verify git status is clean**

Run: `git status`
Expected: `nothing to commit, working tree clean`

- [ ] **Step 2: Run full flutter analyze**

Run: `flutter analyze --no-pub 2>&1 | grep "ai.dart" | grep error | grep -v "L10n\|uri_does_not_exist"`
Expected: No output (no new errors from our changes)

- [ ] **Step 3: Push to GitHub**

```bash
git push origin main
```

---

## Self-Review Checklist

1. **Spec coverage:**
   - [x] KAIROS level toggle in AI settings — Task 1 (tile) + Task 2 (picker)
   - [x] Local embedding endpoint config — Task 1 (tile) + Task 5 (dialog)
   - [x] Web search API key config — Task 1 (tile) + Task 4 (dialog)
   - [x] Skills picker in settings — Task 1 (tile) + Task 3 (picker)
   - [x] Token usage display is already visible (shows after conversation ends)

2. **Placeholder scan:** No TBD/TODO/placeholders. All code blocks complete.

3. **Type consistency:**
   - `Prefs().kairosLevel` (int 0-3) — consistent across Task 1 and 2
   - `Prefs().activeAiSkillId` (String?) — consistent across Task 1 and 3
   - `Prefs().localEmbeddingEndpoint` (String?) — consistent across Task 1 and 5
   - `Prefs().localEmbeddingModel` (String) — consistent across Task 1 and 5
   - `AiSkillRegistry.byId()` / `AiSkillRegistry.allSkills()` — matches existing API
