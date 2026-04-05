import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/customers/domain/customer_model.dart';
import '../../features/payments/domain/payment_model.dart';
import '../../features/rooms/domain/room_model.dart';
import '../../features/transactions/domain/transaction_model.dart';

// ── Colour palette (PDF uses 0.0–1.0 floats) ──────────────────────────────────

class _C {
  static const primary      = PdfColor(0.082, 0.396, 0.753);   // #155FBF ≈ Blue 800
  static const primaryLight = PdfColor(0.890, 0.949, 1.000);   // #E3F2FD
  static const success      = PdfColor(0.180, 0.490, 0.196);   // #2E7D32
  static const warning      = PdfColor(0.902, 0.318, 0.000);   // #E65100
  static const error        = PdfColor(0.827, 0.184, 0.184);   // #D32F2F
  static const grey         = PdfColor(0.459, 0.459, 0.459);   // #757575
  static const greyLight    = PdfColor(0.961, 0.961, 0.961);   // #F5F5F5
  static const border       = PdfColor(0.878, 0.878, 0.878);   // #E0E0E0
  static const white        = PdfColors.white;
  static const black        = PdfColors.black;
}

// ── PdfService ─────────────────────────────────────────────────────────────────

class PdfService {
  PdfService._();

  static final _idr =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _dateLong = DateFormat('d MMMM yyyy', 'id_ID');
  static final _dtShort  = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

  // ── Public API ──────────────────────────────────────────────────────────────

  static Future<Uint8List> generateInvoice({
    required TransactionModel transaction,
    CustomerModel? customer,
    List<RoomModel> rooms = const [],
    required List<PaymentModel> payments,
  }) async {
    final doc = pw.Document(
      title:  'Invoice ${transaction.bookingCode}',
      author: 'Baiti App',
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 44),
        build: (_) => _InvoicePage(
          t: transaction,
          customer: customer,
          rooms: rooms,
          payments: payments,
        ).build(),
      ),
    );
    return doc.save();
  }

  static Future<Uint8List> generateReceipt({
    required TransactionModel transaction,
    CustomerModel? customer,
    List<RoomModel> rooms = const [],
    required List<PaymentModel> payments,
  }) async {
    final doc = pw.Document(
      title:  'Kwitansi ${transaction.bookingCode}',
      author: 'Baiti App',
    );
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 44),
        build: (_) => _ReceiptPage(
          t: transaction,
          customer: customer,
          rooms: rooms,
          payments: payments,
        ).build(),
      ),
    );
    return doc.save();
  }

  // ── Shared helpers ──────────────────────────────────────────────────────────

  static String _fmt(double v)       => _idr.format(v);
  static String _fmtDate(DateTime d) => _dateLong.format(d);
  static String _fmtDt(DateTime d)   => _dtShort.format(d);
  static String _now() => DateFormat('d MMMM yyyy, HH:mm', 'id_ID').format(DateTime.now());

  /// Wide horizontal rule.
  static pw.Widget _rule({double thickness = 0.5, PdfColor? color}) =>
      pw.Divider(thickness: thickness, color: color ?? _C.border);

  /// Label + value in a standard info row.
  static pw.Widget _infoRow(String label, String value, {bool bold = false}) =>
      pw.Row(
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                font: pw.Font.helvetica(),
                fontSize: 9,
                color: _C.grey,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                font: bold ? pw.Font.helveticaBold() : pw.Font.helvetica(),
                fontSize: 9,
              ),
            ),
          ),
        ],
      );

  /// Gray section-header band.
  static pw.Widget _sectionBar(String text) =>
      pw.Container(
        width: double.infinity,
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        color: _C.greyLight,
        child: pw.Text(
          text.toUpperCase(),
          style: pw.TextStyle(
            font: pw.Font.helveticaBold(),
            fontSize: 8,
            letterSpacing: 0.8,
            color: _C.grey,
          ),
        ),
      );

  /// Status badge (coloured rounded-rect label).
  static pw.Widget _statusBadge(PaymentStatus status) {
    final (bg, fg, label) = switch (status) {
      PaymentStatus.paid    => (_C.success, _C.white, 'LUNAS'),
      PaymentStatus.partial => (_C.warning, _C.white, 'SEBAGIAN'),
      PaymentStatus.unpaid  => (_C.error,   _C.white, 'BELUM BAYAR'),
    };
    return pw.Container(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          font: pw.Font.helveticaBold(),
          fontSize: 8,
          color: fg,
        ),
      ),
    );
  }

  /// Common branded header bar (blue band with app name + doc type).
  static pw.Widget _headerBand(String docType) =>
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        color: _C.primary,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            // Brand
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Baiti App',
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 14,
                    color: _C.white,
                    letterSpacing: 1.5,
                  ),
                ),
                pw.Text(
                  'Manajemen Penginapan',
                  style: pw.TextStyle(
                    font: pw.Font.helvetica(),
                    fontSize: 8,
                    color: PdfColor(0.8, 0.9, 1.0),
                  ),
                ),
              ],
            ),
            // Document type
            pw.Text(
              docType,
              style: pw.TextStyle(
                font: pw.Font.helveticaBold(),
                fontSize: 22,
                color: _C.white,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      );

  /// Footer: printed timestamp.
  static pw.Widget _footer() =>
      pw.Column(
        children: [
          _rule(),
          pw.SizedBox(height: 4),
          pw.Text(
            'Dicetak: ${_now()}  •  Baiti App',
            style: pw.TextStyle(
              font: pw.Font.helveticaOblique(),
              fontSize: 7,
              color: _C.grey,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      );

  /// Payment table row helper.
  static List<pw.TableRow> _paymentRows(List<PaymentModel> payments) =>
      payments.map((p) {
        return pw.TableRow(
          children: [
            _cell(_fmtDt(p.paidAt), color: _C.grey),
            _cell(p.method.label, color: _C.grey),
            _cellR(_fmt(p.amount)),
            _cell(p.notes.isNotEmpty ? p.notes : '—', color: _C.grey),
          ],
        );
      }).toList();

  static pw.Widget _cell(String text,
          {PdfColor? color, bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            font: bold ? pw.Font.helveticaBold() : pw.Font.helvetica(),
            fontSize: 8.5,
            color: color ?? _C.black,
          ),
        ),
      );

  static pw.Widget _cellR(String text, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            font: bold ? pw.Font.helveticaBold() : pw.Font.helvetica(),
            fontSize: 8.5,
          ),
        ),
      );
}

// ── Invoice page builder ───────────────────────────────────────────────────────

class _InvoicePage {
  const _InvoicePage({
    required this.t,
    required this.customer,
    required this.rooms,
    required this.payments,
  });

  final TransactionModel t;
  final CustomerModel? customer;
  final List<RoomModel> rooms;
  final List<PaymentModel> payments;

  pw.Widget build() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        PdfService._headerBand('INVOICE'),
        pw.SizedBox(height: 16),

        // ── Invoice meta ─────────────────────────────────────────────────────
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left: booking code + date
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'No. Invoice',
                  style: pw.TextStyle(
                    font: pw.Font.helvetica(),
                    fontSize: 8,
                    color: _C.grey,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  t.bookingCode,
                  style: pw.TextStyle(
                    font: pw.Font.courier(),
                    fontSize: 13,
                    color: _C.primary,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Tanggal: ${PdfService._fmtDate(t.createdAt)}',
                  style: pw.TextStyle(
                    font: pw.Font.helvetica(),
                    fontSize: 8.5,
                    color: _C.grey,
                  ),
                ),
              ],
            ),
            // Right: status badge
            PdfService._statusBadge(t.paymentStatus),
          ],
        ),
        pw.SizedBox(height: 18),

        // ── Customer ──────────────────────────────────────────────────────────
        PdfService._sectionBar('Kepada'),
        pw.SizedBox(height: 8),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Column(
            children: [
              PdfService._infoRow('Nama', customer?.name ?? t.customerName, bold: true),
              if ((customer?.nik ?? '').isNotEmpty) ...[
                pw.SizedBox(height: 5),
                PdfService._infoRow('NIK', customer!.nik),
              ],
              if ((customer?.phone ?? '').isNotEmpty) ...[
                pw.SizedBox(height: 5),
                PdfService._infoRow('Telepon', customer!.phone),
              ],
              if ((customer?.address ?? '').isNotEmpty) ...[
                pw.SizedBox(height: 5),
                PdfService._infoRow('Alamat', customer!.address),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 18),

        // ── Stay details ──────────────────────────────────────────────────────
        PdfService._sectionBar('Detail Pemesanan'),
        pw.SizedBox(height: 4),

        // Room table
        _roomTable(),
        pw.SizedBox(height: 8),

        // Check-in / check-out / nights
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  children: [
                    PdfService._infoRow('Check-in',  PdfService._fmtDate(t.checkIn)),
                    pw.SizedBox(height: 4),
                    PdfService._infoRow('Check-out', PdfService._fmtDate(t.checkOut)),
                    pw.SizedBox(height: 4),
                    PdfService._infoRow('Lama menginap', '${t.nights} malam'),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 18),

        // ── Totals ────────────────────────────────────────────────────────────
        _totalsSection(),
        pw.SizedBox(height: 18),

        // ── Payment history ───────────────────────────────────────────────────
        if (payments.isNotEmpty) ...[
          PdfService._sectionBar('Riwayat Pembayaran'),
          pw.SizedBox(height: 4),
          _paymentsTable(),
          pw.SizedBox(height: 18),
        ],

        // ── Notes ─────────────────────────────────────────────────────────────
        if (t.notes.isNotEmpty) ...[
          PdfService._sectionBar('Catatan'),
          pw.SizedBox(height: 6),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4),
            child: pw.Text(
              t.notes,
              style: pw.TextStyle(
                font: pw.Font.helveticaOblique(),
                fontSize: 8.5,
                color: _C.grey,
              ),
            ),
          ),
          pw.SizedBox(height: 18),
        ],

        pw.Spacer(),
        PdfService._footer(),
      ],
    );
  }

  pw.Widget _roomTable() {
    // Build one data row per room; fall back to summary row when no room data.
    final List<pw.TableRow> dataRows;

    if (rooms.isNotEmpty) {
      dataRows = rooms.map((r) {
        final subtotal = r.pricePerNight * t.nights;
        return pw.TableRow(
          children: [
            PdfService._cell(r.name),
            PdfService._cellR('${t.nights}'),
            PdfService._cellR(PdfService._fmt(r.pricePerNight)),
            PdfService._cellR(PdfService._fmt(subtotal)),
          ],
        );
      }).toList();

      // Total row (only when multiple rooms)
      if (rooms.length > 1) {
        dataRows.add(
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _C.greyLight),
            children: [
              PdfService._cell(
                '${rooms.length} kamar × ${t.nights} malam',
                bold: true,
              ),
              PdfService._cell(''),
              PdfService._cell('Total', bold: true),
              PdfService._cellR(PdfService._fmt(t.totalPrice), bold: true),
            ],
          ),
        );
      }
    } else {
      // Fallback: no room objects, use transaction summary
      final pricePerNight = t.nights > 0 ? t.totalPrice / t.nights : 0.0;
      dataRows = [
        pw.TableRow(
          children: [
            PdfService._cell(t.roomName),
            PdfService._cellR('${t.nights}'),
            PdfService._cellR(PdfService._fmt(pricePerNight)),
            PdfService._cellR(PdfService._fmt(t.totalPrice), bold: true),
          ],
        ),
      ];
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _C.border, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FixedColumnWidth(40),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(2),
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _C.greyLight),
          children: [
            PdfService._cell('Kamar', bold: true),
            PdfService._cell('Mlm', bold: true),
            PdfService._cellR('Harga/Malam', bold: true),
            PdfService._cellR('Subtotal', bold: true),
          ],
        ),
        ...dataRows,
      ],
    );
  }

  pw.Widget _totalsSection() {
    final rows = <_TotalRow>[
      _TotalRow('Total', PdfService._fmt(t.totalPrice)),
      _TotalRow('Sudah Dibayar', PdfService._fmt(t.dpAmount)),
      _TotalRow(
        'Sisa Tagihan',
        PdfService._fmt(t.remaining),
        bold: true,
        highlight: t.remaining > 0,
      ),
    ];

    return pw.Column(
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          if (i == rows.length - 1) PdfService._rule(),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.SizedBox(
                  width: 130,
                  child: pw.Text(
                    rows[i].label,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      font: rows[i].bold
                          ? pw.Font.helveticaBold()
                          : pw.Font.helvetica(),
                      fontSize: rows[i].bold ? 10 : 9,
                      color: _C.grey,
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.SizedBox(
                  width: 110,
                  child: pw.Text(
                    rows[i].value,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      font: rows[i].bold
                          ? pw.Font.helveticaBold()
                          : pw.Font.helvetica(),
                      fontSize: rows[i].bold ? 11 : 9.5,
                      color: rows[i].highlight ? _C.error : _C.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  pw.Widget _paymentsTable() {
    return pw.Table(
      border: pw.TableBorder.all(color: _C.border, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FixedColumnWidth(70),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _C.greyLight),
          children: [
            PdfService._cell('Tanggal & Waktu', bold: true),
            PdfService._cell('Metode', bold: true),
            PdfService._cellR('Jumlah', bold: true),
            PdfService._cell('Keterangan', bold: true),
          ],
        ),
        ...PdfService._paymentRows(payments),
      ],
    );
  }
}

// ── Receipt (Kwitansi) page builder ───────────────────────────────────────────

class _ReceiptPage {
  const _ReceiptPage({
    required this.t,
    required this.customer,
    required this.rooms,
    required this.payments,
  });

  final TransactionModel t;
  final CustomerModel? customer;
  final List<RoomModel> rooms;
  final List<PaymentModel> payments;

  pw.Widget build() {
    final totalPaid = payments.fold(0.0, (s, p) => s + p.amount);
    final effectivePaid = totalPaid > 0 ? totalPaid : t.dpAmount;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        PdfService._headerBand('KWITANSI'),
        pw.SizedBox(height: 6),

        // Receipt number (right-aligned, under header)
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'No. ${t.bookingCode}',
            style: pw.TextStyle(
              font: pw.Font.courier(),
              fontSize: 9,
              color: _C.grey,
            ),
          ),
        ),
        pw.SizedBox(height: 18),

        // ── "Sudah terima dari" ───────────────────────────────────────────────
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: _C.primaryLight,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Sudah terima dari',
                style: pw.TextStyle(
                  font: pw.Font.helvetica(),
                  fontSize: 9,
                  color: _C.grey,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                customer?.name ?? t.customerName,
                style: pw.TextStyle(
                  font: pw.Font.helveticaBold(),
                  fontSize: 13,
                  color: _C.primary,
                ),
              ),
              if ((customer?.phone ?? '').isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  customer!.phone,
                  style: pw.TextStyle(
                    font: pw.Font.helvetica(),
                    fontSize: 9,
                    color: _C.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 16),

        // ── Amount box ────────────────────────────────────────────────────────
        pw.Text(
          'Uang sejumlah',
          style: pw.TextStyle(
            font: pw.Font.helvetica(),
            fontSize: 9,
            color: _C.grey,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _C.primary, width: 2),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                '✦  ${PdfService._fmt(effectivePaid)}  ✦',
                style: pw.TextStyle(
                  font: pw.Font.helveticaBold(),
                  fontSize: 20,
                  color: _C.primary,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 18),

        // ── Payment for ───────────────────────────────────────────────────────
        PdfService._sectionBar('Untuk Pembayaran'),
        pw.SizedBox(height: 8),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Room list — one info row per room
              if (rooms.isNotEmpty) ...[
                for (int i = 0; i < rooms.length; i++) ...[
                  PdfService._infoRow(
                    rooms.length == 1 ? 'Kamar' : 'Kamar ${i + 1}',
                    '${rooms[i].name}  (${PdfService._fmt(rooms[i].pricePerNight)}/malam)',
                    bold: true,
                  ),
                  if (i < rooms.length - 1) pw.SizedBox(height: 4),
                ],
              ] else ...[
                PdfService._infoRow('Kamar', t.roomName, bold: true),
              ],
              pw.SizedBox(height: 5),
              PdfService._infoRow('Check-in',  PdfService._fmtDate(t.checkIn)),
              pw.SizedBox(height: 5),
              PdfService._infoRow('Check-out',
                  '${PdfService._fmtDate(t.checkOut)} (${t.nights} malam)'),
              pw.SizedBox(height: 5),
              PdfService._infoRow(
                  'Total Sewa', PdfService._fmt(t.totalPrice)),
            ],
          ),
        ),
        pw.SizedBox(height: 18),

        // ── Payment breakdown ─────────────────────────────────────────────────
        if (payments.isNotEmpty) ...[
          PdfService._sectionBar('Rincian Pembayaran'),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: _C.border, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FixedColumnWidth(70),
              2: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _C.greyLight),
                children: [
                  PdfService._cell('Tanggal & Waktu', bold: true),
                  PdfService._cell('Metode', bold: true),
                  PdfService._cellR('Jumlah', bold: true),
                ],
              ),
              ...payments.map((p) => pw.TableRow(children: [
                    PdfService._cell(PdfService._fmtDt(p.paidAt),
                        color: _C.grey),
                    PdfService._cell(p.method.label, color: _C.grey),
                    PdfService._cellR(PdfService._fmt(p.amount)),
                  ])),
              // Total row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _C.greyLight),
                children: [
                  PdfService._cell(''),
                  PdfService._cell('Total Diterima',
                      bold: true, color: _C.success),
                  PdfService._cellR(PdfService._fmt(effectivePaid),
                      bold: true),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),
        ] else ...[
          // No payments recorded — show dp_amount if any
          if (t.dpAmount > 0) ...[
            PdfService._rule(),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Diterima',
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 10,
                    color: _C.success,
                  ),
                ),
                pw.Text(
                  PdfService._fmt(t.dpAmount),
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 10,
                    color: _C.success,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
          ],
        ],

        // ── Remaining (if partial) ────────────────────────────────────────────
        if (t.remaining > 0) ...[
          pw.Container(
            width: double.infinity,
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColor(1.0, 0.945, 0.878), // amber 50
              borderRadius:
                  const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Sisa yang belum dibayar',
                  style: pw.TextStyle(
                    font: pw.Font.helvetica(),
                    fontSize: 9,
                    color: _C.warning,
                  ),
                ),
                pw.Text(
                  PdfService._fmt(t.remaining),
                  style: pw.TextStyle(
                    font: pw.Font.helveticaBold(),
                    fontSize: 9,
                    color: _C.warning,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
        ],

        // ── Signature area ────────────────────────────────────────────────────
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  PdfService._fmtDate(DateTime.now()),
                  style: pw.TextStyle(
                    font: pw.Font.helvetica(),
                    fontSize: 9,
                    color: _C.grey,
                  ),
                ),
                pw.SizedBox(height: 50),
                pw.SizedBox(
                  width: 140,
                  child: pw.Divider(thickness: 0.5, color: _C.black),
                ),
                pw.Text(
                  'Hormat Kami',
                  style: pw.TextStyle(
                    font: pw.Font.helvetica(),
                    fontSize: 9,
                    color: _C.grey,
                  ),
                ),
              ],
            ),
          ],
        ),

        pw.Spacer(),
        PdfService._footer(),
      ],
    );
  }
}

// ── Private helpers ────────────────────────────────────────────────────────────

class _TotalRow {
  const _TotalRow(this.label, this.value,
      {this.bold = false, this.highlight = false});
  final String label;
  final String value;
  final bool bold;
  final bool highlight;
}
