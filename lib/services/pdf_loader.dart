import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import '../models/app_state.dart';

class PdfLoader {
  final AppState appState;
  final String? proxyUrl;

  PdfLoader(this.appState, {this.proxyUrl});

  Future<Uint8List> fetchPdfAsBytes(String url) async {
    try {
      final uri = Uri.base.resolve(url);

      final response = await http.get(uri);

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }

      throw Exception(
        'Direct fetch failed with status: ${response.statusCode}, body: ${response.body}',
      );
    } catch (e) {
      if (proxyUrl != null && proxyUrl!.isNotEmpty) {
        try {
          final fullProxyUrl = '$proxyUrl${Uri.encodeComponent(url)}';
          final response = await http.get(Uri.parse(fullProxyUrl));

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            return response.bodyBytes;
          }

          throw Exception(
            'Proxy fetch failed with status: ${response.statusCode}, body: ${response.body}',
          );
        } catch (proxyError) {
          throw Exception(
            'Both direct fetch and proxy fetch failed. Direct error: $e, Proxy error: $proxyError',
          );
        }
      }

      throw Exception(
        'Direct fetch failed and no proxy URL provided. Error: $e',
      );
    }
  }

  Future<void> loadPdf(String url) async {
    await loadPdfFromUrl(url);
  }

  Future<void> loadPdfFromUrl(String url) async {
    try {
      appState.isLoading = true;
      final bytes = await fetchPdfAsBytes(url);
      await _openPdfFromBytes(bytes);
    } catch (e) {
      appState.isLoading = false;
      throw Exception("Failed to load PDF from URL: $e");
    }
  }

  Future<void> loadPdfFromAsset(String assetPath) async {
    try {
      appState.isLoading = true;
      final byteData = await rootBundle.load(assetPath);
      await _openPdfFromBytes(byteData.buffer.asUint8List());
    } catch (e) {
      appState.isLoading = false;
      throw Exception("Failed to load PDF from asset: $e");
    }
  }

  Future<void> loadPdfFromFile(String filePath) async {
    try {
      appState.isLoading = true;

      if (kIsWeb) {
        throw Exception(
          'loadPdfFromFile is not supported on Web. Use loadPdfFromBytes instead.',
        );
      }

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist: $filePath');
      }

      await _openPdfFromBytes(await file.readAsBytes());
    } catch (e) {
      appState.isLoading = false;
      throw Exception("Failed to load PDF from file: $e");
    }
  }

  Future<void> loadPdfFromBytes(Uint8List bytes) async {
    try {
      appState.isLoading = true;
      await _openPdfFromBytes(bytes);
    } catch (e) {
      appState.isLoading = false;
      throw Exception("Failed to load PDF from bytes: $e");
    }
  }

  Future<void> _openPdfFromBytes(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw Exception("PDF file is empty or could not be loaded.");
    }

    if (bytes.length < 4 ||
        !(bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46)) {
      throw Exception(
        "Invalid PDF format. File does not appear to be a valid PDF.",
      );
    }

    final document = await PdfDocument.openData(bytes);

    if (document.pagesCount == 0) {
      throw Exception("PDF document has no pages.");
    }

    await _resetDocumentState();

    appState.document = document;
    appState.totalPages = document.pagesCount;
    appState.isLoading = false;

    await loadPages(0, null);
  }

  Future<void> _resetDocumentState() async {
    try {
      await appState.document?.close();
    } catch (_) {}

    appState.pageImages = [];
    appState.alreadyAdded = [];
    appState.currentPage = 0;
    appState.currentPageComplete = 0;
    appState.totalPages = 0;
    appState.showLastPage = true;
    appState.animationComplete = false;
    appState.document = null;
  }

  Future<void> loadPages(int index, int? pageNumber) async {
    if (appState.isLoading || appState.document == null) return;

    appState.isLoading = true;

    try {
      int pagesToLoad;

      if (pageNumber == null) {
        if (index == 0 || index == 1) {
          pagesToLoad = 6;
        } else {
          pagesToLoad = 4 + appState.pageImages.length;
        }
      } else {
        pagesToLoad = 4 + pageNumber;
      }

      for (int i = 0; i < pagesToLoad; i++) {
        if (appState.alreadyAdded.contains(i)) continue;
        if (i >= appState.document!.pagesCount) continue;

        final newAlreadyAdded = List<int>.from(appState.alreadyAdded);
        newAlreadyAdded.add(i);
        appState.alreadyAdded = newAlreadyAdded;

        final page = await appState.document!.getPage(i + 1);

        final image = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.png,
          quality: 100,
          forPrint: true,
        );

        if (image != null) {
          final newPageImages = List<PdfPageImage?>.from(appState.pageImages);

          newPageImages.add(image);

          if (i == 0) {
            // index 1: duplicate page 1 để cover vẫn nằm bên phải ở màn đầu
            newPageImages.add(image);

            // index 2: mặt sau cover là trang trắng
            newPageImages.add(null);
          }

          if (appState.document!.pagesCount == i + 1) {
            final visualPageCount = newPageImages.length;

            if (visualPageCount.isOdd) {
              newPageImages.add(null);
              appState.showLastPage = false;
            }
          }

          appState.pageImages = newPageImages;
        }

        await page.close();
      }

      appState.animationComplete = false;

      if (pageNumber != null) {
        appState.currentPage = (pageNumber / 2).toInt();
        appState.currentPageComplete = appState.currentPage;
      }
    } finally {
      appState.isLoading = false;
    }
  }

  Future<void> navigateToPage(int pageNumber) async {
    if (appState.document == null) return;

    if (pageNumber < 1 || pageNumber > appState.document!.pagesCount) {
      return;
    }

    pageNumber++;

    final targetPage = (pageNumber - 1) ~/ 2;

    appState.pageImages = [];
    appState.alreadyAdded = [];

    await loadPages(targetPage, pageNumber);

    appState.currentPage = targetPage;
    appState.currentPageComplete = targetPage;
  }
}
