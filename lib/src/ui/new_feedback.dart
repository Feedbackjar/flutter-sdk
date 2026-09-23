import 'package:flutter/material.dart';

import '../feedbackjar_sdk.dart';
import '../models.dart';
import 'theme.dart';

/// The "New feedback" screen. A multiline text field, plus a Name and/or
/// Email field per [WidgetConfig.collectName] / [WidgetConfig.collectEmail]
/// (prefilled from `getIdentity()`, persisted on submit via `setIdentity`).
class NewFeedbackScreen extends StatefulWidget {
  final WidgetConfig config;
  final FbTheme theme;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  /// Called on send to get fresh custom key/value pairs (e.g.
  /// `{'flavor': 'foss'}`) merged into the auto-collected metadata.
  /// Forwarded verbatim to [FeedbackJar.submit]'s `properties` param.
  final Map<String, dynamic>? Function()? properties;

  const NewFeedbackScreen({
    super.key,
    required this.config,
    required this.theme,
    required this.onDone,
    required this.onCancel,
    this.properties,
  });

  @override
  State<NewFeedbackScreen> createState() => _NewFeedbackScreenState();
}

class _NewFeedbackScreenState extends State<NewFeedbackScreen> {
  final _text = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
    FeedbackJar.shared.getIdentity().then((id) {
      if (!mounted) return;
      setState(() {
        if (id.name != null) _name.text = id.name!;
        if (id.email != null) _email.text = id.email!;
      });
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _send() async {
    final content = _text.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    final result = await FeedbackJar.shared.submit(
      content,
      name: widget.config.collectName
          ? (_name.text.trim().isEmpty ? null : _name.text.trim())
          : null,
      email: widget.config.collectEmail
          ? (_email.text.trim().isEmpty ? null : _email.text.trim())
          : null,
      properties: widget.properties?.call(),
    );
    if (!mounted) return;
    setState(() => _sending = false);

    switch (result) {
      case FeedbackSuccess():
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Thanks for your feedback!')),
        );
        widget.onDone();
      case FeedbackFailure(:final error):
        setState(() => _error = errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final canSend = _text.text.trim().isNotEmpty && !_sending;

    return Container(
      color: t.bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TextButton(
                  label: 'Cancel',
                  color: t.textDim,
                  onTap: widget.onCancel,
                ),
                Text(
                  'New feedback',
                  style: TextStyle(
                    fontSize: kFontBody,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(width: 52),
              ],
            ),
            const SizedBox(height: 16),
            _Field(
              theme: t,
              controller: _text,
              hint: 'Share your feedback…',
              minLines: 5,
              maxLines: 8,
            ),
            if (widget.config.collectName) ...[
              const SizedBox(height: 12),
              _Field(theme: t, controller: _name, hint: 'Name'),
            ],
            if (widget.config.collectEmail) ...[
              const SizedBox(height: 12),
              _Field(
                theme: t,
                controller: _email,
                hint: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(fontSize: kFontSmall, color: t.accent),
              ),
            ],
            const SizedBox(height: 16),
            _PrimaryButton(
              theme: t,
              label: 'Send',
              busy: _sending,
              enabled: canSend,
              onTap: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final FbTheme theme;
  final TextEditingController controller;
  final String hint;
  final int? minLines;
  final int maxLines;
  final TextInputType? keyboardType;

  const _Field({
    required this.theme,
    required this.controller,
    required this.hint,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: kFontBody, color: theme.text),
      cursorColor: theme.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: theme.textDim, fontSize: kFontBody),
        filled: true,
        fillColor: theme.fieldBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TextButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            style: TextStyle(fontSize: kFontBody, color: color),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final FbTheme theme;
  final String label;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.theme,
    required this.label,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.accent,
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: kFontBody,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
