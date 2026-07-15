import Constants from 'expo-constants';
import appConfig from '../app.json';

function resolveGoogleMapsApiKey() {
  const expoConfig = (Constants.expoConfig as any) || {};
  const manifest = (Constants as any)?.manifest || {};
  const manifest2 = (Constants as any)?.manifest2 || {};
  const staticExpoConfig = (appConfig as any)?.expo || {};
  const extra =
    (expoConfig.extra as Record<string, string | undefined> | undefined) ||
    (manifest2?.extra?.expoClient?.extra as Record<string, string | undefined> | undefined) ||
    (manifest.extra as Record<string, string | undefined> | undefined) ||
    (staticExpoConfig.extra as Record<string, string | undefined> | undefined) ||
    {};

  return (
    extra.googleMapsApiKey ||
    expoConfig?.android?.config?.googleMaps?.apiKey ||
    expoConfig?.ios?.config?.googleMapsApiKey ||
    staticExpoConfig?.android?.config?.googleMaps?.apiKey ||
    staticExpoConfig?.ios?.config?.googleMapsApiKey ||
    manifest?.android?.config?.googleMaps?.apiKey ||
    manifest?.ios?.config?.googleMapsApiKey ||
    manifest2?.extra?.expoGo?.android?.config?.googleMaps?.apiKey ||
    process.env.EXPO_PUBLIC_GOOGLE_MAPS_API_KEY ||
    ''
  );
}

const expoExtra =
  ((Constants.expoConfig as any)?.extra as Record<string, string | undefined> | undefined) ||
  ((Constants as any)?.manifest2?.extra?.expoClient?.extra as Record<string, string | undefined> | undefined) ||
  ((Constants as any)?.manifest?.extra as Record<string, string | undefined> | undefined) ||
  {};

export const API_BASE_URL = expoExtra.apiUrl || process.env.EXPO_PUBLIC_API_URL || 'https://softcarshuttle.com';
export const GOOGLE_MAPS_API_KEY = resolveGoogleMapsApiKey();
export const SOCKET_URL = process.env.EXPO_PUBLIC_SOCKET_URL || API_BASE_URL;
export const SUPPORT_PHONE = process.env.EXPO_PUBLIC_SUPPORT_PHONE || '01050996940';
export const TOKEN_KEY = 'softcar.passenger.token';
export const NOTIFICATION_POLL_MS = 30000;
export const LIVE_TRIP_REFRESH_MS = 10000;
export const CHAT_POLL_MS = 8000;
export const SOCKET_RECONNECT_DELAY = 3000;
export const SOCKET_MAX_RECONNECT_ATTEMPTS = 5;
export const OFFLINE_QUEUE_KEY = 'softcar.passenger.offline_queue';
export const CACHED_TRIPS_KEY = 'softcar.passenger.cached_trips';
export const CACHED_RESERVATIONS_KEY = 'softcar.passenger.cached_reservations';
export const BOOKING_DRAFT_KEY = 'softcar.passenger.booking_draft';
export const PENDING_SHARED_TRIP_KEY = 'softcar.passenger.pending_shared_trip';
export const LOCAL_PREFERENCES_KEY = 'softcar.passenger.local_preferences';

export const PAYMENT_METHODS: { value: 'CASH' | 'CARD' | 'WALLET' | 'CASHLESS_CORPORATE'; label: string }[] = [
  { value: 'CASH', label: 'نقداً' },
  { value: 'CARD', label: 'بطاقة / فيزا' },
  { value: 'WALLET', label: 'محفظة SOFT CAR' },
  { value: 'CASHLESS_CORPORATE', label: 'شركة' },
];

export const SUPPORT_CATEGORIES: Array<'GENERAL' | 'BOOKING' | 'TRIP' | 'PAYMENT' | 'TECHNICAL' | 'ACCOUNT'> = ['GENERAL', 'BOOKING', 'TRIP', 'PAYMENT', 'TECHNICAL', 'ACCOUNT'];
export const SUPPORT_PRIORITIES: Array<'NORMAL' | 'HIGH' | 'URGENT' | 'LOW'> = ['NORMAL', 'HIGH', 'URGENT', 'LOW'];

export const COLORS = {
  background: '#050505',
  card: '#0A0A0A',
  cardBorder: '#2A2A2A',
  primary: '#D32F2F',
  primaryLight: '#FCA5A5',
  text: '#f8fafc',
  textSecondary: '#d4d4d8',
  textMuted: '#a1a1aa',
  accent: '#D32F2F',
  success: '#99f6e4',
  warning: '#f59e0b',
  error: '#fda4af',
  overlay: 'rgba(2, 6, 23, 0.6)',
};
