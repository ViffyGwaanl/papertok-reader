class ReadingTime {
  int? id;
  int bookId;
  String? date;
  int readingTime;

  ReadingTime({
    this.id,
    required this.bookId,
    this.date,
    required this.readingTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'book_id': bookId,
      'date': date,
      'reading_time': readingTime,
    };
  }

  factory ReadingTime.fromDb(Map<String, dynamic> map) {
    return ReadingTime(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      date: map['date'] as String?,
      readingTime: map['reading_time'] as int? ?? 0,
    );
  }
}
