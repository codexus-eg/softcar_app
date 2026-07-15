import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Notifications from 'expo-notifications';

const REMINDER_STATE_KEY = 'softcar.passenger.trip_reminder_state';
const MAX_SCHEDULED_REMINDERS = 12;

type ReminderReservation = {
  id: string;
  status: string;
  pickupPoint: { name: string };
  trip: {
    id: string;
    title: string;
    startTime: string;
    status?: string | null;
  };
};

export type PassengerReminderSettings = {
  enabled: boolean;
  leadMinutes: number;
};

type ReminderState = {
  signature: string;
  ids: string[];
};

async function loadReminderState(): Promise<ReminderState> {
  try {
    const raw = await AsyncStorage.getItem(REMINDER_STATE_KEY);
    const parsed = raw ? JSON.parse(raw) as Partial<ReminderState> : {};
    return {
      signature: typeof parsed.signature === 'string' ? parsed.signature : '',
      ids: Array.isArray(parsed.ids)
        ? parsed.ids.filter((value): value is string => typeof value === 'string')
        : [],
    };
  } catch {
    return { signature: '', ids: [] };
  }
}

export async function clearPassengerTripReminders() {
  const state = await loadReminderState();
  await Promise.all(state.ids.map((id) => Notifications.cancelScheduledNotificationAsync(id).catch(() => undefined)));
  await AsyncStorage.removeItem(REMINDER_STATE_KEY);
}

export async function syncPassengerTripReminders(
  reservations: ReminderReservation[],
  settings: PassengerReminderSettings,
) {
  const permission = await Notifications.getPermissionsAsync();
  if (!settings.enabled || permission.status !== 'granted') {
    await clearPassengerTripReminders();
    return 0;
  }

  const now = Date.now();
  const leadMinutes = Math.min(180, Math.max(5, Math.round(settings.leadMinutes || 30)));
  const candidates = reservations
    .filter((reservation) => {
      const reservationStatus = String(reservation.status || '').toUpperCase();
      const tripStatus = String(reservation.trip.status || 'SCHEDULED').toUpperCase();
      const start = new Date(reservation.trip.startTime).getTime();
      return (
        ['RESERVED', 'BOARDED'].includes(reservationStatus) &&
        !['COMPLETED', 'CANCELLED'].includes(tripStatus) &&
        Number.isFinite(start) &&
        start - leadMinutes * 60_000 > now + 30_000
      );
    })
    .sort((left, right) => new Date(left.trip.startTime).getTime() - new Date(right.trip.startTime).getTime())
    .slice(0, MAX_SCHEDULED_REMINDERS);

  const signature = JSON.stringify({
    leadMinutes,
    reminders: candidates.map((reservation) => [
      reservation.id,
      reservation.trip.id,
      reservation.trip.startTime,
      reservation.pickupPoint.name,
    ]),
  });
  const previousState = await loadReminderState();
  if (previousState.signature === signature) return previousState.ids.length;

  await Promise.all(
    previousState.ids.map((id) => Notifications.cancelScheduledNotificationAsync(id).catch(() => undefined)),
  );

  const ids: string[] = [];
  for (const reservation of candidates) {
    const start = new Date(reservation.trip.startTime).getTime();
    const triggerDate = new Date(start - leadMinutes * 60_000);
    const id = await Notifications.scheduleNotificationAsync({
      content: {
        title: 'اقترب موعد رحلة سوفت كار',
        body: `${reservation.trip.title} من ${reservation.pickupPoint.name} بعد ${leadMinutes.toLocaleString('ar-EG')} دقيقة.`,
        sound: true,
        data: {
          type: 'trip_reminder',
          tripId: reservation.trip.id,
          reservationId: reservation.id,
          actionUrl: `/trip/view/${reservation.trip.id}`,
        },
      },
      trigger: {
        type: Notifications.SchedulableTriggerInputTypes.DATE,
        date: triggerDate,
      },
    });
    ids.push(id);
  }

  await AsyncStorage.setItem(REMINDER_STATE_KEY, JSON.stringify({ signature, ids }));
  return ids.length;
}
