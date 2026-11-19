import 'dart:convert';

import 'local_store.dart';

String calendarEvent(Json event) {
  String escape(Object? value) => '${value ?? ''}'
      .replaceAll('\\', '\\\\')
      .replaceAll('\r', '')
      .replaceAll('\n', r'\n')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,');
  String timestamp(String value) {
    final parsed = DateTime.parse(value);
    final date = parsed.isUtc ? parsed.toUtc() : parsed;
    return date
            .toIso8601String()
            .split('.')
            .first
            .replaceAll('-', '')
            .replaceAll(':', '') +
        (parsed.isUtc ? 'Z' : '');
  }

  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//The People Voice//Community//EN',
    'BEGIN:VEVENT',
    'UID:event-${event['id']}@fayettevillethepeoplevoice.com',
    'DTSTAMP:${timestamp(DateTime.now().toUtc().toIso8601String())}',
    'DTSTART:${timestamp(event['starts_at'] as String)}',
    if (event['ends_at'] is String)
      'DTEND:${timestamp(event['ends_at'] as String)}',
    'SUMMARY:${escape(event['title'])}',
    'LOCATION:${escape(event['location'])}',
    'DESCRIPTION:${escape(event['description'])}',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  final foldedLines = lines
      .map((line) {
        final folded = StringBuffer();
        var bytes = 0;
        for (final rune in line.runes) {
          final char = String.fromCharCode(rune),
              size = utf8.encode(String.fromCharCode(rune)).length;
          if (bytes + size > 75) {
            folded.write('\r\n ');
            bytes = 1;
          }
          folded.write(char);
          bytes += size;
        }
        return folded.toString();
      })
      .join('\r\n');
  return '$foldedLines\r\n';
}

bool eventMatches(
  Json row, {
  required String period,
  required bool free,
  required bool family,
  DateTime? now,
}) {
  if (free && row['is_free'] != true) return false;
  if (family && row['family_friendly'] != true) return false;
  if (period == 'all') return true;
  final start = DateTime.tryParse('${row['starts_at']}');
  if (start == null) return false;
  final current = now ?? DateTime.now();
  final midnight = DateTime(current.year, current.month, current.day);
  if (period == 'today') {
    return !start.isBefore(midnight) &&
        start.isBefore(midnight.add(const Duration(days: 1)));
  }
  return !start.isBefore(current) &&
      start.isBefore(current.add(const Duration(days: 7)));
}
