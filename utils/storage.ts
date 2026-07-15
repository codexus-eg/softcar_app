import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';
import { TOKEN_KEY, OFFLINE_QUEUE_KEY, CACHED_TRIPS_KEY, CACHED_RESERVATIONS_KEY } from './constants';
import type { OfflineQueueItem, Trip, Reservation } from './types';

export type PassengerCacheSummary = {
  tripCount: number;
  reservationCount: number;
  lastUpdatedAt: number | null;
};

type CacheEnvelope<T> = {
  data: T;
  timestamp: number;
};

function parseCacheEnvelope<T>(raw: string | null): CacheEnvelope<T> | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as CacheEnvelope<T>;
    if (!parsed || typeof parsed.timestamp !== 'number') return null;
    return parsed;
  } catch {
    return null;
  }
}

export async function getToken(): Promise<string | null> {
  if (Platform.OS === 'web') return AsyncStorage.getItem(TOKEN_KEY);
  const secureToken = await SecureStore.getItemAsync(TOKEN_KEY);
  if (secureToken) return secureToken;
  const legacyToken = await AsyncStorage.getItem(TOKEN_KEY);
  if (legacyToken) {
    await setToken(legacyToken);
    await AsyncStorage.removeItem(TOKEN_KEY);
  }
  return legacyToken;
}

export async function setToken(token: string): Promise<void> {
  if (Platform.OS === 'web') return AsyncStorage.setItem(TOKEN_KEY, token);
  await SecureStore.setItemAsync(TOKEN_KEY, token, {
    keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK,
  });
}

export async function removeToken(): Promise<void> {
  await AsyncStorage.removeItem(TOKEN_KEY);
  if (Platform.OS !== 'web') await SecureStore.deleteItemAsync(TOKEN_KEY);
}

export async function queueOfflineAction(action: string, payload: Record<string, any>): Promise<void> {
  try {
    const raw = await AsyncStorage.getItem(OFFLINE_QUEUE_KEY);
    const queue: OfflineQueueItem[] = raw ? JSON.parse(raw) : [];
    queue.push({
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`,
      action,
      payload,
      timestamp: Date.now(),
      retries: 0,
    });
    await AsyncStorage.setItem(OFFLINE_QUEUE_KEY, JSON.stringify(queue));
  } catch {
    // Silently fail - queue is best-effort
  }
}

export async function getOfflineQueue(): Promise<OfflineQueueItem[]> {
  try {
    const raw = await AsyncStorage.getItem(OFFLINE_QUEUE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export async function clearOfflineQueue(): Promise<void> {
  return AsyncStorage.removeItem(OFFLINE_QUEUE_KEY);
}

export async function removeOfflineItem(id: string): Promise<void> {
  try {
    const queue = await getOfflineQueue();
    const filtered = queue.filter((item) => item.id !== id);
    await AsyncStorage.setItem(OFFLINE_QUEUE_KEY, JSON.stringify(filtered));
  } catch {
    // Silently fail
  }
}

export async function cacheTrips(trips: Trip[]): Promise<void> {
  if (!Array.isArray(trips)) return;
  try {
    await AsyncStorage.setItem(CACHED_TRIPS_KEY, JSON.stringify({ data: trips, timestamp: Date.now() }));
  } catch {
    // Silently fail
  }
}

export async function getCachedTrips(maxAgeMs = 300000): Promise<Trip[] | null> {
  try {
    const raw = await AsyncStorage.getItem(CACHED_TRIPS_KEY);
    if (!raw) return null;
    const { data, timestamp } = JSON.parse(raw);
    if (Date.now() - timestamp > maxAgeMs) return null;
    return Array.isArray(data) ? data : null;
  } catch {
    return null;
  }
}

export async function cacheReservations(reservations: Reservation[]): Promise<void> {
  if (!Array.isArray(reservations)) return;
  try {
    await AsyncStorage.setItem(CACHED_RESERVATIONS_KEY, JSON.stringify({ data: reservations, timestamp: Date.now() }));
  } catch {
    // Silently fail
  }
}

export async function getCachedReservations(maxAgeMs = 300000): Promise<Reservation[] | null> {
  try {
    const raw = await AsyncStorage.getItem(CACHED_RESERVATIONS_KEY);
    if (!raw) return null;
    const { data, timestamp } = JSON.parse(raw);
    if (Date.now() - timestamp > maxAgeMs) return null;
    return Array.isArray(data) ? data : null;
  } catch {
    return null;
  }
}

export async function getPassengerCacheSummary(): Promise<PassengerCacheSummary> {
  const [tripsRaw, reservationsRaw] = await Promise.all([
    AsyncStorage.getItem(CACHED_TRIPS_KEY),
    AsyncStorage.getItem(CACHED_RESERVATIONS_KEY),
  ]);
  const tripsCache = parseCacheEnvelope<Trip[]>(tripsRaw);
  const reservationsCache = parseCacheEnvelope<Reservation[]>(reservationsRaw);
  const timestamps = [tripsCache?.timestamp, reservationsCache?.timestamp].filter(
    (value): value is number => typeof value === 'number'
  );

  return {
    tripCount: Array.isArray(tripsCache?.data) ? tripsCache.data.length : 0,
    reservationCount: Array.isArray(reservationsCache?.data) ? reservationsCache.data.length : 0,
    lastUpdatedAt: timestamps.length ? Math.max(...timestamps) : null,
  };
}

export async function clearPassengerCache(): Promise<void> {
  await AsyncStorage.multiRemove([CACHED_TRIPS_KEY, CACHED_RESERVATIONS_KEY]);
}
