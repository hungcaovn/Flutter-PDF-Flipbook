import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../services/pdf_loader.dart';
import '../services/book_animation_controller.dart';
import '../services/page_navigation.dart';
import 'book_page.dart';
import 'animated_page.dart';
import 'navigation_controls.dart';

class PdfBookViewer extends StatefulWidget {
  /// Network PDF
  final String? pdfUrl;

  /// Asset PDF, ví dụ: assets/sample.pdf
  final String? assetPath;

  /// Local file path, ví dụ từ file_picker/path_provider
  final String? filePath;

  /// Raw PDF bytes
  final Uint8List? pdfBytes;

  final PdfBookViewerStyle? style;
  final void Function(int currentPage, int totalPages)? onPageChanged;
  final void Function(String error)? onError;
  final bool showNavigationControls;
  final Color? backgroundColor;

  /// Optional proxy URL to bypass CORS restrictions for network PDFs
  final String? proxyUrl;

  const PdfBookViewer({
    Key? key,
    this.pdfUrl,
    this.assetPath,
    this.filePath,
    this.pdfBytes,
    this.style,
    this.onPageChanged,
    this.onError,
    this.showNavigationControls = true,
    this.backgroundColor,
    this.proxyUrl,
  })  : assert(
          (pdfUrl != null ? 1 : 0) +
                  (assetPath != null ? 1 : 0) +
                  (filePath != null ? 1 : 0) +
                  (pdfBytes != null ? 1 : 0) ==
              1,
          'You must provide exactly one PDF source: pdfUrl, assetPath, filePath, or pdfBytes.',
        ),
        super(key: key);

  @override
  _PdfBookViewerState createState() => _PdfBookViewerState();
}

class _PdfBookViewerState extends State<PdfBookViewer>
    with SingleTickerProviderStateMixin {
  late AppState appState;
  late PdfLoader pdfLoader;
  late BookAnimationController animationController;
  late PageNavigation pageNavigation;
  late TransformationController transformationController;
  TextEditingController pageController = TextEditingController();

  @override
  void initState() {
    super.initState();

    appState = AppState();
    appState.addListener(_onPageChanged);

    transformationController = TransformationController();
    transformationController.addListener(_onTransformationChanged);

    pdfLoader = PdfLoader(appState, proxyUrl: widget.proxyUrl);
    animationController = BookAnimationController(
      appState: appState,
      pdfLoader: pdfLoader,
      vsync: this,
    );
    pageNavigation = PageNavigation(
      appState: appState,
      animationController: animationController,
    );

    _loadPdfWithErrorHandling();
  }

  @override
  void didUpdateWidget(PdfBookViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final sourceChanged = _didPdfSourceChange(oldWidget, widget);

    final proxyChanged = oldWidget.proxyUrl != widget.proxyUrl;

    if (sourceChanged || proxyChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          _resetState();

          await _loadPdfSource();
        } catch (e) {
          final errorMsg = 'Failed to load PDF: ${e.toString()}';

          appState.errorMessage = errorMsg;

          widget.onError?.call(errorMsg);
        }
      });
    }
  }

  bool _didPdfSourceChange(PdfBookViewer oldWidget, PdfBookViewer newWidget) {
    return oldWidget.pdfUrl != newWidget.pdfUrl ||
        oldWidget.assetPath != newWidget.assetPath ||
        oldWidget.filePath != newWidget.filePath ||
        !_sameBytes(oldWidget.pdfBytes, newWidget.pdfBytes);
  }

  bool _sameBytes(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;

    if (a == null || b == null) return a == b;

    if (a.length != b.length) return false;

    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }

    return true;
  }

  void _resetState() {
    appState.pageImages = [];
    appState.alreadyAdded = [];
    appState.currentPage = 0;
    appState.currentPageComplete = 0;
    appState.totalPages = 0;
    appState.document = null;
    appState.isLoading = false;
    appState.errorMessage = null;
  }

  Future<void> _loadPdfSource() async {
    if (widget.assetPath != null) {
      await pdfLoader.loadPdfFromAsset(widget.assetPath!);

      return;
    }

    if (widget.filePath != null) {
      await pdfLoader.loadPdfFromFile(widget.filePath!);

      return;
    }

    if (widget.pdfBytes != null) {
      await pdfLoader.loadPdfFromBytes(widget.pdfBytes!);

      return;
    }

    if (widget.pdfUrl != null) {
      await pdfLoader.loadPdfFromUrl(widget.pdfUrl!);

      return;
    }

    throw Exception('No PDF source provided.');
  }

  Future<void> _loadPdfWithErrorHandling() async {
    try {
      appState.errorMessage = null;

      await _loadPdfSource();
    } catch (e) {
      final errorMsg = 'Failed to load PDF: ${e.toString()}';

      appState.errorMessage = errorMsg;

      widget.onError?.call(errorMsg);
    }
  }

  @override
  void dispose() {
    animationController.dispose();
    transformationController.dispose();
    appState.removeListener(_onPageChanged);
    appState.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final Matrix4 matrix = transformationController.value;
    final double scaleX = matrix.getMaxScaleOnAxis();
    bool newZoomed = scaleX > 1.01;

    if (appState.isZoomed != newZoomed) {
      appState.isZoomed = newZoomed;
    }
  }

  int? currentPage;
  int? totalPages;
  void _onPageChanged() {
    if (widget.onPageChanged != null) {
      if (currentPage != appState.currentPageComplete * 2 + 1 ||
          totalPages != appState.currentTotalPages) {
        currentPage = appState.currentPageComplete * 2 + 1;
        totalPages = appState.currentTotalPages;

        /// Defer the callback to the next frame to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onPageChanged!(currentPage!, totalPages!);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? PdfBookViewerStyle.defaultStyle();

    return Scaffold(
      backgroundColor: widget.backgroundColor ??
          style.backgroundColor ??
          Colors.grey.shade800,
      body: Stack(
        children: [
          Column(
            children: [
              ListenableBuilder(
                listenable: appState,
                builder: (context, child) {
                  /// Show error message if there's an error
                  if (appState.errorMessage != null) {
                    return Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Colors.grey.shade600,
                            ),
                            SizedBox(height: 16),
                            Text(
                              appState.errorMessage!,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  /// Show loading indicator if no error and no pages loaded
                  return appState.pageImages.isEmpty
                      ? Expanded(
                          child: Center(
                            child: CircularProgressIndicator(
                              color: style.loadingIndicatorColor,
                            ),
                          ),
                        )
                      : Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final screenWidth = constraints.maxWidth;
                              final screenHeight = constraints.maxHeight;

                              /// Calculate proper aspect ratio for PDF pages
                              final firstRealPage =
                                  appState.pageImages.firstWhere(
                                (page) => page != null,
                              );

                              final pageAspectRatio =
                                  firstRealPage!.width!.toDouble() /
                                      firstRealPage.height!.toDouble();

                              /// Calculate maximum height available (leave some padding)
                              final maxHeight = screenHeight -
                                  (widget.showNavigationControls ? 100 : 50);

                              /// Calculate width for single page based on aspect ratio
                              final singlePageWidth =
                                  maxHeight * pageAspectRatio;

                              /// Calculate total width for both pages (book spread)
                              final totalBookWidth = singlePageWidth * 2;

                              /// Scale down if book is too wide for screen
                              double scaleFactor = 1.0;
                              if (totalBookWidth > screenWidth * 0.9) {
                                scaleFactor =
                                    (screenWidth * 0.9) / totalBookWidth;
                              }

                              /// Apply scale factor
                              final finalPageWidth =
                                  singlePageWidth * scaleFactor;
                              final finalPageHeight = maxHeight * scaleFactor;

                              return MouseRegion(
                                cursor: appState.isZoomed
                                    ? SystemMouseCursors.grab
                                    : SystemMouseCursors.basic,
                                child: InteractiveViewer(
                                  transformationController:
                                      transformationController,
                                  boundaryMargin: EdgeInsets.zero,
                                  minScale: 1.0,
                                  child: Center(
                                    child: Container(
                                      width: finalPageWidth * 2,
                                      height: finalPageHeight,
                                      decoration: style.bookContainerDecoration,
                                      child: Column(
                                        children: [
                                          appState.pageImages.isEmpty
                                              ? Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                    color: style
                                                        .loadingIndicatorColor,
                                                  ),
                                                )
                                              : GestureDetector(
                                                  onHorizontalDragUpdate: appState
                                                          .isZoomed
                                                      ? null
                                                      : pageNavigation
                                                          .handleHorizontalDrag,
                                                  child: Stack(
                                                    children: [
                                                      /// Center divider
                                                      Center(
                                                        child: Container(
                                                          width: style
                                                              .centerDividerWidth,
                                                          color: style
                                                              .centerDividerColor,
                                                        ),
                                                      ),

                                                      /// Book pages
                                                      BookPage(
                                                        appState: appState,
                                                        finalPageWidth:
                                                            finalPageWidth,
                                                        finalPageHeight:
                                                            finalPageHeight,
                                                      ),

                                                      /// Animated page during flip
                                                      if (animationController
                                                          .animationController
                                                          .isAnimating)
                                                        AnimatedPage(
                                                          appState: appState,
                                                          rotationAnimation:
                                                              animationController
                                                                  .rotationAnimation,
                                                          finalPageWidth:
                                                              finalPageWidth,
                                                          finalPageHeight:
                                                              finalPageHeight,
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                },
              ),
              SizedBox(height: widget.showNavigationControls ? 50 : 0),
            ],
          ),
          if (widget.showNavigationControls)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: NavigationControls(
                  appState: appState,
                  pageNavigation: pageNavigation,
                  pdfLoader: pdfLoader,
                  pageController: pageController,
                  style: style.navigationControlsStyle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Styling options for the PDF book viewer
class PdfBookViewerStyle {
  final Color? backgroundColor;
  final Color? bookBackgroundColor;
  final Color? centerDividerColor;
  final double centerDividerWidth;
  final Color? loadingIndicatorColor;
  final BoxDecoration? bookContainerDecoration;
  final NavigationControlsStyle? navigationControlsStyle;

  const PdfBookViewerStyle({
    this.backgroundColor,
    this.bookBackgroundColor,
    this.centerDividerColor,
    this.centerDividerWidth = 5.0,
    this.loadingIndicatorColor,
    this.bookContainerDecoration,
    this.navigationControlsStyle,
  });

  static PdfBookViewerStyle defaultStyle() {
    return PdfBookViewerStyle(
      backgroundColor: Colors.grey.shade800,
      centerDividerColor: Colors.black.withValues(alpha: 0.5),
      loadingIndicatorColor: Colors.blue,
    );
  }
}

/// Styling options for navigation controls
class NavigationControlsStyle {
  final Color buttonColor;
  final Color iconColor;
  final BoxShadow? shadow;

  const NavigationControlsStyle({
    this.buttonColor = Colors.grey,
    this.iconColor = Colors.white,
    this.shadow,
  });
}
