import React, { useState } from 'react';
import { Alert, Pressable, StyleSheet, Text } from 'react-native';
import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';

type ReceiptReservation = {
  id: string;
  ticketCode?: string | null;
  seatNumbers?: string | null;
  totalPrice?: number | null;
  paymentMethod?: string | null;
  paymentStatus?: string | null;
  pickupPoint: { name: string };
  dropoffPoint: { name: string };
  trip: { title: string; startTime: string };
};

function escapeHtml(value: unknown) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

export function ReservationReceiptButton({ reservation }: { reservation: ReceiptReservation }) {
  const [busy, setBusy] = useState(false);

  async function shareReceipt() {
    setBusy(true);
    try {
      const html = `
        <html dir="rtl"><head><meta charset="utf-8"><style>
          body{font-family:Arial,sans-serif;background:#fff;color:#111;padding:32px}
          h1{color:#c62828;margin:0 0 8px}.box{border:1px solid #ddd;padding:18px;margin-top:20px}
          .row{display:flex;justify-content:space-between;border-bottom:1px solid #eee;padding:10px 0}
          .brand{font-weight:800;letter-spacing:1px}.foot{margin-top:24px;color:#666;font-size:12px}
        </style></head><body>
          <div class="brand">SOFT CAR</div><h1>إيصال حجز</h1>
          <div class="box">
            <div class="row"><b>الرحلة</b><span>${escapeHtml(reservation.trip.title)}</span></div>
            <div class="row"><b>الموعد</b><span>${escapeHtml(new Date(reservation.trip.startTime).toLocaleString('ar-EG'))}</span></div>
            <div class="row"><b>المسار</b><span>${escapeHtml(reservation.pickupPoint.name)} ← ${escapeHtml(reservation.dropoffPoint.name)}</span></div>
            <div class="row"><b>التذكرة</b><span>${escapeHtml(reservation.ticketCode || reservation.id)}</span></div>
            <div class="row"><b>المقعد</b><span>${escapeHtml(reservation.seatNumbers || '-')}</span></div>
            <div class="row"><b>المبلغ</b><span>${escapeHtml(reservation.totalPrice || 0)} ج.م</span></div>
            <div class="row"><b>حالة الدفع</b><span>${escapeHtml(reservation.paymentStatus || reservation.paymentMethod || '-')}</span></div>
          </div>
          <div class="foot">تم إنشاء هذا الإيصال من تطبيق سوفت كار.</div>
        </body></html>`;
      const file = await Print.printToFileAsync({ html });
      if (!(await Sharing.isAvailableAsync())) throw new Error('مشاركة الملفات غير متاحة على هذا الجهاز.');
      await Sharing.shareAsync(file.uri, { mimeType: 'application/pdf', dialogTitle: 'مشاركة إيصال الحجز' });
    } catch (error) {
      Alert.alert('تعذر إنشاء الإيصال', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Pressable style={styles.button} onPress={() => void shareReceipt()} disabled={busy}>
      <Text style={styles.text}>{busy ? 'جارٍ إنشاء الإيصال...' : 'تنزيل أو مشاركة الإيصال'}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: { marginTop: 10, minHeight: 42, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#D32F2F', borderRadius: 7 },
  text: { color: '#FCA5A5', fontWeight: '900' },
});
