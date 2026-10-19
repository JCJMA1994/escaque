import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_ids.dart';
import '../purchases/purchases.dart';
import 'ads_service.dart';

/// Banner adaptativo anclado. Solo en pantallas fuera de la partida.
/// No ocupa espacio hasta que hay un anuncio cargado.
class BannerSlot extends ConsumerStatefulWidget {
  const BannerSlot({super.key});

  @override
  ConsumerState<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends ConsumerState<BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;
  AdsService? _ads;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ads == null) {
      _ads = ref.read(adsServiceProvider);
      _ads!.ready.addListener(_maybeLoad);
    }
    _maybeLoad();
  }

  Future<void> _maybeLoad() async {
    final ads = _ads;
    if (ads == null || _requested || !ads.ready.value || !mounted) return;
    _requested = true;
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    _ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ads?.ready.removeListener(_maybeLoad);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ref.watch(adFreeProvider.select((s) => s.adFree))) return const SizedBox.shrink();
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
