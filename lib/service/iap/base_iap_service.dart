import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

enum IAPStatus {
  purchased,
  trial,
  trialExpired,
  originalUser,
  unknown,
}

abstract class BaseIAPService {
  BaseIAPService({required this.trialDays});

  final int trialDays;

  bool get isInitialized;
  bool get isPurchased;
  bool get isOriginalUser;

  DateTime get originalDate;
  DateTime? get purchaseDate;

  String get storeName;

  Future<void> initialize();
  Future<void> refresh();
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> queryProductDetails();
  Future<void> buy(ProductDetails productDetails);
  Future<void> completePurchase(PurchaseDetails purchaseDetails);
  Future<void> restorePurchases();
  Stream<List<PurchaseDetails>> get purchaseUpdates;

  int get trialDaysLeft {
    if (!isInitialized) {
      return 0;
    }
    final startDate = originalDate;
    final diff = DateTime.now().difference(startDate).inDays;
    return trialDays - diff;
  }

  bool get isFeatureAvailable => isPurchased || trialDaysLeft > 0;

  IAPStatus get iapStatus {
    if (!isInitialized) {
      return IAPStatus.unknown;
    }
    if (isPurchased) {
      return IAPStatus.purchased;
    }
    if (isOriginalUser) {
      return IAPStatus.originalUser;
    }
    if (trialDaysLeft > 0) {
      return IAPStatus.trial;
    }
    return IAPStatus.trialExpired;
  }

  String statusTitle(BuildContext context) {
    switch (iapStatus) {
      case IAPStatus.purchased:
        return L10n.of(context).iapStatusPurchased;
      case IAPStatus.trial:
        return L10n.of(context).iapStatusTrial;
      case IAPStatus.trialExpired:
        return L10n.of(context).iapStatusTrialExpired;
      case IAPStatus.originalUser:
        return L10n.of(context).iapStatusOriginal;
      default:
        return L10n.of(context).iapStatusUnknown;
    }
  }
}
