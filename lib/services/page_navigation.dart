import 'package:flutter/material.dart';
import '../models/app_state.dart';
import 'book_animation_controller.dart';

class PageNavigation {
  final AppState appState;
  final BookAnimationController animationController;

  PageNavigation({
    required this.appState,
    required this.animationController,
  });

  int get lastSpreadIndex {
    if (appState.pageImages.isEmpty) return 0;
    return ((appState.pageImages.length - 1) / 2).floor();
  }

  bool get isAtLastSpread {
    return appState.currentPageComplete >= lastSpreadIndex;
  }

  bool get isAtFirstSpread {
    return appState.currentPageComplete <= 0;
  }

  void handleHorizontalDrag(DragUpdateDetails details) {
    if (appState.isZoomed || appState.isSwipeInProgress) return;

    if (details.delta.dx < 0) {
      if (!canNavigate(true)) return;

      appState.isSwipeInProgress = true;
      animationController.triggerFlip(true);
    } else if (details.delta.dx > 0) {
      if (!canNavigate(false)) return;

      appState.isSwipeInProgress = true;
      animationController.triggerFlip(false);
    }
  }

  void navigateToPreviousPage(BuildContext context) {
    if (canNavigate(false)) {
      animationController.triggerFlip(false);
    } else {
      _showNavigationError(context, 'Already at the first page');
    }
  }

  void navigateToNextPage(BuildContext context) {
    if (canNavigate(true)) {
      animationController.triggerFlip(true);
    } else {
      _showNavigationError(context, 'Already at the last page');
    }
  }

  bool canNavigate(bool swipeLeft) {
    if (appState.document == null) return false;
    if (appState.pageImages.isEmpty) return false;

    if (swipeLeft) {
      return appState.currentPageComplete < lastSpreadIndex;
    }

    return appState.currentPageComplete > 0;
  }

  void _showNavigationError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
