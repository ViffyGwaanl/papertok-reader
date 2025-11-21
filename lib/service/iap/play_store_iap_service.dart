import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/iap/base_iap_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class PlayStoreIAPService extends BaseIAPService {
  PlayStoreIAPService({
    required super.trialDays,
  })  : _inAppPurchase = InAppPurchase.instance,
        _isPurchased = Prefs().iapPurchaseStatus,
        _trialStartDate = Prefs().iapLastCheckTime;

  static const MethodChannel _installInfoChannel =
      MethodChannel('com.anxcye.anx_reader/install_info');
  final InAppPurchase _inAppPurchase;
  bool _isInitialized = false;
  bool _isPurchased;
  late DateTime _trialStartDate;
  String productId = 'anx_reader_lifetime';

  @override
  bool get isInitialized => _isInitialized;

  @override
  String get storeName => 'Play Store';

  @override
  Stream<List<PurchaseDetails>> get purchaseUpdates =>
      _inAppPurchase.purchaseStream;

  @override
  Future<ProductDetailsResponse> queryProductDetails() async {
    final Set<String> productIds = {productId};
    return _inAppPurchase.queryProductDetails(productIds);
  }

  @override
  Future<void> buy(ProductDetails productDetails) async {
    final purchaseParam = PurchaseParam(productDetails: productDetails);
    await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.status == PurchaseStatus.purchased ||
        purchaseDetails.status == PurchaseStatus.restored) {
      _markPurchased();
    }
    await _inAppPurchase.completePurchase(purchaseDetails);
  }

  @override
  Future<void> restorePurchases() {
    return _inAppPurchase.restorePurchases();
  }

  @override
  Future<bool> isAvailable() {
    return _inAppPurchase.isAvailable();
  }

  @override
  Future<void> initialize() async {
    await _resolveTrialStartDate();
    _isPurchased = Prefs().iapPurchaseStatus;
    _isInitialized = true;
  }

  @override
  Future<void> refresh() async {
    _isPurchased = Prefs().iapPurchaseStatus;
  }

  @override
  bool get isPurchased => _isInitialized && _isPurchased;

  @override
  bool get isOriginalUser => false;

  @override
  DateTime? get purchaseDate => null;

  @override
  DateTime get originalDate => _trialStartDate;

  Future<void> _resolveTrialStartDate() async {
    final installDate = await _getInstallDate();
    AnxLog.info('IAP: Install date: $installDate');
    if (installDate != null) {
      _trialStartDate = installDate;
      Prefs().iapLastCheckTime = _trialStartDate;
      return;
    }

    if (_trialStartDate.year == 1970) {
      _trialStartDate = DateTime.now();
      Prefs().iapLastCheckTime = _trialStartDate;
    }
  }

  Future<DateTime?> _getInstallDate() async {
    try {
      final installInfo =
          await _installInfoChannel.invokeMapMethod<String, dynamic>(
        'getInstallInfo',
      );
      final firstInstall = installInfo?['firstInstallTime'] as int?;
      final lastUpdate = installInfo?['lastUpdateTime'] as int?;
      final timestampMs = firstInstall ?? lastUpdate;
      if (timestampMs == null || timestampMs <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(timestampMs);
    } catch (e) {
      AnxLog.warning('IAP: Unable to read install info: $e');
      return null;
    }
  }

  void _markPurchased() {
    _isPurchased = true;
    Prefs().iapPurchaseStatus = true;
    Prefs().iapLastCheckTime = DateTime.now();
    AnxLog.info('IAP: Play Store purchase marked as completed');
  }
}
