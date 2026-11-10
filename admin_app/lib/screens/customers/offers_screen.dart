import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../cubit/offers/offers_cubit.dart';
import '../../data/campaign/campaign_model.dart';
import '../../data/customer/customer_model.dart';
import '../../utils/relative_date.dart';
import 'customers_screen.dart' show CustomerAvatar;

const _newCampaignValue = '__new__';
const _whatsappGreen = Color(0xFF25D366);

/// Manual WhatsApp campaign: pick an audience (consenting customers only),
/// write the message, then send one customer at a time.
class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OffersCubit()..load(),
      child: const _OffersView(),
    );
  }
}

class _OffersView extends StatefulWidget {
  const _OffersView();

  @override
  State<_OffersView> createState() => _OffersViewState();
}

class _OffersViewState extends State<_OffersView> {
  final _titleCtrl = TextEditingController(
    text: 'عرض ${DateFormat('d MMM', 'ar').format(DateTime.now())}',
  );
  final _templateCtrl = TextEditingController(text: offerTemplatePresets.first.text);
  final _offerCtrl = TextEditingController();
  final _linkCtrl = TextEditingController(text: kDefaultOfferLink);
  String? _presetLabel = offerTemplatePresets.first.label;

  @override
  void initState() {
    super.initState();
    for (final c in [_templateCtrl, _offerCtrl, _linkCtrl]) {
      c.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in [_titleCtrl, _templateCtrl, _offerCtrl, _linkCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Why sending is blocked, or null when the message is ready.
  String? get _messageProblem {
    final t = _templateCtrl.text.trim();
    if (t.isEmpty) return 'اكتب نص الرسالة أولاً.';
    if (t.contains('{offer}') && _offerCtrl.text.trim().isEmpty) {
      return 'القالب يحتوي {offer}: أدخل نص العرض.';
    }
    return null;
  }

  void _pickCampaign(OffersCubit cubit, String? value) {
    if (value == null) return;
    if (value == _newCampaignValue) {
      cubit.startNewCampaign();
      return;
    }
    final c = cubit.state.recentCampaigns.firstWhere((c) => c.id == value);
    _titleCtrl.text = c.title;
    _templateCtrl.text = c.template;
    _offerCtrl.text = c.offer;
    _linkCtrl.text = c.link;
    _presetLabel = offerTemplatePresets
        .where((p) => p.text.isNotEmpty && p.text == c.template)
        .map((p) => p.label)
        .firstOrNull ?? 'نص حر';
    cubit.openCampaign(c);
  }

  void _send(OffersCubit cubit, CustomerModel c) {
    FocusScope.of(context).unfocus();
    cubit.send(
      customer: c,
      title: _titleCtrl.text.trim().isEmpty
          ? 'عرض ${DateFormat('d MMM', 'ar').format(DateTime.now())}'
          : _titleCtrl.text,
      template: _templateCtrl.text,
      offer: _offerCtrl.text,
      link: _linkCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OffersCubit, OffersState>(
      listenWhen: (_, s) => s.message != null,
      listener: (context, s) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.message!))),
      builder: (context, state) {
        final cubit = context.read<OffersCubit>();
        return Scaffold(
          appBar: AppBar(title: const Text('إرسال عرض')),
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: _body(context, state, cubit),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, OffersState state, OffersCubit cubit) {
    if (state.loading && state.consenting.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.consenting.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(state.error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: cubit.load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    final remaining = state.remaining;
    final problem = _messageProblem;
    final sampleName = remaining.isNotEmpty ? remaining.first.name : 'أحمد';

    return RefreshIndicator(
      onRefresh: cubit.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          _campaignSection(state, cubit),
          const SizedBox(height: 12),
          _section(
            '1. الجمهور',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in OfferAudience.values)
                      ChoiceChip(
                        label: Text('${offerAudienceLabels[a]} (${state.eligibleCount(a)})'),
                        selected: state.audience == a,
                        onSelected: (_) => cubit.setAudience(a),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'الموافقون على العروض فقط، بدون من استلم هذه الحملة.'
                  '${state.hitCap ? ' (يعرض أول $kMaxCampaignCustomers عميل)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _templateSection(sampleName),
          const SizedBox(height: 12),
          if (state.overDailyLimit) ...[
            _warning(
              'أرسلت لـ ${state.sendsToday} عميل اليوم. '
              'الإرسال المكثف قد يعرّض رقمك للحظر، أرسل على دفعات.',
            ),
            const SizedBox(height: 12),
          ],
          _sendList(state, cubit, remaining, problem),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _campaignSection(OffersState state, OffersCubit cubit) {
    return _section(
      'الحملة',
      Column(
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(state.campaignId),
            initialValue: state.isExisting &&
                    state.recentCampaigns.any((c) => c.id == state.campaignId)
                ? state.campaignId
                : _newCampaignValue,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: _newCampaignValue, child: Text('حملة جديدة')),
              for (final c in state.recentCampaigns)
                DropdownMenuItem(
                  value: c.id,
                  child: Text(
                    '${c.title} · ${c.sentCount} مرسلة',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: state.sendingId != null ? null : (v) => _pickCampaign(cubit, v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم الحملة',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateSection(String sampleName) {
    final theme = Theme.of(context);
    final preview = buildOfferMessage(
      template: _templateCtrl.text,
      customerName: sampleName,
      offer: _offerCtrl.text,
      link: _linkCtrl.text,
    );
    return _section(
      '2. نص الرسالة',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(_presetLabel),
            initialValue: _presetLabel,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'قالب جاهز',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in offerTemplatePresets)
                DropdownMenuItem(value: p.label, child: Text(p.label)),
            ],
            onChanged: (label) {
              final p = offerTemplatePresets.firstWhere((p) => p.label == label);
              setState(() => _presetLabel = label);
              _templateCtrl.text = p.text;
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _templateCtrl,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'الرسالة',
              helperText: 'المتغيرات: {name} الاسم الأول، {offer} العرض، {link} الرابط',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _offerCtrl,
            decoration: const InputDecoration(
              labelText: 'العرض {offer}',
              hintText: 'مثال: خصم 20% على الأحذية الرجالية',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _linkCtrl,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'الرابط {link}',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('معاينة', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFDCF8C6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(preview, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _warning(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: Colors.orange.shade900))),
        ],
      ),
    );
  }

  Widget _sendList(
    OffersState state,
    OffersCubit cubit,
    List<CustomerModel> remaining,
    String? problem,
  ) {
    final busy = state.coolingDown || state.sendingId != null;
    return _section(
      '3. قائمة الإرسال (${remaining.length})',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (problem != null) ...[
            Text(problem, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 8),
          ] else if (state.coolingDown) ...[
            Text('انتظر لحظات قبل الإرسال التالي…',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          if (remaining.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('لا يوجد عملاء متبقون في هذه الفئة.', textAlign: TextAlign.center),
            ),
          for (final c in remaining)
            _CustomerSendTile(
              customer: c,
              sending: state.sendingId == c.id,
              onSend: problem != null || busy ? null : () => _send(cubit, c),
              onSkip: state.sendingId == c.id ? null : () => cubit.skip(c),
            ),
          if (state.sentThisSession.isNotEmpty) ...[
            const Divider(height: 24),
            Text('تم الإرسال (${state.sentThisSession.length})',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final c in state.sentThisSession)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.check_circle, color: Colors.green.shade700),
                title: Text(c.name.isEmpty ? c.phone : c.name,
                    overflow: TextOverflow.ellipsis),
                trailing: Text('تم الإرسال',
                    style: TextStyle(color: Colors.green.shade700, fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }
}

class _CustomerSendTile extends StatelessWidget {
  final CustomerModel customer;
  final bool sending;
  final VoidCallback? onSend;
  final VoidCallback? onSkip;
  const _CustomerSendTile({
    required this.customer,
    required this.sending,
    required this.onSend,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = customer;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomerAvatar(name: c.name, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name.isEmpty ? 'بدون اسم' : c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(c.phone, textDirection: TextDirection.ltr, style: muted),
                    if (c.lastContactedAt != null)
                      Text('آخر تواصل ${relativeDateAr(c.lastContactedAt!)}', style: muted),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onSkip, child: const Text('تخطي')),
              const SizedBox(width: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _whatsappGreen,
                  foregroundColor: Colors.white,
                ),
                onPressed: onSend,
                icon: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send, size: 16),
                label: const Text('إرسال'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
