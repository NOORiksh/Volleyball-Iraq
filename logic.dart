// منطق قوانين الكرة الطائرة (بدون أي اعتماد على الواجهة)

class SetScore {
  final int a, b;
  const SetScore(this.a, this.b);
}

/// الشوط العادي 25، الحاسم 15، بفارق نقطتين.
/// إذا تجاوز الفائز الهدف يجب أن يكون الفارق نقطتين بالضبط (26-24).
bool isValidSet(int a, int b, {required bool decider}) {
  final t = decider ? 15 : 25;
  final w = a > b ? a : b, l = a > b ? b : a;
  if (w < t) return false;
  return w > t ? w - l == 2 : w - l >= 2;
}

class Team {
  final String id, name;
  const Team(this.id, this.name);
  @override
  bool operator ==(Object o) => o is Team && o.id == id;
  @override
  int get hashCode => id.hashCode;
}

class VMatch {
  final Team a, b;
  final int bestOf; // 3 أو 5
  final List<SetScore> sets = [];
  String? id;          // معرّف مستند Firestore
  String stage;        // group | qf | sf | final
  int slot;            // موقع المباراة داخل الدور
  VMatch(this.a, this.b, {this.bestOf = 3, this.stage = 'group', this.slot = 0, this.id});

  int get need => bestOf ~/ 2 + 1;
  int get setsA => sets.where((s) => s.a > s.b).length;
  int get setsB => sets.where((s) => s.b > s.a).length;
  bool get finished => setsA == need || setsB == need;
  Team? get winner => !finished ? null : (setsA > setsB ? a : b);

  /// يرجع نص الخطأ أو null عند النجاح
  String? addSet(int x, int y) {
    if (finished) return 'المباراة منتهية';
    final decider = sets.length == bestOf - 1;
    if (!isValidSet(x, y, decider: decider)) {
      return decider
          ? 'الشوط الفاصل ينتهي عند 15 نقطة بفارق نقطتين'
          : 'الشوط ينتهي عند 25 نقطة بفارق نقطتين';
    }
    sets.add(SetScore(x, y));
    return null;
  }
}

class StandRow {
  final Team team;
  int played = 0, wins = 0, pts = 0, sw = 0, sl = 0, pf = 0, pa = 0;
  StandRow(this.team);
  double get setRatio => sl == 0 ? (sw == 0 ? 0 : 1e9) : sw / sl;
  double get pointRatio => pa == 0 ? (pf == 0 ? 0 : 1e9) : pf / pa;
}

/// 3-0 / 3-1 => 3 للفائز | 3-2 => 2 للفائز و1 للخاسر
List<StandRow> standings(List<Team> teams, List<VMatch> matches) {
  final rows = {for (final t in teams) t.id: StandRow(t)};
  for (final m in matches.where((m) => m.finished)) {
    final w = m.winner!;
    final winnerIsA = w == m.a;
    final ra = rows[m.a.id]!, rb = rows[m.b.id]!;
    final rw = winnerIsA ? ra : rb, rl = winnerIsA ? rb : ra;
    final loserSets = winnerIsA ? m.setsB : m.setsA;
    final fullDistance = loserSets == m.need - 1;
    rw.pts += fullDistance ? 2 : 3;
    rl.pts += fullDistance ? 1 : 0;
    rw.wins++;
    for (final r in [ra, rb]) {
      r.played++;
    }
    ra.sw += m.setsA; ra.sl += m.setsB;
    rb.sw += m.setsB; rb.sl += m.setsA;
    for (final s in m.sets) {
      ra.pf += s.a; ra.pa += s.b;
      rb.pf += s.b; rb.pa += s.a;
    }
  }
  final list = rows.values.toList()
    ..sort((x, y) {
      var c = y.pts.compareTo(x.pts);
      if (c != 0) return c;
      c = y.wins.compareTo(x.wins);
      if (c != 0) return c;
      c = y.setRatio.compareTo(x.setRatio);
      if (c != 0) return c;
      return y.pointRatio.compareTo(x.pointRatio);
    });
  return list;
}

class Tie {
  Team? a, b;
  VMatch? match;
  Tie([this.a, this.b]);
  Team? get winner => match?.winner;
}

/// 8 فرق مرتبة حسب التصنيف: 1×8، 4×5، 2×7، 3×6 ثم نصف نهائي ثم نهائي
List<List<Tie>> buildBracket(List<Team> s) {
  assert(s.length == 8);
  return [
    [Tie(s[0], s[7]), Tie(s[3], s[4]), Tie(s[1], s[6]), Tie(s[2], s[5])],
    [Tie(), Tie()],
    [Tie()],
  ];
}

/// تصعيد تلقائي للفائز إلى الدور التالي
void advance(List<List<Tie>> rounds) {
  for (var r = 0; r < rounds.length - 1; r++) {
    for (var i = 0; i < rounds[r].length; i++) {
      final w = rounds[r][i].winner;
      final next = rounds[r + 1][i ~/ 2];
      if (i % 2 == 0) { next.a = w; } else { next.b = w; }
    }
  }
}

String roundName(int r, int total) =>
    r == total - 1 ? 'النهائي' : r == total - 2 ? 'نصف النهائي' : 'ربع النهائي';
