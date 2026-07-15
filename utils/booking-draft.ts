import AsyncStorage from '@react-native-async-storage/async-storage';
import { BOOKING_DRAFT_KEY, PENDING_SHARED_TRIP_KEY } from './constants';

export type PassengerBookingDraft = {
  tripId: string;
  pickupPointId: string;
  dropoffPointId: string;
  paymentMethod: 'CASH' | 'CARD' | 'WALLET' | 'CASHLESS_CORPORATE';
  walletSenderNumber: string;
  selectedSeat: string;
  selectedTierId: string;
  selectedServiceDateKeys: string[];
  reserveRoundTrip: boolean;
  returnPickupPointId: string;
  returnDropoffPointId: string;
  clientRequestId: string;
  updatedAt: number;
};

export function createClientRequestId() {
  return `mobile-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
}

export async function saveBookingDraft(draft: PassengerBookingDraft) {
  await AsyncStorage.setItem(BOOKING_DRAFT_KEY, JSON.stringify(draft));
}

export async function loadBookingDraft(maxAgeMs = 24 * 60 * 60 * 1000): Promise<PassengerBookingDraft | null> {
  try {
    const raw = await AsyncStorage.getItem(BOOKING_DRAFT_KEY);
    if (!raw) return null;
    const draft = JSON.parse(raw) as PassengerBookingDraft;
    if (!draft.tripId || !draft.updatedAt || Date.now() - draft.updatedAt > maxAgeMs) {
      await clearBookingDraft();
      return null;
    }
    return draft;
  } catch {
    return null;
  }
}

export async function clearBookingDraft() {
  await AsyncStorage.removeItem(BOOKING_DRAFT_KEY);
}

export async function savePendingSharedTrip(tripId: string) {
  if (!tripId) return;
  await AsyncStorage.setItem(PENDING_SHARED_TRIP_KEY, tripId);
}

export async function loadPendingSharedTrip() {
  return AsyncStorage.getItem(PENDING_SHARED_TRIP_KEY);
}

export async function clearPendingSharedTrip() {
  await AsyncStorage.removeItem(PENDING_SHARED_TRIP_KEY);
}

export function parseSharedTripId(url: string | null | undefined) {
  const value = String(url || '').trim();
  if (!value) return '';

  const pathMatch = value.match(/\/trip\/view\/([^/?#]+)/i);
  if (pathMatch?.[1]) return decodeURIComponent(pathMatch[1]);

  const queryMatch = value.match(/[?&](?:selectedTrip|tripId)=([^&#]+)/i);
  if (queryMatch?.[1]) return decodeURIComponent(queryMatch[1]);

  const schemeMatch = value.match(/^(?:softcarpassenger|com\.softcar\.passengersss|com\.softcar\.passenger):\/\/(?:trip\/)?([^/?#]+)/i);
  return schemeMatch?.[1] ? decodeURIComponent(schemeMatch[1]) : '';
}
