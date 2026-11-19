import 'package:flutter/material.dart';

/// Keeps a dismiss action available even for multiline and numeric keyboards.
class KeyboardDismiss extends StatelessWidget {
  const KeyboardDismiss({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Stack(
      children: [
        child,
        if (inset > 0)
          Positioned(
            right: 12,
            bottom: inset + 8,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(24),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: TextButton.icon(
                onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
                icon: const Icon(Icons.keyboard_hide_outlined),
                label: const Text('Hide keyboard'),
              ),
            ),
          ),
      ],
    );
  }
}
