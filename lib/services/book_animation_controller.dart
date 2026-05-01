import 'package:flutter/material.dart';
import '../models/app_state.dart';
import 'pdf_loader.dart';

class BookAnimationController {
  final AppState appState;
  final PdfLoader pdfLoader;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  BookAnimationController({
    required this.appState,
    required this.pdfLoader,
    required TickerProvider vsync,
  }) {
    _animationController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1200),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.fastOutSlowIn,
      ),
    );
  }

  AnimationController get animationController => _animationController;
  Animation<double> get rotationAnimation => _rotationAnimation;

  int get lastSpreadIndex {
    if (appState.pageImages.isEmpty) return 0;
    return ((appState.pageImages.length - 1) / 2).floor();
  }

  Future<void> triggerFlip(bool swipeLeft) async {
    if (!canNavigate(swipeLeft)) {
      appState.isSwipeInProgress = false;
      return;
    }

    if (_animationController.isAnimating) {
      await _interruptAndSkipToNext(swipeLeft);
      return;
    }

    if (!appState.isAnimationReady) {
      appState.isSwipeInProgress = false;
      return;
    }

    await _performFlipAnimation(swipeLeft);
  }

  Future<void> _interruptAndSkipToNext(bool swipeLeft) async {
    _animationController.stop();
    _animationController.reset();

    appState.isAnimationReady = false;

    final nextPage = _nextPageIndex(swipeLeft);

    appState.updateMultiple(
      currentPage: nextPage,
      currentPageComplete: nextPage,
      animationComplete: true,
      animationEnd: true,
    );

    await pdfLoader.loadPages(appState.currentPage, null);

    Future.delayed(const Duration(milliseconds: 300), () {
      appState.updateMultiple(
        animationEnd: true,
        animationComplete: false,
        isAnimationReady: true,
        isSwipeInProgress: false,
      );
    });
  }

  int _nextPageIndex(bool swipeLeft) {
    final next = appState.currentPage + (swipeLeft ? 1 : -1);

    if (next < 0) return 0;
    if (next > lastSpreadIndex) return lastSpreadIndex;

    return next;
  }

  bool canNavigate(bool swipeLeft) {
    if (appState.document == null) return false;
    if (appState.pageImages.isEmpty) return false;

    if (swipeLeft) {
      return appState.currentPageComplete < lastSpreadIndex;
    }

    return appState.currentPageComplete > 0;
  }

  Future<void> _performFlipAnimation(bool swipeLeft) async {
    final nextPage = _nextPageIndex(swipeLeft);

    appState.updateMultiple(
      animationEnd: false,
      isSwipingLeft: swipeLeft,
      currentPage: nextPage,
    );

    await _animationController.forward();

    await pdfLoader.loadPages(appState.currentPage, null);

    appState.updateMultiple(
      animationComplete: true,
      currentPageComplete: appState.currentPage,
      animationEnd: true,
      isSwipeInProgress: false,
    );

    _animationController.reset();
  }

  void dispose() {
    _animationController.dispose();
  }
}
