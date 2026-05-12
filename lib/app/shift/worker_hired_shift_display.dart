import '../../domain/models.dart';
import 'shift_repository.dart';

/// Calendar workdays spanned by [Gig.startAt]–[endAt] in local time.
List<DateTime> gigCalendarDaysLocal(Gig g) {
  final s = g.startAt.toLocal();
  final e = g.endAt.toLocal();
  var cur = DateTime(s.year, s.month, s.day);
  final end = DateTime(e.year, e.month, e.day);
  final out = <DateTime>[];
  while (!cur.isAfter(end)) {
    out.add(cur);
    cur = cur.add(const Duration(days: 1));
  }
  return out;
}

String ymdLocal(DateTime d) {
  final l = d.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

ShiftDaySummary? shiftDaySummaryFor(
  DateTime localDay,
  List<ShiftDaySummary> rows,
) {
  final key = ymdLocal(localDay);
  for (final s in rows) {
    if (ymdLocal(s.workDay) == key) return s;
  }
  return null;
}

/// True when every calendar day in the gig span has a check-out timestamp.
bool shiftFullyCheckedOut(Gig gig, List<ShiftDaySummary> summaries) {
  final span = gigCalendarDaysLocal(gig);
  if (span.isEmpty) return false;
  for (final d in span) {
    if (shiftDaySummaryFor(d, summaries)?.checkOut == null) return false;
  }
  return true;
}

Gig? pickNearestHiredGig(List<Gig> hiredGigs, DateTime nowUtc) {
  if (hiredGigs.isEmpty) return null;
  Gig? best;
  int? bestScore;
  for (final g in hiredGigs) {
    final s = g.startAt.toUtc();
    final e = g.endAt.toUtc();
    final int score;
    if (!nowUtc.isBefore(s) && nowUtc.isBefore(e)) {
      score = 0;
    } else if (nowUtc.isBefore(s)) {
      score = 10 + s.difference(nowUtc).inMinutes.abs();
    } else {
      score = 1000 + nowUtc.difference(e).inMinutes.abs();
    }
    if (best == null || (bestScore != null && score < bestScore)) {
      best = g;
      bestScore = score;
    }
  }
  return best ?? hiredGigs.first;
}

/// Same rules as **My Shift**: prefer gigs still within [startAt, endAt]; else
/// the most recently ended gig that has full per-day check-outs; omit past
/// gigs that never completed attendance.
Future<Gig?> pickDisplayedHiredShift({
  required List<Gig> hiredGigs,
  required String workerId,
  required ShiftRepository shiftRepo,
}) async {
  if (hiredGigs.isEmpty) return null;
  final nowUtc = DateTime.now().toUtc();
  final inWindow =
      hiredGigs.where((g) => !nowUtc.isAfter(g.endAt.toUtc())).toList();
  if (inWindow.isNotEmpty) return pickNearestHiredGig(inWindow, nowUtc);

  final ended = [...hiredGigs]..sort((a, b) => b.endAt.compareTo(a.endAt));
  for (final g in ended) {
    final sum = await shiftRepo.listWorkDaySummaries(
      gigId: g.id,
      workerId: workerId,
    );
    if (shiftFullyCheckedOut(g, sum)) return g;
  }
  return null;
}
