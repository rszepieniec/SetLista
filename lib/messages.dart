import 'dart:async';

import 'package:flutter/material.dart';

/// Daje dostęp do nakładki (Overlay) aplikacji z dowolnego miejsca - np. gdy
/// zapis do Firestore nie powiedzie się już po zamknięciu ekranu edycji.
final navigatorKey = GlobalKey<NavigatorState>();

OverlayEntry? _current;
Timer? _hideTimer;

/// Krótki komunikat u góry ekranu ("Dołączyłeś do zespołu", "Skopiowano…").
/// Znika sam po kilku sekundach albo po dotknięciu.
void showMessage(String text, {String? actionLabel, VoidCallback? onAction}) {
  final overlay = navigatorKey.currentState?.overlay;
  if (overlay == null) return;
  _hide();
  final entry = OverlayEntry(
    builder: (context) => _TopMessage(
      text: text,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              _hide();
              onAction();
            },
      onDismiss: _hide,
    ),
  );
  _current = entry;
  overlay.insert(entry);
  _hideTimer = Timer(Duration(seconds: actionLabel == null ? 3 : 5), _hide);
}

void _hide() {
  _hideTimer?.cancel();
  _current?.remove();
  _current = null;
}

class _TopMessage extends StatefulWidget {
  const _TopMessage({
    required this.text,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  State<_TopMessage> createState() => _TopMessageState();
}

class _TopMessageState extends State<_TopMessage>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, -1),
              end: Offset.zero,
            ).animate(curve),
            child: FadeTransition(
              opacity: curve,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Material(
                    color: colors.inverseSurface,
                    elevation: 6,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: widget.onDismiss,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          widget.actionLabel == null ? 16 : 4,
                          12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.text,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onInverseSurface,
                                ),
                              ),
                            ),
                            if (widget.actionLabel != null)
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.inversePrimary,
                                ),
                                onPressed: widget.onAction,
                                child: Text(widget.actionLabel!),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
