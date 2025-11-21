import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:anx_reader/service/iap/app_store_iap_service.dart';
import 'package:anx_reader/service/iap/base_iap_service.dart';
import 'package:anx_reader/service/iap/play_store_iap_service.dart';

export 'package:anx_reader/service/iap/base_iap_service.dart' show IAPStatus;

class NoopIAPService extends BaseIAPService {
  NoopIAPService({required super.trialDays});

  @override
  bool get isInitialized => true;

  @override
  bool get isPurchased => false;

  @override
  bool get isOriginalUser => false;

  @override
  DateTime? get purchaseDate => null;

  @override
  DateTime get originalDate => DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get storeName => 'In-App Purchase';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<ProductDetailsResponse> queryProductDetails() async {
    return ProductDetailsResponse(productDetails: [], notFoundIDs: []);
  }

  @override
  Future<void> buy(ProductDetails productDetails) async {}

  @override
  Future<void> completePurchase(PurchaseDetails purchaseDetails) async {}

  @override
  Future<void> restorePurchases() async {}

  @override
  Stream<List<PurchaseDetails>> get purchaseUpdates =>
      const Stream<List<PurchaseDetails>>.empty();
}

class IAPService {
  IAPService._internal() : _delegate = _buildDelegate();

  factory IAPService() => _instance;

  static final IAPService _instance = IAPService._internal();

  static const int kTrialDays = 7;
  static const int kMaxValidationInterval = 7 * 24 * 60 * 60 * 1000;

  final BaseIAPService _delegate;

  static BaseIAPService _buildDelegate() {
    if (Platform.isIOS || Platform.isMacOS) {
      return AppStoreIAPService(
        maxValidationInterval: kMaxValidationInterval,
        trialDays: kTrialDays,
      );
    }

    if (Platform.isAndroid) {
      return PlayStoreIAPService(
        trialDays: kTrialDays,
      );
    }

    return NoopIAPService(trialDays: kTrialDays);
  }

  Future<void> initialize() => _delegate.initialize();

  Future<void> refresh() => _delegate.refresh();

  Future<bool> isAvailable() => _delegate.isAvailable();

  Future<ProductDetailsResponse> queryProductDetails() =>
      _delegate.queryProductDetails();

  Future<void> buy(ProductDetails productDetails) =>
      _delegate.buy(productDetails);

  Future<void> completePurchase(PurchaseDetails purchaseDetails) =>
      _delegate.completePurchase(purchaseDetails);

  Future<void> restorePurchases() => _delegate.restorePurchases();

  Stream<List<PurchaseDetails>> get purchaseUpdates =>
      _delegate.purchaseUpdates;

  bool get isPurchased => _delegate.isPurchased;
  bool get isFeatureAvailable => _delegate.isFeatureAvailable;
  int get trialDaysLeft => _delegate.trialDaysLeft;
  IAPStatus get iapStatus => _delegate.iapStatus;
  DateTime? get purchaseDate => _delegate.purchaseDate;
  DateTime get originalDate => _delegate.originalDate;
  String statusTitle(BuildContext context) => _delegate.statusTitle(context);
  String get storeName => _delegate.storeName;
}
