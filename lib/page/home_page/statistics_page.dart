import 'package:papertok_reader/dao/book.dart';
import 'package:papertok_reader/dao/reading_time.dart';
import 'package:papertok_reader/enums/chart_mode.dart';
import 'package:papertok_reader/enums/hint_key.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/page/book_detail.dart';
import 'package:papertok_reader/providers/statistic_data.dart';
import 'package:papertok_reader/utils/date/convert_seconds.dart';
import 'package:papertok_reader/utils/date/week_of_year.dart';
import 'package:papertok_reader/utils/page_transitions.dart';
import 'package:papertok_reader/theme/app_spacing.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/bookshelf/book_cover.dart';
import 'package:papertok_reader/widgets/common/container/outlined_container.dart';
import 'package:papertok_reader/widgets/common/pt_card.dart';
import 'package:papertok_reader/widgets/hint/hint_banner.dart';
import 'package:papertok_reader/widgets/statistic/statistic_card.dart';
import 'package:papertok_reader/widgets/statistic/statistics_dashboard_title.dart';
import 'package:papertok_reader/widgets/statistic/statistics_dashboard.dart';
import 'package:papertok_reader/widgets/tips/statistic_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class StatisticPage extends StatefulWidget {
  const StatisticPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  State<StatisticPage> createState() => _StatisticPageState();
}

class _StatisticPageState extends State<StatisticPage> {
  int totalNumberOfBook = 0;
  int totalNumberOfDate = 0;
  int totalNumberOfNotes = 0;
  late final ScrollController _scrollController =
      widget.controller ?? ScrollController();

  void setNumbers() async {
    final numberOfBook = await readingTimeDao.selectTotalNumberOfBook();
    final numberOfDate = await readingTimeDao.selectTotalNumberOfDate();
    final numberOfNotes = await readingTimeDao.selectTotalNumberOfNotes();
    setState(() {
      totalNumberOfBook = numberOfBook;
      totalNumberOfDate = numberOfDate;
      totalNumberOfNotes = numberOfNotes;
    });
  }

  @override
  void initState() {
    setNumbers();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: Text(context.navBarStatistics),
      // ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const StatisticsDashboardTitle(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 600) {
                    return Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 8, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _SectionHeader(label: 'DASHBOARD'),
                                SizedBox(height: AppSpacing.sm),
                                StatisticsDashboard(),
                                SizedBox(height: AppSpacing.lg),
                                _SectionHeader(label: 'INSIGHTS'),
                                SizedBox(height: AppSpacing.sm),
                                StatisticCard(),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(8, 0, 16, 24),
                            children: const [
                              _SectionHeader(label: 'LIBRARY'),
                              SizedBox(height: AppSpacing.sm),
                              DateBooks(),
                            ],
                          ),
                        ),
                      ],
                    );
                  } else {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      controller: _scrollController,
                      children: const [
                        _SectionHeader(label: 'DASHBOARD'),
                        SizedBox(height: AppSpacing.sm),
                        StatisticsDashboard(),
                        SizedBox(height: AppSpacing.lg),
                        _SectionHeader(label: 'INSIGHTS'),
                        SizedBox(height: AppSpacing.sm),
                        StatisticCard(),
                        SizedBox(height: AppSpacing.lg),
                        _SectionHeader(label: 'LIBRARY'),
                        SizedBox(height: AppSpacing.sm),
                        DateBooks(),
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: ClaudePalette.secondary(context),
        ),
      ),
    );
  }
}

class DateBooks extends ConsumerStatefulWidget {
  const DateBooks({super.key});

  @override
  ConsumerState<DateBooks> createState() => _DateBooksState();
}

class _DateBooksState extends ConsumerState<DateBooks> {
  TextStyle _titleStyle(BuildContext context) => TextStyle(
        fontSize: 22,
        fontFamily: 'SourceHanSerif',
        fontWeight: FontWeight.w700,
        overflow: TextOverflow.ellipsis,
        color: ClaudePalette.fg(context),
        letterSpacing: -0.3,
      );

  List<int> deleteBookIds = [];

  @override
  void dispose() {
    super.dispose();
    if (deleteBookIds.isNotEmpty) {
      readingTimeDao.deleteReadingTimeByBookId(deleteBookIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statisticData = ref.watch(statisticDataProvider);

    Widget dragToDelete(Widget child, int bookId) {
      return StatefulBuilder(builder: (context, localSetState) {
        if (deleteBookIds.contains(bookId)) {
          return OutlinedContainer(
            margin: const EdgeInsets.only(bottom: 10),
            height: 146,
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.delete,
                          size: 30,
                        ),
                        Text(
                          L10n.of(context).statisticDeletedRecords,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    FilledButton(
                        onPressed: () {
                          localSetState(() {
                            deleteBookIds.remove(bookId);
                          });
                        },
                        child: Text(L10n.of(context).commonUndo)),
                  ],
                ),
                const Spacer(),
                const Divider(),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 18),
                    Text(L10n.of(context).statisticDeletedRecordsTips),
                  ],
                ),
              ],
            ),
          );
        }
        ActionPane actionPane = ActionPane(
          motion: const StretchMotion(),
          children: [
            SlidableAction(
              onPressed: (context) {
                localSetState(() {
                  deleteBookIds.add(bookId);
                });
              },
              icon: Icons.delete,
              label: L10n.of(context).commonDelete,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
          ],
        );
        return Slidable(
          key: ValueKey(bookId),
          startActionPane: actionPane,
          endActionPane: actionPane,
          child: child,
        );
      });
    }

    return statisticData.when(
      data: (data) {
        final title = data.isSelectingDay
            ? data.date.toString().substring(0, 10)
            : data.mode == ChartMode.week
                ? weekOfYear(data.date)
                : data.mode == ChartMode.month
                    ? '${data.date.year}.${data.date.month}'
                    : data.mode == ChartMode.year
                        ? data.date.year.toString()
                        : L10n.of(context).statisticAllTime;

        final books = data.bookReadingTime;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(title, style: _titleStyle(context)),
            ),
            if (books.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40, bottom: 40),
                child: StatisticsTips(),
              )
            else
              Column(
                children: [
                  HintBanner(
                    icon: const Icon(Icons.swipe_left),
                    hintKey: HintKey.statisticsSwipeToDelete,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(L10n.of(context).statisticsSwipeToDeleteHint),
                  ),
                  ...books.map((bookMap) {
                    final book = bookMap.keys.first;
                    final readingTime = bookMap.values.first;
                    return dragToDelete(
                      BookStatisticItem(
                        bookId: book.id,
                        readingTime: readingTime,
                      ),
                      book.id,
                    );
                  })
                ],
              ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) => Center(
        child: Text('Error: $error'),
      ),
    );
  }
}

class BookStatisticItem extends StatelessWidget {
  const BookStatisticItem(
      {super.key, required this.bookId, required this.readingTime});

  final int bookId;
  final int readingTime;

  TextStyle _bookTitleStyle(BuildContext context) => TextStyle(
        fontSize: 15,
        fontFamily: 'SourceHanSerif',
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: ClaudePalette.fg(context),
        overflow: TextOverflow.ellipsis,
      );
  TextStyle _bookAuthorStyle(BuildContext context) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: ClaudePalette.secondary(context),
        overflow: TextOverflow.ellipsis,
      );
  TextStyle _bookReadingTimeStyle(BuildContext context) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: ClaudePalette.fg(context),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Book>(
      future: bookDao.selectBookById(bookId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                CupertinoStyleRoute(
                  page: BookDetail(book: snapshot.data!),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: PTCard(
                elevation: 1,
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Hero(
                      tag: snapshot.data!.coverFullPath,
                      child: BookCover(
                        book: snapshot.data!,
                        height: 80,
                        width: 56,
                        radius: 6,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            snapshot.data!.title,
                            style: _bookTitleStyle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  snapshot.data!.author,
                                  style: _bookAuthorStyle(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                convertSeconds(readingTime),
                                textAlign: TextAlign.end,
                                style: _bookReadingTimeStyle(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: snapshot.data!.readingPercentage,
                                    minHeight: 4,
                                    backgroundColor:
                                        ClaudePalette.divider(context),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        ClaudePalette.accent(context)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Text(
                                '${(snapshot.data!.readingPercentage * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: ClaudePalette.accent(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          return const CircularProgressIndicator();
        }
      },
    );
  }
}
