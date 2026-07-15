import React, { type ReactNode, useEffect, useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

type JourneyReservation = {
  status: string;
  seatNumbers: string | null;
  ticketCode: string | null;
  paymentStatus?: string | null;
  pickupPoint: { name: string };
  dropoffPoint: { name: string };
  trip: {
    title: string;
    startTime: string;
    estimatedEndTime?: string | null;
  };
};

type JourneyDriver = {
  phone?: string | null;
} | null;

type PassengerJourneyCommandCenterProps = {
  reservation: JourneyReservation;
  driver: JourneyDriver;
  live: boolean;
  online: boolean;
  unreadCount: number;
  onDirections: () => void;
  onCallDriver: () => void;
  onShare: () => void;
  onOpenHistory: () => void;
  onOpenNotifications: () => void;
  onAddCalendar: () => void;
  children?: ReactNode;
};

function statusLabel(status: string) {
  const labels: Record<string, string> = {
    RESERVED: 'محجوزة',
    BOARDED: 'تم الصعود',
    IN_PROGRESS: 'جارية الآن',
    COMPLETED: 'مكتملة',
    CANCELLED: 'ملغاة',
    NO_SHOW: 'لم يحضر',
  };
  return labels[String(status || '').toUpperCase()] || status || 'غير محددة';
}

function paymentLabel(status?: string | null) {
  const labels: Record<string, string> = {
    PAID: 'مدفوع',
    AUTHORIZED: 'تم اعتماد الدفع',
    PAID_CASH_COLLECTED: 'تم تحصيل النقد',
    CASH_COLLECTED: 'تم تحصيل النقد',
    PENDING_CASH_COLLECTION: 'الدفع عند الصعود',
    PENDING: 'قيد الدفع',
    UNPAID: 'غير مدفوع',
  };
  return labels[String(status || '').toUpperCase()] || 'راجع حالة الدفع';
}

function formatJourneyTime(value?: string | null) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return date.toLocaleString('ar-EG', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function journeyCountdown(startTime: string, live: boolean, now: number) {
  if (live) return { title: 'الرحلة جارية الآن', detail: 'تابع المحطات وتعليمات السائق من هذه الشاشة.' };
  const start = new Date(startTime).getTime();
  if (!Number.isFinite(start)) return { title: 'موعد الرحلة', detail: formatJourneyTime(startTime) };

  const minutes = Math.round((start - now) / 60_000);
  if (minutes <= 0) return { title: 'حان موعد الرحلة', detail: 'تأكد من وجودك عند نقطة الصعود.' };
  if (minutes < 60) return { title: `متبقي ${minutes.toLocaleString('ar-EG')} دقيقة`, detail: 'جهز التذكرة واتجه إلى نقطة الصعود.' };

  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return {
    title: `متبقي ${hours.toLocaleString('ar-EG')} ساعة`,
    detail: remainingMinutes
      ? `و${remainingMinutes.toLocaleString('ar-EG')} دقيقة على موعد الصعود.`
      : 'على موعد الصعود.',
  };
}

export function PassengerJourneyCommandCenter({
  reservation,
  driver,
  live,
  online,
  unreadCount,
  onDirections,
  onCallDriver,
  onShare,
  onOpenHistory,
  onOpenNotifications,
  onAddCalendar,
  children,
}: PassengerJourneyCommandCenterProps) {
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const interval = setInterval(() => setNow(Date.now()), 30_000);
    return () => clearInterval(interval);
  }, []);

  const countdown = useMemo(
    () => journeyCountdown(reservation.trip.startTime, live, now),
    [live, now, reservation.trip.startTime],
  );

  return (
    <View style={[styles.card, live && styles.cardLive]}>
      <View style={styles.header}>
        <View style={styles.headerCopy}>
          <Text style={styles.eyebrow}>{live ? 'متابعة مباشرة' : 'رحلتك القادمة'}</Text>
          <Text style={styles.title}>{reservation.trip.title}</Text>
          <Text style={styles.route}>
            {reservation.pickupPoint.name} ← {reservation.dropoffPoint.name}
          </Text>
        </View>
        <View style={styles.statusColumn}>
          <Text style={[styles.status, live && styles.statusLive]}>{statusLabel(reservation.status)}</Text>
          <Text style={[styles.connection, online ? styles.connectionOnline : styles.connectionOffline]}>
            {online ? 'متصل' : 'بيانات محفوظة'}
          </Text>
        </View>
      </View>

      <View style={styles.countdownCard}>
        <Text style={styles.countdownTitle}>{countdown.title}</Text>
        <Text style={styles.countdownDetail}>{countdown.detail}</Text>
        <Text style={styles.date}>{formatJourneyTime(reservation.trip.startTime)}</Text>
      </View>

      <View style={styles.metrics}>
        <View style={styles.metric}>
          <Text style={styles.metricLabel}>التذكرة</Text>
          <Text style={styles.metricValue} numberOfLines={1}>{reservation.ticketCode || 'قيد الإصدار'}</Text>
        </View>
        <View style={styles.metric}>
          <Text style={styles.metricLabel}>المقعد</Text>
          <Text style={styles.metricValue}>{reservation.seatNumbers || '-'}</Text>
        </View>
        <View style={styles.metric}>
          <Text style={styles.metricLabel}>الدفع</Text>
          <Text style={styles.metricValue} numberOfLines={1}>{paymentLabel(reservation.paymentStatus)}</Text>
        </View>
      </View>

      <View style={styles.primaryActions}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="فتح اتجاهات نقطة الصعود على خرائط Google"
          style={[styles.primaryButton, !online && styles.buttonDisabled]}
          disabled={!online}
          onPress={onDirections}
        >
          <Text style={styles.primaryButtonText}>اتجاهات الصعود</Text>
        </Pressable>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="الاتصال بسائق الرحلة"
          style={[styles.primaryButton, (!driver?.phone || !online) && styles.buttonDisabled]}
          disabled={!driver?.phone || !online}
          onPress={onCallDriver}
        >
          <Text style={styles.primaryButtonText}>{driver?.phone ? 'اتصال بالسائق' : 'السائق غير معيّن'}</Text>
        </Pressable>
      </View>

      <View style={styles.secondaryActions}>
        <Pressable accessibilityRole="button" style={styles.secondaryButton} onPress={onShare}>
          <Text style={styles.secondaryButtonText}>مشاركة</Text>
        </Pressable>
        <Pressable accessibilityRole="button" style={styles.secondaryButton} onPress={onOpenHistory}>
          <Text style={styles.secondaryButtonText}>التفاصيل</Text>
        </Pressable>
        <Pressable accessibilityRole="button" style={styles.secondaryButton} onPress={onOpenNotifications}>
          <Text style={styles.secondaryButtonText}>
            {unreadCount > 0 ? `التنبيهات (${unreadCount.toLocaleString('ar-EG')})` : 'التنبيهات'}
          </Text>
        </Pressable>
        <Pressable accessibilityRole="button" style={styles.secondaryButton} onPress={onAddCalendar}>
          <Text style={styles.secondaryButtonText}>إضافة للتقويم</Text>
        </Pressable>
      </View>

      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#3A3A3A',
    backgroundColor: '#080808',
    padding: 14,
    gap: 12,
  },
  cardLive: {
    borderColor: '#E53935',
    shadowColor: '#E53935',
    shadowOpacity: 0.18,
    shadowRadius: 18,
    elevation: 7,
  },
  header: {
    flexDirection: 'row-reverse',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  headerCopy: {
    flex: 1,
    gap: 4,
  },
  eyebrow: {
    color: '#EF5350',
    fontSize: 11,
    fontWeight: '900',
    textAlign: 'right',
  },
  title: {
    color: '#FFFFFF',
    fontSize: 19,
    fontWeight: '900',
    textAlign: 'right',
  },
  route: {
    color: '#D7D7D7',
    fontSize: 13,
    lineHeight: 20,
    textAlign: 'right',
  },
  statusColumn: {
    alignItems: 'flex-start',
    gap: 6,
  },
  status: {
    overflow: 'hidden',
    borderRadius: 999,
    backgroundColor: '#2B2B2B',
    color: '#FFFFFF',
    paddingHorizontal: 9,
    paddingVertical: 5,
    fontSize: 10,
    fontWeight: '900',
  },
  statusLive: {
    backgroundColor: '#D32F2F',
  },
  connection: {
    fontSize: 10,
    fontWeight: '800',
  },
  connectionOnline: {
    color: '#86EFAC',
  },
  connectionOffline: {
    color: '#FCA5A5',
  },
  countdownCard: {
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#303030',
    backgroundColor: '#121212',
    padding: 12,
    gap: 4,
  },
  countdownTitle: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '900',
    textAlign: 'right',
  },
  countdownDetail: {
    color: '#D0D0D0',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  date: {
    color: '#EF9A9A',
    fontSize: 12,
    fontWeight: '800',
    textAlign: 'right',
  },
  metrics: {
    flexDirection: 'row-reverse',
    gap: 8,
  },
  metric: {
    flex: 1,
    minHeight: 66,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#303030',
    backgroundColor: '#101010',
    padding: 9,
    gap: 6,
  },
  metricLabel: {
    color: '#A3A3A3',
    fontSize: 10,
    fontWeight: '800',
    textAlign: 'right',
  },
  metricValue: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '900',
    textAlign: 'right',
  },
  primaryActions: {
    flexDirection: 'row-reverse',
    gap: 8,
  },
  primaryButton: {
    flex: 1,
    minHeight: 46,
    borderRadius: 8,
    backgroundColor: '#D32F2F',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 10,
  },
  primaryButtonText: {
    color: '#FFFFFF',
    fontSize: 13,
    fontWeight: '900',
  },
  buttonDisabled: {
    opacity: 0.45,
  },
  secondaryActions: {
    flexDirection: 'row-reverse',
    flexWrap: 'wrap',
    gap: 8,
  },
  secondaryButton: {
    width: '48%',
    minHeight: 42,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#3A3A3A',
    backgroundColor: '#151515',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 6,
  },
  secondaryButtonText: {
    color: '#FFFFFF',
    fontSize: 11,
    fontWeight: '800',
    textAlign: 'center',
  },
});
