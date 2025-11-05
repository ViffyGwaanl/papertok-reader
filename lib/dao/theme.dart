import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/utils/toast/common.dart';

class ThemeDao extends BaseDao {
  ThemeDao();

  static const String table = 'tb_themes';

  Future<int> insertTheme(ReadTheme readTheme) {
    return insert(table, readTheme.toMap());
  }

  Future<List<ReadTheme>> selectThemes() {
    return queryList(
      table,
      mapper: ReadTheme.fromDb,
    );
  }

  Future<void> deleteTheme(int id) async {
    final currentThemes = await queryList(
      table,
      mapper: ReadTheme.fromDb,
    );
    if (currentThemes.length <= 2) {
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).readingPageAtLeastTwoThemes);
      return;
    }

    await delete(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateTheme(ReadTheme readTheme) async {
    await update(
      table,
      readTheme.toMap(),
      where: 'id = ?',
      whereArgs: [readTheme.id],
    );
  }

  Future<ReadTheme> selectReadThemeById(int id) async {
    final theme = await querySingle(
      table,
      mapper: ReadTheme.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (theme == null) {
      throw StateError('Theme with id $id not found');
    }
    return theme;
  }
}

final themeDao = ThemeDao();

@Deprecated('Use themeDao.insertTheme instead')
Future<int> insertTheme(ReadTheme readTheme) => themeDao.insertTheme(readTheme);

@Deprecated('Use themeDao.selectThemes instead')
Future<List<ReadTheme>> selectThemes() => themeDao.selectThemes();

@Deprecated('Use themeDao.deleteTheme instead')
Future<void> deleteTheme(int id) => themeDao.deleteTheme(id);

@Deprecated('Use themeDao.updateTheme instead')
Future<void> updateTheme(ReadTheme readTheme) =>
    themeDao.updateTheme(readTheme);

@Deprecated('Use themeDao.selectReadThemeById instead')
Future<ReadTheme> selectReadThemeById(int id) =>
    themeDao.selectReadThemeById(id);
