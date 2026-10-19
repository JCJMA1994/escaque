import 'dart:math';

/// Valoración Glicko-2 (Glickman, 2012). Cada partida valorada es un periodo.
class Rating {
  final double rating;
  final double deviation;
  final double volatility;
  final int games;
  const Rating({this.rating = 1500, this.deviation = 350, this.volatility = 0.06, this.games = 0});

  /// Provisional: pocas partidas o mucha incertidumbre.
  bool get provisional => games < 5 || deviation > 150;

  Map<String, Object?> toFields() => {'r': rating, 'rd': deviation, 'vol': volatility, 'games': games};

  factory Rating.fromFields(Map<String, Object?> f) => Rating(
        rating: (f['r'] as num?)?.toDouble() ?? 1500,
        deviation: (f['rd'] as num?)?.toDouble() ?? 350,
        volatility: (f['vol'] as num?)?.toDouble() ?? 0.06,
        games: (f['games'] as num?)?.toInt() ?? 0,
      );
}

/// Resultado frente a un rival: [score] 1 victoria, 0,5 tablas, 0 derrota.
typedef GlickoGame = ({double rating, double deviation, double score});

abstract final class Glicko2 {
  static const _scale = 173.7178;
  static const tau = 0.5;

  static double _g(double phi) => 1 / sqrt(1 + 3 * phi * phi / (pi * pi));
  static double _e(double mu, double muj, double phij) => 1 / (1 + exp(-_g(phij) * (mu - muj)));

  static Rating update(Rating p, List<GlickoGame> games) {
    if (games.isEmpty) {
      // Sin partidas: solo crece la incertidumbre.
      final phi = p.deviation / _scale;
      final phiStar = sqrt(phi * phi + p.volatility * p.volatility);
      return Rating(rating: p.rating, deviation: min(350, phiStar * _scale), volatility: p.volatility, games: p.games);
    }
    final mu = (p.rating - 1500) / _scale;
    final phi = p.deviation / _scale;
    var vInv = 0.0, dSum = 0.0;
    for (final o in games) {
      final muj = (o.rating - 1500) / _scale, phij = o.deviation / _scale;
      final e = _e(mu, muj, phij), g = _g(phij);
      vInv += g * g * e * (1 - e);
      dSum += g * (o.score - e);
    }
    final v = 1 / vInv;
    final delta = v * dSum;
    final a = log(p.volatility * p.volatility);
    const eps = 1e-6;
    double f(double x) {
      final ex = exp(x);
      return ex * (delta * delta - phi * phi - v - ex) / (2 * pow(phi * phi + v + ex, 2)) - (x - a) / (tau * tau);
    }

    var aa = a;
    double bb;
    if (delta * delta > phi * phi + v) {
      bb = log(delta * delta - phi * phi - v);
    } else {
      var k = 1;
      while (f(a - k * tau) < 0) {
        k++;
      }
      bb = a - k * tau;
    }
    var fa = f(aa), fb = f(bb);
    while ((bb - aa).abs() > eps) {
      final c = aa + (aa - bb) * fa / (fb - fa);
      final fc = f(c);
      if (fc * fb <= 0) {
        aa = bb;
        fa = fb;
      } else {
        fa = fa / 2;
      }
      bb = c;
      fb = fc;
    }
    final vol = exp(aa / 2);
    final phiStar = sqrt(phi * phi + vol * vol);
    final phiNew = 1 / sqrt(1 / (phiStar * phiStar) + 1 / v);
    final muNew = mu + phiNew * phiNew * dSum;
    return Rating(rating: _scale * muNew + 1500, deviation: _scale * phiNew, volatility: vol, games: p.games + games.length);
  }
}
