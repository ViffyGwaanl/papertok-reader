class RelativeTimeFormatter {
  const RelativeTimeFormatter._();

  static String format(DateTime? timestamp) {
    if (timestamp == null) return '--'; // TODO(l10n)

    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 60) return 'just now'; // TODO(l10n)
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago'; // TODO(l10n)
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago'; // TODO(l10n)
    }
    if (diff.inDays == 1) return 'yesterday'; // TODO(l10n)
    if (diff.inDays < 30) {
      return '${diff.inDays}d ago'; // TODO(l10n)
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return months <= 1
          ? 'last month' // TODO(l10n)
          : '${months}mo ago'; // TODO(l10n)
    }
    final years = (diff.inDays / 365).floor();
    return years <= 1
        ? 'last year' // TODO(l10n)
        : '${years}y ago'; // TODO(l10n)
  }
}
