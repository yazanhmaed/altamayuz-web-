import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/campaign/campaign_model.dart';
import '../../data/customer/customer_model.dart';

/// Safety cap on how many consenting customers one campaign screen loads.
const int kMaxCampaignCustomers = 1000;

class OffersState {
  final bool loading;
  final String? error;

  /// Every customer with marketingConsent == true (up to the cap).
  final List<CustomerModel> consenting;
  final bool hitCap;

  final List<CampaignSummary> recentCampaigns;

  /// Current campaign. A new one gets an ID up front; its document is only
  /// written on the first send.
  final String campaignId;
  final bool isExisting;
  final OfferAudience audience;

  /// Phones already sent for this campaign (stored).
  final Set<String> sentPhones;

  /// Sent during this visit, shown as "تم الإرسال".
  final List<CustomerModel> sentThisSession;

  /// Skipped during this visit only (not stored).
  final Set<String> skipped;

  final int sendsToday;
  final bool coolingDown;
  final String? sendingId;

  /// One-shot snackbar text.
  final String? message;

  const OffersState({
    this.loading = true,
    this.error,
    this.consenting = const [],
    this.hitCap = false,
    this.recentCampaigns = const [],
    required this.campaignId,
    this.isExisting = false,
    this.audience = OfferAudience.allConsenting,
    this.sentPhones = const {},
    this.sentThisSession = const [],
    this.skipped = const {},
    this.sendsToday = 0,
    this.coolingDown = false,
    this.sendingId,
    this.message,
  });

  /// Customers in [a] not yet sent for this campaign (live count per chip).
  int eligibleCount(OfferAudience a) => consenting
      .where((c) => audienceIncludes(a, c) && !sentPhones.contains(c.id))
      .length;

  /// The send list: current audience, minus sent and skipped.
  List<CustomerModel> get remaining => consenting
      .where((c) =>
          audienceIncludes(audience, c) &&
          !sentPhones.contains(c.id) &&
          !skipped.contains(c.id))
      .toList();

  bool get overDailyLimit => sendsToday >= kDailySoftSendLimit;

  OffersState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<CustomerModel>? consenting,
    bool? hitCap,
    List<CampaignSummary>? recentCampaigns,
    String? campaignId,
    bool? isExisting,
    OfferAudience? audience,
    Set<String>? sentPhones,
    List<CustomerModel>? sentThisSession,
    Set<String>? skipped,
    int? sendsToday,
    bool? coolingDown,
    String? sendingId,
    bool clearSending = false,
    String? message,
  }) {
    return OffersState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      consenting: consenting ?? this.consenting,
      hitCap: hitCap ?? this.hitCap,
      recentCampaigns: recentCampaigns ?? this.recentCampaigns,
      campaignId: campaignId ?? this.campaignId,
      isExisting: isExisting ?? this.isExisting,
      audience: audience ?? this.audience,
      sentPhones: sentPhones ?? this.sentPhones,
      sentThisSession: sentThisSession ?? this.sentThisSession,
      skipped: skipped ?? this.skipped,
      sendsToday: sendsToday ?? this.sendsToday,
      coolingDown: coolingDown ?? this.coolingDown,
      sendingId: clearSending ? null : (sendingId ?? this.sendingId),
      message: message,
    );
  }
}

/// Manual WhatsApp offers: opens WhatsApp with a prefilled message for one
/// customer at a time and records the send. No bulk sending.
class OffersCubit extends Cubit<OffersState> {
  OffersCubit()
      : super(OffersState(
          campaignId: FirebaseFirestore.instance.collection('campaigns').doc().id,
        ));

  final _db = FirebaseFirestore.instance;
  Timer? _cooldown;

  CollectionReference<Map<String, dynamic>> get _campaigns =>
      _db.collection('campaigns');

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final now = DateTime.now();
      final results = await Future.wait([
        _db
            .collection('customers')
            .where('marketingConsent', isEqualTo: true)
            .limit(kMaxCampaignCustomers)
            .get(),
        _campaigns.orderBy('createdAt', descending: true).limit(20).get(),
        _db
            .collection('customers')
            .where('lastContactedAt',
                isGreaterThanOrEqualTo:
                    Timestamp.fromDate(DateTime(now.year, now.month, now.day)))
            .count()
            .get(),
      ]);
      final customers = (results[0] as QuerySnapshot<Map<String, dynamic>>)
          .docs
          .map(CustomerModel.fromDoc)
          .toList()
        ..sort((a, b) => (b.lastOrderAt ?? DateTime(0))
            .compareTo(a.lastOrderAt ?? DateTime(0)));
      final campaigns = (results[1] as QuerySnapshot<Map<String, dynamic>>)
          .docs
          .map(CampaignSummary.fromDoc)
          .toList();
      final today = (results[2] as AggregateQuerySnapshot).count ?? 0;
      if (isClosed) return;
      emit(state.copyWith(
        loading: false,
        consenting: customers,
        hitCap: customers.length >= kMaxCampaignCustomers,
        recentCampaigns: campaigns,
        sendsToday: today,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  void setAudience(OfferAudience a) => emit(state.copyWith(audience: a));

  void startNewCampaign() {
    emit(state.copyWith(
      campaignId: _campaigns.doc().id,
      isExisting: false,
      sentPhones: const {},
      sentThisSession: const [],
      skipped: const {},
    ));
  }

  /// Re-opens a campaign: its already-sent customers are excluded.
  Future<void> openCampaign(CampaignSummary c) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final sent = await _campaigns.doc(c.id).collection('sent').get();
      if (isClosed) return;
      emit(state.copyWith(
        loading: false,
        campaignId: c.id,
        isExisting: true,
        audience: c.audience,
        sentPhones: sent.docs.map((d) => d.id).toSet(),
        sentThisSession: const [],
        skipped: const {},
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  void skip(CustomerModel c) =>
      emit(state.copyWith(skipped: {...state.skipped, c.id}));

  /// Opens WhatsApp for [customer] and records the send. Re-checks consent
  /// first, so a customer who opted out meanwhile is never messaged.
  Future<void> send({
    required CustomerModel customer,
    required String title,
    required String template,
    required String offer,
    required String link,
  }) async {
    if (state.coolingDown || state.sendingId != null) return;
    emit(state.copyWith(sendingId: customer.id));
    try {
      final customerRef = _db.collection('customers').doc(customer.id);
      final live = await customerRef.get();
      if (live.data()?['marketingConsent'] != true) {
        _dropCustomer(customer.id);
        emit(state.copyWith(
          clearSending: true,
          message: 'هذا العميل ألغى موافقته على العروض.',
        ));
        return;
      }

      final message = buildOfferMessage(
        template: template,
        customerName: customer.name,
        offer: offer,
        link: link,
      );
      final launched = await launchUrl(
        whatsappMessageUri(customer.phone, message),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw Exception('تعذر فتح واتساب.');

      final campaignRef = _campaigns.doc(state.campaignId);
      final sentRef = campaignRef.collection('sent').doc(customer.id);
      await _db.runTransaction((tx) async {
        final sentSnap = await tx.get(sentRef);
        final campaignSnap = await tx.get(campaignRef);
        if (sentSnap.exists) return; // already recorded (double tap)
        final now = FieldValue.serverTimestamp();
        tx.set(
          campaignRef,
          {
            'title': title.trim(),
            'audience': state.audience.name,
            'template': template,
            'offer': offer.trim(),
            'link': link.trim().isEmpty ? kDefaultOfferLink : link.trim(),
            'sentCount': FieldValue.increment(1),
            'updatedAt': now,
            if (!campaignSnap.exists) 'createdAt': now,
          },
          SetOptions(merge: true),
        );
        tx.set(sentRef, {'sentAt': now});
        tx.update(customerRef, {'lastContactedAt': now});
      });

      if (isClosed) return;
      final contactedToday = customer.lastContactedAt != null &&
          _isSameDay(customer.lastContactedAt!, DateTime.now());
      emit(state.copyWith(
        clearSending: true,
        isExisting: true,
        sentPhones: {...state.sentPhones, customer.id},
        sentThisSession: [customer, ...state.sentThisSession],
        sendsToday: contactedToday ? state.sendsToday : state.sendsToday + 1,
        coolingDown: true,
      ));
      _cooldown?.cancel();
      _cooldown = Timer(kSendCooldown, () {
        if (!isClosed) emit(state.copyWith(coolingDown: false));
      });
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        clearSending: true,
        message: e.toString().replaceFirst('Exception: ', ''),
      ));
    }
  }

  void _dropCustomer(String id) {
    emit(state.copyWith(
      consenting: state.consenting.where((c) => c.id != id).toList(),
    ));
  }

  @override
  Future<void> close() {
    _cooldown?.cancel();
    return super.close();
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
