import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/customer/customer_model.dart';
import '../../../utils/jordan_phone.dart';

/// Like [JordanPhoneInputFormatter] (bare 9 local digits), but also accepts a
/// pasted/typed country prefix: `07XXXXXXXX`, `7XXXXXXXX`, `9627XXXXXXXX`,
/// `+9627XXXXXXXX`, `009627XXXXXXXX`, with Arabic-Indic digits.
class _AnyJordanPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var d = toAsciiDigits(newValue.text).replaceAll(RegExp(r'\D'), '');
    d = d.replaceFirst(RegExp(r'^00'), '');
    // No Jordanian local number starts with 96, so a leading 962 followed by
    // more digits is always the country code.
    if (d.startsWith('962') && d.length > 3) d = d.substring(3);
    d = d.replaceFirst(RegExp(r'^0+'), '');
    if (d.length > jordanLocalNumberLength) {
      d = d.substring(0, jordanLocalNumberLength);
    }
    return TextEditingValue(
      text: d,
      selection: TextSelection.collapsed(offset: d.length),
    );
  }
}

/// Phone field of the create-order form with customer suggestions.
///
/// From 3 local digits (= 4 typed with the leading 0), debounced 300 ms, it
/// looks up `customers` by document-ID prefix (`+962…`, max 5, never the whole
/// collection) and shows the matches in an overlay under the field. Picking
/// one calls [onSelected]. A lookup failure is silent — typing continues.
class CustomerPhoneField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<CustomerModel> onSelected;

  const CustomerPhoneField({
    super.key,
    required this.controller,
    required this.onSelected,
  });

  @override
  State<CustomerPhoneField> createState() => _CustomerPhoneFieldState();
}

class _CustomerPhoneFieldState extends State<CustomerPhoneField> {
  static const _minDigits = 3;
  static const _debounce = Duration(milliseconds: 300);

  final _focus = FocusNode();
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  Timer? _timer;
  int _request = 0;
  bool _loading = false;
  List<CustomerModel> _results = const [];
  String _lastQueried = '';

  /// Text set by a selection; no lookup for it.
  String? _suppress;
  double _fieldWidth = 0;
  double _lastInset = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onText);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) {
      _hide();
    } else if (_results.isNotEmpty) {
      _overlay.show();
    }
  }

  void _hide() {
    if (_overlay.isShowing) _overlay.hide();
  }

  void _onText() {
    final text = widget.controller.text;
    if (text == _lastQueried) return;
    _timer?.cancel();
    if (text == _suppress || text.length < _minDigits) {
      _request++; // drop any in-flight lookup
      _lastQueried = text;
      _results = const [];
      _hide();
      if (_loading) setState(() => _loading = false);
      return;
    }
    _timer = Timer(_debounce, () => _lookup(text));
  }

  Future<void> _lookup(String local) async {
    final id = ++_request;
    _lastQueried = local;
    setState(() => _loading = true);
    final prefix = '$jordanDialCode$local';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('customers')
          .orderBy(FieldPath.documentId)
          .startAt([prefix])
          .endAt(['$prefix'])
          .limit(5)
          .get();
      if (!mounted || id != _request) return;
      setState(() {
        _loading = false;
        _results = snap.docs.map(CustomerModel.fromDoc).toList();
      });
      if (_results.isNotEmpty && _focus.hasFocus) {
        _overlay.show();
      } else {
        _hide();
      }
    } catch (e) {
      debugPrint('customer lookup failed: $e');
      if (mounted && id == _request) {
        setState(() {
          _loading = false;
          _results = const [];
        });
        _hide();
      }
    }
  }

  void _select(CustomerModel c) {
    final local = jordanPhoneToLocal(c.phone.isNotEmpty ? c.phone : c.id);
    _suppress = local;
    _results = const [];
    _hide();
    widget.onSelected(c);
    // The parent sets the phone text; make sure it lands even if it doesn't.
    if (widget.controller.text != local) widget.controller.text = local;
  }

  @override
  Widget build(BuildContext context) {
    // Close the list when the on-screen keyboard is dismissed.
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (_lastInset > 0 && inset == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hide();
      });
    }
    _lastInset = inset;

    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: _buildOverlay,
      child: CompositedTransformTarget(
        link: _link,
        child: LayoutBuilder(builder: (context, constraints) {
          _fieldWidth = constraints.maxWidth;
          return TextFormField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            inputFormatters: [_AnyJordanPhoneFormatter()],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              hintText: '7XXXXXXXX',
              hintTextDirection: TextDirection.ltr,
              border: const OutlineInputBorder(),
              prefixIcon: const Padding(
                padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: 1,
                  child: Text('🇯🇴 $jordanDialCode',
                      style: TextStyle(fontSize: 15)),
                ),
              ),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            validator: (v) =>
                (v == null || v.trim().length != jordanLocalNumberLength)
                    ? 'أدخل رقمًا من 9 أرقام'
                    : null,
          );
        }),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      // Positioned by the follower; these just give it a box to live in.
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 4),
        // Counts as part of the field for tap-outside purposes.
        child: TextFieldTapRegion(
          child: SizedBox(
            width: _fieldWidth,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = _results[i];
                    final phone =
                        '0${jordanPhoneToLocal(c.phone.isNotEmpty ? c.phone : c.id)}';
                    final details = [
                      if (c.city.isNotEmpty) c.city,
                      if (c.ordersCount > 0) 'طلبات سابقة: ${c.ordersCount}',
                    ].join(' · ');
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(
                        c.name.isEmpty ? phone : c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: phone),
                          if (details.isNotEmpty) TextSpan(text: ' · $details'),
                        ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () => _select(c),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
