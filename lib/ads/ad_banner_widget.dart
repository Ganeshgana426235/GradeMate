import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io' show Platform;

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  // Flag to ensure the ad loads only once after context is available.
  bool _adLoadedCalled = false; 
  
  // Google's official TEST Ad Unit IDs for Banner Ad
  // MUST be replaced with real IDs for production
  final String _adUnitId = Platform.isAndroid 
    ? 'ca-app-pub-3940256099942544/6300978111' 
    : 'ca-app-pub-3940256099942544/2934735716'; 

  @override
  void initState() {
    super.initState();
  }

  // CORRECTED: Use didChangeDependencies to access MediaQuery via context
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_adLoadedCalled) {
      _loadAd();
      _adLoadedCalled = true; // Set the flag to true after the first call
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadAd() {
    // This method now runs in didChangeDependencies, where MediaQuery is safe to access.
    final adSize = AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(
        MediaQuery.of(context).size.width.toInt());
        
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: adSize, // Use the safely calculated size
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          print('BannerAd failed to load: $error');
        },
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdLoaded && _bannerAd != null) {
      // Ensure the ad is properly sized when loaded
      return Container(
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    } else {
      // Show a placeholder container to prevent layout shifting
      return const SizedBox(height: 50); 
    }
  }
}