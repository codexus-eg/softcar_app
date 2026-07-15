import React, { useMemo } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

type ReadinessItem = { id: string; label: string; ready: boolean; detail: string; actionLabel?: string; onAction?: () => void };

export function PassengerTravelReadiness({ online, notificationReady, locationReady, hasReservation, paymentReady, driverAssigned, onEnableLocation, onEnableNotifications, onOpenHistory, onOpenSupport }: {
  online: boolean; notificationReady: boolean; locationReady: boolean; hasReservation: boolean; paymentReady: boolean; driverAssigned: boolean;
  onEnableLocation: () => void; onEnableNotifications: () => void; onOpenHistory: () => void; onOpenSupport: () => void;
}) {
  const items = useMemo<ReadinessItem[]>(() => [
    { id: 'network', label: 'الاتصال', ready: online, detail: online ? 'متصل بالخدمة' : 'تعمل البيانات المحفوظة حتى عودة الإنترنت' },
    { id: 'notifications', label: 'الإشعارات', ready: notificationReady, detail: notificationReady ? 'تنبيهات الرحلة مفعلة' : 'فعّلها لتصلك تغييرات الموعد والسائق', actionLabel: 'تفعيل', onAction: onEnableNotifications },
    { id: 'location', label: 'الموقع', ready: locationReady, detail: locationReady ? 'يمكن ترتيب أقرب نقاط الصعود' : 'فعّل الموقع للبحث عن أقرب رحلة', actionLabel: 'تحديد موقعي', onAction: onEnableLocation },
    { id: 'reservation', label: 'الحجز القادم', ready: hasReservation, detail: hasReservation ? 'الحجز والتذكرة متاحان' : 'لا يوجد حجز قادم', actionLabel: hasReservation ? 'عرض' : undefined, onAction: hasReservation ? onOpenHistory : undefined },
    { id: 'payment', label: 'الدفع', ready: !hasReservation || paymentReady, detail: !hasReservation ? 'يظهر بعد الحجز' : paymentReady ? 'حالة الدفع واضحة' : 'راجع حالة الدفع قبل الصعود', actionLabel: hasReservation && !paymentReady ? 'مراجعة' : undefined, onAction: hasReservation && !paymentReady ? onOpenHistory : undefined },
    { id: 'driver', label: 'السائق', ready: !hasReservation || driverAssigned, detail: !hasReservation ? 'يظهر بعد الحجز' : driverAssigned ? 'بيانات السائق متاحة' : 'لم يتم تعيين السائق بعد', actionLabel: hasReservation && !driverAssigned ? 'الدعم' : undefined, onAction: hasReservation && !driverAssigned ? onOpenSupport : undefined },
  ], [driverAssigned, hasReservation, locationReady, notificationReady, onEnableLocation, onEnableNotifications, onOpenHistory, onOpenSupport, online, paymentReady]);
  const readyCount = items.filter((item) => item.ready).length;
  const percent = Math.round((readyCount / items.length) * 100);
  return (
    <View style={styles.card}>
      <View style={styles.header}>
        <View style={styles.score}><Text style={styles.scoreText}>{percent.toLocaleString('ar-EG')}٪</Text></View>
        <View style={styles.headerCopy}><Text style={styles.eyebrow}>جاهزية الرحلة</Text><Text style={styles.title}>{percent === 100 ? 'كل شيء جاهز' : 'أكمل الخطوات المهمة قبل التحرك'}</Text><Text style={styles.subtitle}>{readyCount.toLocaleString('ar-EG')} من {items.length.toLocaleString('ar-EG')} عناصر جاهزة</Text></View>
      </View>
      <View style={styles.progress}><View style={[styles.progressFill, { width: `${percent}%` }]} /></View>
      <View style={styles.grid}>{items.map((item) => (
        <View key={item.id} style={[styles.item, item.ready && styles.itemReady]}>
          <View style={[styles.dot, item.ready && styles.dotReady]} />
          <View style={styles.itemCopy}><Text style={styles.itemTitle}>{item.label}</Text><Text style={styles.itemDetail}>{item.detail}</Text></View>
          {!item.ready && item.actionLabel && item.onAction ? <Pressable accessibilityRole="button" onPress={item.onAction} style={styles.action}><Text style={styles.actionText}>{item.actionLabel}</Text></Pressable> : null}
        </View>
      ))}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: 8, borderWidth: 1, borderColor: '#343434', backgroundColor: '#0A0A0A', padding: 14, gap: 12 },
  header: { flexDirection: 'row', alignItems: 'center', gap: 12 }, score: { width: 54, height: 54, borderRadius: 8, borderWidth: 1, borderColor: '#D32F2F', backgroundColor: '#24090A', alignItems: 'center', justifyContent: 'center' }, scoreText: { color: '#FFFFFF', fontWeight: '900', fontSize: 15 },
  headerCopy: { flex: 1, alignItems: 'flex-end' }, eyebrow: { color: '#EF5350', fontSize: 10, fontWeight: '900' }, title: { color: '#FFFFFF', fontSize: 17, fontWeight: '900', marginTop: 3, textAlign: 'right' }, subtitle: { color: '#A3A3A3', fontSize: 10, marginTop: 4, textAlign: 'right' },
  progress: { height: 5, borderRadius: 3, backgroundColor: '#292929', overflow: 'hidden' }, progressFill: { height: '100%', borderRadius: 3, backgroundColor: '#D32F2F' }, grid: { gap: 7 },
  item: { minHeight: 62, borderRadius: 8, borderWidth: 1, borderColor: '#343434', backgroundColor: '#121212', padding: 10, flexDirection: 'row', alignItems: 'center', gap: 9 }, itemReady: { borderColor: '#245A38' }, dot: { width: 9, height: 9, borderRadius: 5, backgroundColor: '#D32F2F' }, dotReady: { backgroundColor: '#22C55E' }, itemCopy: { flex: 1, alignItems: 'flex-end' }, itemTitle: { color: '#FFFFFF', fontSize: 12, fontWeight: '900', textAlign: 'right' }, itemDetail: { color: '#A3A3A3', fontSize: 10, lineHeight: 16, marginTop: 3, textAlign: 'right' }, action: { minHeight: 34, borderRadius: 8, backgroundColor: '#D32F2F', paddingHorizontal: 10, alignItems: 'center', justifyContent: 'center' }, actionText: { color: '#FFFFFF', fontSize: 10, fontWeight: '900' },
});
