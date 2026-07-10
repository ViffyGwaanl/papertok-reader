import 'package:flutter/material.dart';

/// Double-tap wrapper for the AI Chat AppBar title: scrolls the chat list
/// back to the top (E3 batch 3, user request from P1 round six).
/// Single tap and long-press keep their default behavior.
class ChatScrollToTopTitle extends StatelessWidget {
  const ChatScrollToTopTitle({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  void _scrollToTop() {
    if (!controller.hasClients) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _scrollToTop,
      child: child,
    );
  }
}
