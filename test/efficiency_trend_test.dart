import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_health/services/efficiency_trend.dart';
import 'package:arcade_health/services/health_score_service.dart' show TrendDir;

void main() {
  group('EfficiencyTrend.compare', () {
    test('baseline ou courant à 0 -> flat (rien à comparer)', () {
      expect(EfficiencyTrend.compare(0, 10).dir, TrendDir.flat);
      expect(EfficiencyTrend.compare(10, 0).dir, TrendDir.flat);
    });

    test('variation en dessous du seuil -> flat', () {
      // 1% de variation, seuil par défaut 2%.
      final t = EfficiencyTrend.compare(10.05, 10.0);
      expect(t.dir, TrendDir.flat);
    });

    test('ratio plus bas que la baseline -> down + good (progression)', () {
      final t = EfficiencyTrend.compare(9.0, 10.0);
      expect(t.dir, TrendDir.down);
      expect(t.good, isTrue);
    });

    test('ratio plus haut que la baseline -> up + pas good (régression)', () {
      final t = EfficiencyTrend.compare(11.0, 10.0);
      expect(t.dir, TrendDir.up);
      expect(t.good, isFalse);
    });

    test('label reflète le delta signé', () {
      final down = EfficiencyTrend.compare(9.0, 10.0);
      expect(down.label, '-1.0');
      final up = EfficiencyTrend.compare(11.0, 10.0);
      expect(up.label, '+1.0');
    });
  });

  group('EfficiencyTrend.average', () {
    test('moyenne simple', () {
      expect(EfficiencyTrend.average([8.0, 10.0, 12.0]), closeTo(10.0, 1e-9));
    });
  });
}
