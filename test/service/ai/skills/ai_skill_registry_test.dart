import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('native Seminar marker is not exposed as a normal chat skill', () {
    expect(
      AiSkillRegistry.builtInSkills.map((skill) => skill.id),
      isNot(contains(AiSkillRegistry.nativeSeminarSkillId)),
    );
    expect(
      AiSkillRegistry.allSkills().map((skill) => skill.id),
      isNot(contains(AiSkillRegistry.nativeSeminarSkillId)),
    );
    expect(
      AiSkillRegistry.selectableActiveSkills().map((skill) => skill.id),
      isNot(contains(AiSkillRegistry.nativeSeminarSkillId)),
    );

    final marker = AiSkillRegistry.byId(AiSkillRegistry.nativeSeminarSkillId);

    expect(marker, isNotNull);
    expect(marker!.id, AiSkillRegistry.nativeSeminarSkillId);
    expect(marker.systemPromptAppend, isEmpty);
  });
}
