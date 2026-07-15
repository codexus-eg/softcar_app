import React, { useEffect, useMemo, useRef, useState } from 'react';
import Constants from 'expo-constants';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import * as Updates from 'expo-updates';
import { StatusBar } from 'expo-status-bar';
import {
  ActivityIndicator,
  Alert,
  Animated,
  AppState,
  Dimensions,
  Image,
  Linking,
  Modal,
  PanResponder,
  Platform,
  Pressable,
  RefreshControl,
  SafeAreaView,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { WebView } from 'react-native-webview';
import appConfig from './app.json';
import { AccountSecurityPanel } from './components/AccountSecurityPanel';
import { PassengerJourneyCommandCenter } from './components/PassengerJourneyCommandCenter';
import { PassengerDriverAssistCard } from './components/passenger-driver-assist-card';
import { PassengerTripChatPanel } from './components/passenger-trip-chat-panel';
import { ReservationReceiptButton } from './components/ReservationReceiptButton';
import { SupportChatPanel } from './components/SupportChatPanel';
import { PassengerTravelReadiness } from './components/PassengerTravelReadiness';
import { addReservationToDeviceCalendar } from './utils/trip-calendar';
import {
  clearBookingDraft,
  clearPendingSharedTrip,
  createClientRequestId,
  loadBookingDraft,
  loadPendingSharedTrip,
  parseSharedTripId,
  saveBookingDraft,
  savePendingSharedTrip,
  type PassengerBookingDraft,
} from './utils/booking-draft';
import {
  cacheReservations,
  cacheTrips,
  clearPassengerCache,
  getPassengerCacheSummary,
  getToken as getStoredToken,
  getCachedReservations,
  getCachedTrips,
  removeToken as clearStoredToken,
  setToken as persistToken,
  type PassengerCacheSummary,
} from './utils/storage';
import {
  authenticateDevice,
  canUseBiometrics,
  getBiometricEnabled,
  setBiometricEnabled as persistBiometricEnabled,
} from './utils/security';
import { useConnectivityStatus } from './hooks/useConnectivity';
import { parseArrayPayload, parseMobileLoginSession } from './utils/api-client';
import { syncPassengerTripReminders } from './utils/journey-reminders';
import {
  loadPassengerPreferences,
  savePassengerPreferences,
  type PassengerLocalPreferences,
} from './utils/passenger-preferences';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true,
    shouldPlaySound: true,
    shouldSetBadge: true,
    shouldShowBanner: true,
    shouldShowList: true,
  }),
});

type TripPoint = {
  id: string;
  name: string;
  stopOrder: number;
  pointType?: 'PICKUP' | 'DROPOFF';
  arrivalOffsetMin?: number | null;
  latitude?: number | string | null;
  longitude?: number | string | null;
};

type TripReservation = {
  seatNumbers: string | null;
  status?: string | null;
};

type DriverContact = {
  id?: string;
  fullName?: string | null;
  phone?: string | null;
  carModel?: string | null;
  carPlateNumber?: string | null;
  seatsAvailable?: number | null;
  currentLat?: number | string | null;
  currentLng?: number | string | null;
  currentHeading?: number | string | null;
  photoUrl?: string | null;
  carPhotoUrl?: string | null;
  image?: string | null;
};

type Trip = {
  id: string;
  title: string;
  mainDestination: string;
  endDestination: string;
  startTime: string;
  estimatedEndTime?: string | null;
  seatsRemaining: number;
  totalSeats: number;
  basePrice?: number | string | null;
  serviceClassCode?: string | null;
  serviceClassNameAr?: string | null;
  companyTripCost?: number | string | null;
  routePolyline?: string | null;
  tripType?: string | null;
  recurrenceGroupId?: string | null;
  sourceTripId?: string | null;
  templateSourceTripId?: string | null;
  templateId?: string | null;
  roundTripGroupId?: string | null;
  roundTripPairId?: string | null;
  roundTripDirection?: string | null;
  roundTripPrice?: number | string | null;
  returnTrip?: Trip | null;
  serviceDate?: string | null;
  occurrences?: Array<{
    id: string;
    startTime: string;
    estimatedEndTime?: string | null;
    serviceDate?: string | null;
    seatsRemaining: number;
    totalSeats: number;
    status?: string | null;
    tripType?: string | null;
    sourceTripId?: string | null;
    templateSourceTripId?: string | null;
    templateId?: string | null;
    reservations?: TripReservation[];
  }>;
  pickupPoints: TripPoint[];
  reservations: TripReservation[];
  driverProfile?: DriverContact | null;
};

type Reservation = {
  id: string;
  status: string;
  trip: {
    id: string;
    title: string;
    status?: string | null;
    totalSeats?: number | null;
    startTime: string;
    estimatedEndTime?: string | null;
    routePolyline?: string | null;
    pickupPoints?: TripPoint[];
    driverProfile?: DriverContact | null;
  };
  pickupPoint: { name: string };
  dropoffPoint: { name: string };
  seatNumbers: string | null;
  ticketCode: string | null;
  refunds?: Array<{
    id: string;
    refundCode: string;
    amount: number | string;
    status: string;
    reason: string;
    createdAt: string;
    updatedAt: string;
  }>;
  paymentMethod: string;
  paymentStatus?: string | null;
  recurringReservationId?: string | null;
  totalPrice?: number | null;
  review?: {
    id: string;
    rating: number;
    reviewTitle?: string | null;
    reviewBody?: string | null;
    complaint?: string | null;
    status?: string | null;
    updatedAt?: string | null;
  } | null;
};

type VoucherQuote = {
  voucher: { id: string; code: string; name: string; type: string; freeTier?: { id: string; name: string } | null };
  originalSubtotal: number;
  discountAmount: number;
  finalSubtotal: number;
  taxAmount: number;
  finalPrice: number;
};

type ActiveVoucher = {
  id: string;
  code: string;
  name: string;
  description?: string | null;
  imageUrl?: string | null;
  type: string;
  value: number;
  endAt: string;
  publishedAt?: string | null;
  trip?: { id: string; title: string; assetId: string } | null;
  freeTier?: { id: string; name: string; code: string } | null;
};

type MobileMePayload = {
  user: {
    id: string;
    name: string;
    email?: string | null;
    phone?: string | null;
    image?: string | null;
    preferredLanguage?: string | null;
    preferredTheme?: string | null;
    pushNotifications?: boolean | null;
    emailNotifications?: boolean | null;
    phoneNotifications?: boolean | null;
  };
};

type TripChatParticipant = {
  id: string;
  name: string;
  image?: string | null;
  role?: string | null;
};

type TripChatMessage = {
  id: string;
  tripId: string;
  senderId: string;
  recipientUserId?: string | null;
  message: string;
  createdAt: string;
  sender?: TripChatParticipant | null;
  recipient?: TripChatParticipant | null;
};

type TripChatPayload = {
  messages: TripChatMessage[];
  participants: {
    driver: TripChatParticipant | null;
    passengers: TripChatParticipant[];
  };
};

type NotificationItem = {
  id: string;
  title: string;
  message: string;
  type: string;
  actionUrl?: string | null;
  readAt?: string | null;
  sentAt: string;
};

type NotificationFeedPayload = {
  notifications: NotificationItem[];
  unreadCount: number;
  nextCursor?: string | null;
  counts?: {
    all: number;
    unread: number;
    trip: number;
    support: number;
    system: number;
  };
};

type PassengerTripConfirmation = {
  id: string;
  reservationId: string;
  tripId: string;
  type: 'CASH_COLLECTION' | 'BOARDING' | 'CASH_AND_BOARDING' | string;
  status: string;
  attemptNumber: number;
  maxAttempts: number;
  requestedCashAmount: number;
  paymentMethod?: string | null;
  expiresAt?: string | null;
  createdAt?: string | null;
  trip: {
    id: string;
    title: string;
    mainDestination?: string | null;
    endDestination?: string | null;
    startTime?: string | null;
    status?: string | null;
  };
  driver: {
    id: string;
    name: string;
    phone?: string | null;
    carModel?: string | null;
    carPlateNumber?: string | null;
    image?: string | null;
  } | null;
  reservation: {
    id: string;
    status: string;
    paymentStatus?: string | null;
    paymentMethod?: string | null;
    totalPrice: number;
    pickupPoint?: { id?: string; name?: string; stopOrder?: number } | null;
    dropoffPoint?: { id?: string; name?: string; stopOrder?: number } | null;
  };
};

type SupportTicket = {
  id: string;
  subject: string;
  message: string;
  category: 'BOOKING' | 'ACCOUNT' | 'TRIP' | 'PAYMENT' | 'TECHNICAL' | 'GENERAL';
  priority: 'LOW' | 'NORMAL' | 'HIGH' | 'URGENT';
  status: 'OPEN' | 'IN_PROGRESS' | 'RESOLVED' | 'CLOSED';
  resolution?: string | null;
  createdAt: string;
  updatedAt: string;
};

type WalletSettingsPayload = {
  wallet: {
    recipientNumber: string;
    instructionsAr?: string | null;
    instructionsEn?: string | null;
    cibEnabled?: boolean;
    pciMode?: string;
    cibSponsorStatus?: string;
    balance?: number;
    pendingCredit?: number;
    totalCredited?: number;
    totalDebited?: number;
    totalRefunded?: number;
    status?: string;
    currency?: string;
  };
  account?: {
    id: string;
    balance: number;
    pendingCredit: number;
    reservedDebit: number;
    totalCredited: number;
    totalDebited: number;
    totalRefunded: number;
    status: string;
    currency: string;
  };
  ledger?: Array<{
    id: string;
    type: string;
    direction: string;
    amount: number;
    balanceAfter: number;
    source: string;
    note?: string | null;
    createdAt: string;
  }>;
  pendingTransactions?: Array<{
    id: string;
    amount: number;
    method: string;
    provider: string;
    status: string;
    checkoutUrl?: string | null;
    senderNumber?: string | null;
    recipientNumber?: string | null;
    createdAt: string;
  }>;
  transactions?: Array<{
    id: string;
    amount: number;
    method: string;
    provider: string;
    status: string;
    checkoutUrl?: string | null;
    senderNumber?: string | null;
    recipientNumber?: string | null;
    createdAt: string;
  }>;
};

type PricingPreview = {
  pricingMode: 'manual' | 'automatic' | 'progressive';
  unitPrice: number;
  subtotalPrice?: number;
  taxPercent?: number;
  taxAmount?: number;
  finalPrice: number;
  seats: number;
  distanceKm: number;
  durationMin: number;
  pricingStrategy: string;
  pickupName: string;
  dropoffName: string;
  pickupOffsetMin: number;
  dropoffOffsetMin: number;
  boardingTime?: string;
  arrivalTime?: string;
  serviceStartTime?: string;
  seatAvailability?: number;
};

type ReservationTier = {
  id: string;
  name: string;
  code: string;
  description?: string | null;
  durationDays: number;
  excludedWeekdays: number[];
  originalPrice: number;
  packagePrice: number;
  minimumSeats: number;
  maximumSeats?: number | null;
  paymentMethods: PaymentMethod[];
  cancellationPolicy?: string | null;
  tripId?: string | null;
  isRecommended?: boolean;
  autoUpgradeMinTrips?: number;
  autoUpgradeMinSpend?: number | null;
  discountPercent?: number | null;
  walletBonusAmount?: number | null;
  priorityBooking?: boolean;
  benefitsJson?: string | null;
};

type PassengerLoyaltyPayload = {
  summary: {
    points: number;
    completedTrips: number;
    lifetimeSpend: number;
    currentLevel: {
      code: string;
      name: string;
      minimumPoints: number;
      benefits: string[];
    };
    nextLevel: {
      code: string;
      name: string;
      minimumPoints: number;
      benefits: string[];
    } | null;
    progressPercent: number;
    pointsUntilNextLevel: number;
    pointsRule: string;
  };
  activity: Array<{
    id: string;
    reservationId: string;
    tripTitle: string;
    serviceDate: string;
    amount: number;
    points: number;
    ticketCode?: string | null;
  }>;
  rewards: Array<{
    id: string;
    name: string;
    code: string;
    description?: string | null;
    eligible: boolean;
    progressPercent: number;
    requirements: {
      minimumTrips: number;
      minimumSpend: number;
      remainingTrips: number;
      remainingSpend: number;
    };
    benefits: string[];
  }>;
};

type PaymentMethod = 'CASH' | 'CARD' | 'WALLET' | 'CASHLESS_CORPORATE';
type PassengerTab = 'reserve' | 'wallet' | 'history' | 'loyalty' | 'compliance' | 'support' | 'settings' | 'profile';
type HistoryFilter = 'all' | 'upcoming' | 'completed' | 'cancelled' | 'refunds';
type NotificationFilter = 'all' | 'unread' | 'trip' | 'support' | 'system';
const SUPPORT_CATEGORIES: SupportTicket['category'][] = ['GENERAL', 'BOOKING', 'TRIP', 'PAYMENT', 'TECHNICAL', 'ACCOUNT'];
const SUPPORT_PRIORITIES: SupportTicket['priority'][] = ['NORMAL', 'HIGH', 'URGENT', 'LOW'];

function formatSupportCategoryLabel(category: SupportTicket['category']) {
  return {
    GENERAL: 'عام',
    BOOKING: 'الحجز',
    TRIP: 'الرحلة',
    PAYMENT: 'الدفع',
    TECHNICAL: 'تقني',
    ACCOUNT: 'الحساب',
  }[category];
}

function formatSupportPriorityLabel(priority: SupportTicket['priority']) {
  return {
    LOW: 'منخفض',
    NORMAL: 'عادي',
    HIGH: 'مهم',
    URGENT: 'عاجل',
  }[priority];
}

function formatSupportStatusLabel(status: SupportTicket['status']) {
  return {
    OPEN: 'مفتوح',
    IN_PROGRESS: 'قيد المتابعة',
    RESOLVED: 'تم الحل',
    CLOSED: 'مغلق',
  }[status];
}

const TOKEN_KEY = 'softcar.passenger.token';
const NOTIFICATION_POLL_MS = 30000;
const LIVE_TRIP_REFRESH_MS = 10000;

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
const apiBaseUrl = expoExtra.apiUrl || process.env.EXPO_PUBLIC_API_URL || 'https://softcarshuttle.com';
const googleMapsApiKey = resolveGoogleMapsApiKey();

const PAYMENT_METHODS: { value: PaymentMethod; label: string }[] = [
  { value: 'CASH', label: 'نقداً' },
  { value: 'CARD', label: 'بطاقة / فيزا' },
  { value: 'WALLET', label: 'محفظة SOFT CAR' },
  { value: 'CASHLESS_CORPORATE', label: 'شركة' },
];

const PAYMENT_METHOD_LABELS_AR: Record<PaymentMethod, string> = {
  CASH: 'نقدا',
  CARD: 'بطاقة / فيزا',
  WALLET: 'محفظة SOFT CAR',
  CASHLESS_CORPORATE: 'شركة',
};

function paymentMethodDisplayLabel(method: string | null | undefined) {
  const key = String(method || '').toUpperCase() as PaymentMethod;
  return PAYMENT_METHOD_LABELS_AR[key] || method || '-';
}

function formatPaymentMethodLabel(method: string | null | undefined) {
  const cleanLabel = paymentMethodDisplayLabel(method);
  if (cleanLabel !== '-' && cleanLabel !== method) return cleanLabel;
  switch (String(method || '').toUpperCase()) {
    case 'CASH':
      return 'نقداً';
    case 'CARD':
      return 'بطاقة / فيزا';
    case 'WALLET':
      return 'محفظة SOFT CAR';
    case 'CASHLESS_CORPORATE':
      return 'شركة';
    default:
      return method || '-';
  }
}

function formatReservationStatusLabel(status: string | null | undefined) {
  switch (String(status || '').toUpperCase()) {
    case 'RESERVED':
      return 'محجوز';
    case 'BOARDED':
      return 'صعد';
    case 'IN_PROGRESS':
      return 'قيد التنفيذ';
    case 'COMPLETED':
      return 'مكتملة';
    case 'CANCELLED':
      return 'ملغاة';
    case 'NO_SHOW':
      return 'لم يحضر';
    default:
      return status || '-';
  }
}

function formatRefundStatusLabel(status: string | null | undefined) {
  const normalized = String(status || '').toUpperCase();
  const labels: Record<string, string> = {
    PENDING_REVIEW: 'قيد المراجعة المالية',
    APPROVED: 'تم الاعتماد وينتظر التنفيذ',
    PROCESSED: 'تم تنفيذ الاسترداد',
    REJECTED: 'تم رفض الطلب',
    CANCELLED: 'ملغي',
  };
  return labels[normalized] || status || 'غير محدد';
}

function formatTripStatusLabel(status: string | null | undefined) {
  switch (String(status || '').toUpperCase()) {
    case 'SCHEDULED':
      return 'مجدولة';
    case 'IN_PROGRESS':
      return 'قيد التنفيذ';
    case 'COMPLETED':
      return 'مكتملة';
    case 'CANCELLED':
      return 'ملغاة';
    case 'DELAYED':
      return 'متأخرة';
    default:
      return status || '-';
  }
}

function formatNotificationTypeLabel(type: string | null | undefined) {
  const normalized = String(type || '').toLowerCase();
  switch (normalized) {
    case 'trip_delay':
    case 'trip_started_delayed':
      return 'تأخير رحلة';
    case 'trip_update':
    case 'trip_started':
    case 'trip_completed':
      return 'تحديث رحلة';
    case 'driver_update':
    case 'driver_manifest_updated':
      return 'تحديث السائق';
    case 'booking':
    case 'reservation_created':
    case 'reservation_changed':
    case 'reservation_cancelled':
      return 'حجز';
    case 'refund_requested':
    case 'reservation_refunded':
      return 'استرداد';
    case 'payment':
    case 'payment_update':
      return 'دفع';
    case 'trip_chat_message':
    case 'support_chat':
      return 'رسالة جديدة';
    case 'support':
    case 'support_ticket':
      return 'الدعم';
    case 'complaint':
    case 'complaint_update':
      return 'شكوى';
    case 'security':
    case 'system':
      return 'النظام';
    default:
      if (normalized.includes('refund')) return 'استرداد';
      if (normalized.includes('payment') || normalized.includes('wallet')) return 'دفع';
      if (normalized.includes('trip') || normalized.includes('reservation') || normalized.includes('booking')) return 'رحلة وحجز';
      if (normalized.includes('support') || normalized.includes('ticket') || normalized.includes('chat')) return 'الدعم';
      return 'تنبيه';
  }
}

function matchesNotificationFilter(item: NotificationItem, filter: NotificationFilter) {
  const type = String(item.type || '').toLowerCase();
  if (filter === 'all') return true;
  if (filter === 'unread') return !item.readAt;
  const isTrip = type.includes('trip') || type.includes('reservation') || type.includes('booking') ||
    type.includes('driver') || type.includes('refund') || type.includes('payment');
  const isSupport = type.includes('support') || type.includes('ticket') || type.includes('chat') || type.includes('complaint');
  if (filter === 'trip') return isTrip;
  if (filter === 'support') return isSupport;
  return !isTrip && !isSupport;
}

function getNotificationActionLabel(item: NotificationItem | null) {
  const type = String(item?.type || '').toLowerCase();
  if (!item?.actionUrl) return 'لا يوجد إجراء مطلوب';
  if (type.includes('trip') || type.includes('reservation') || type.includes('booking') || type.includes('driver')) {
    return 'فتح الرحلة المرتبطة';
  }
  if (type.includes('support') || type.includes('chat') || type.includes('ticket')) {
    return 'فتح الدعم';
  }
  if (type.includes('refund') || type.includes('payment')) {
    return 'فتح السجل المالي';
  }
  if (type.includes('loyalty') || type.includes('reward') || type.includes('tier')) {
    return 'فتح برنامج الولاء';
  }
  return 'فتح الإجراء';
}

function formatDate(value: string | null | undefined) {
  if (!value) return '-';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '-' : parsed.toLocaleString('ar-EG');
}

function formatShortTime(value: string | null | undefined) {
  if (!value) return '-';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '-' : parsed.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' });
}

function formatPointEta(startTime: string | null | undefined, point: TripPoint) {
  const parsedOffset = Number(point.arrivalOffsetMin ?? 0);
  const offset = Number.isFinite(parsedOffset) ? Math.max(0, parsedOffset) : 0;
  if (!startTime) return `${offset} دقيقة`;
  const startDate = new Date(startTime);
  if (Number.isNaN(startDate.getTime())) return `${offset} دقيقة`;
  const eta = new Date(startDate.getTime() + offset * 60_000);
  return formatShortTime(eta.toISOString());
}

function formatMoney(value: number | string | null | undefined) {
  const parsed = Number(value || 0);
  return Number.isFinite(parsed) ? `${parsed.toFixed(2)} ج.م` : '0.00 ج.م';
}

function toNumber(value: number | string | null | undefined) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeRouteText(value?: string | null) {
  return String(value || '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[أإآ]/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

function pointRouteText(point?: TripPoint | null) {
  return normalizeRouteText(`${point?.name || ''}`);
}

function mobileDateKey(value?: string | null) {
  if (!value) return '';
  return new Date(value).toISOString().slice(0, 10);
}

function pointMatchesRoute(point: TripPoint, query: string) {
  const normalizedQuery = normalizeRouteText(query);
  if (!normalizedQuery) return true;
  const text = pointRouteText(point);
  return text.includes(normalizedQuery) || normalizedQuery.includes(text);
}

function findMobileRoutePair(trip: Trip, from: string, to: string) {
  const ordered = [...(trip.pickupPoints || [])].sort((a, b) => a.stopOrder - b.stopOrder);
  const pickups = ordered.filter((point) => point.pointType !== 'DROPOFF');
  const dropoffs = ordered.filter((point) => point.pointType !== 'PICKUP');
  const matchedPickups = from.trim() ? pickups.filter((point) => pointMatchesRoute(point, from)) : pickups;
  const matchedDropoffs = to.trim() ? dropoffs.filter((point) => pointMatchesRoute(point, to)) : dropoffs;

  for (const pickup of matchedPickups) {
    const dropoff = matchedDropoffs.find((candidate) => candidate.stopOrder > pickup.stopOrder);
    if (dropoff) return { pickup, dropoff };
  }
  return null;
}

function mobileTripOccurrences(trip: Trip) {
  return (trip.occurrences?.length
    ? trip.occurrences
    : [{ id: trip.id, startTime: trip.startTime, seatsRemaining: trip.seatsRemaining, status: 'SCHEDULED' }]
  )
    .filter((occurrence) => String(occurrence.status || 'SCHEDULED').toUpperCase() === 'SCHEDULED')
    .sort((left, right) => new Date(left.startTime).getTime() - new Date(right.startTime).getTime());
}

function distanceKm(aLat: number, aLng: number, bLat: number, bLng: number) {
  const lat1 = aLat * Math.PI / 180;
  const lat2 = bLat * Math.PI / 180;
  const dLat = lat2 - lat1;
  const dLng = (bLng - aLng) * Math.PI / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 6371 * (2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h)));
}

function nearestMobilePickupDistance(trip: Trip, coords?: { lat: number; lng: number } | null) {
  if (!coords) return Number.POSITIVE_INFINITY;
  return (trip.pickupPoints || []).reduce((nearest, point) => {
    const lat = toNumber(point.latitude);
    const lng = toNumber(point.longitude);
    if (lat === null || lng === null) return nearest;
    return Math.min(nearest, distanceKm(coords.lat, coords.lng, lat, lng));
  }, Number.POSITIVE_INFINITY);
}

function uniqueStopOptions(trips: Trip[], type: 'pickup' | 'dropoff', query: string) {
  const seen = new Map<string, TripPoint>();
  trips.forEach((trip) => {
    (trip.pickupPoints || []).forEach((point) => {
      if (type === 'pickup' && point.pointType === 'DROPOFF') return;
      if (type === 'dropoff' && point.pointType === 'PICKUP') return;
      const key = normalizeRouteText(point.name);
      if (!key || seen.has(key)) return;
      if (query.trim() && !pointMatchesRoute(point, query)) return;
      seen.set(key, point);
    });
  });
  return [...seen.values()].sort((left, right) => left.name.localeCompare(right.name, 'ar')).slice(0, 8);
}

function tripMatchesMobileRoute(trip: Trip, from: string, to: string, date: string, query: string) {
  const pair = findMobileRoutePair(trip, from, to);
  const occurrences = mobileTripOccurrences(trip);
  const dateMatches = !date || occurrences.some((occurrence) => mobileDateKey(occurrence.startTime) === date);
  const text = normalizeRouteText([
    trip.title,
    trip.mainDestination,
    trip.endDestination,
    ...(trip.pickupPoints || []).map((point) => point.name),
  ].join(' '));
  const queryMatches = !query.trim() || text.includes(normalizeRouteText(query));
  const routeMatches = (!from.trim() && !to.trim()) || Boolean(pair);
  return queryMatches && routeMatches && dateMatches;
}

function parseSeatCode(raw: string) {
  const upper = String(raw || '').trim().toUpperCase();
  if (!upper) return '';
  if (upper.startsWith('S')) return upper;
  const match = upper.match(/\d+/);
  if (!match) return '';
  return `S${match[0].padStart(2, '0')}`;
}

function parseReservedSeats(trip: Trip) {
  const reserved = new Set<string>();
  for (const reservation of trip.reservations || []) {
    if (reservation.status === 'CANCELLED' || reservation.status === 'NO_SHOW') continue;
    (reservation.seatNumbers || '')
      .split(',')
      .map((item) => parseSeatCode(item))
      .filter(Boolean)
      .forEach((seat) => reserved.add(seat));
  }
  return reserved;
}

function reservationDisplayGroupKey(reservation: Reservation) {
  const recurringKey = reservation.recurringReservationId || '';
  return [
    recurringKey || reservation.trip.title,
    reservation.trip.title,
    reservation.pickupPoint.name,
    reservation.dropoffPoint.name,
    reservation.status,
    reservation.paymentMethod,
  ].join('::');
}

function groupReservationsForDisplay(reservations: Reservation[]) {
  const groups = new Map<string, Reservation[]>();
  for (const reservation of reservations) {
    const key = reservationDisplayGroupKey(reservation);
    groups.set(key, [...(groups.get(key) || []), reservation]);
  }
  return Array.from(groups.values()).map((group) =>
    [...group].sort((left, right) => new Date(left.trip.startTime).getTime() - new Date(right.trip.startTime).getTime())
  );
}

function isReservationPaidPackage(reservations: Reservation[]) {
  return reservations.some((reservation) => {
    const method = String(reservation.paymentMethod || '').toUpperCase();
    const status = String(reservation.paymentStatus || '').toUpperCase();
    return method === 'CASH' && (status.includes('COLLECTED') || status.includes('PAID'));
  });
}

function createSeatMap(totalSeats: number) {
  const safeSeatCount = Math.max(1, Math.min(Number(totalSeats || 1), 60));
  return Array.from({ length: safeSeatCount }, (_, index) => `S${String(index + 1).padStart(2, '0')}`);
}

type DriverMarkerInput = {
  lat: number;
  lng: number;
  heading?: number | null;
  seats?: number | null;
  label?: string | null;
};

function buildRouteMapHtml(
  points: { lat: number; lng: number; label: string }[],
  routePolyline?: string | null,
  driverMarker?: DriverMarkerInput | null
) {
  const payload = JSON.stringify(points);
  const routePolylinePayload = JSON.stringify(routePolyline || null);
  const driverPayload = JSON.stringify(driverMarker || null);
  const apiKeyPayload = JSON.stringify(googleMapsApiKey);
  const apiBaseUrlPayload = JSON.stringify(apiBaseUrl);
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <style>
    html, body, #map { margin: 0; padding: 0; width: 100%; height: 100%; background: #050505; overflow: hidden; }
    #status {
      position: absolute;
      top: 12px;
      left: 12px;
      right: 12px;
      z-index: 2;
      border-radius: 12px;
      border: 1px solid rgba(255,255,255,0.12);
      background: rgba(2,6,23,0.82);
      color: #e2e8f0;
      padding: 10px 12px;
      font: 600 12px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      opacity: 0;
      transition: opacity .25s ease;
      pointer-events: none;
      backdrop-filter: blur(10px);
    }
    #status.show { opacity: 1; }
  </style>
</head>
<body>
  <div id="map"></div>
  <div id="status"></div>
  <script>
    const points = ${payload};
    const routePolyline = ${routePolylinePayload};
    const driverMarker = ${driverPayload};
    const apiKey = ${apiKeyPayload};
    const apiBaseUrl = ${apiBaseUrlPayload};
    const statusEl = document.getElementById('status');

    function setStatus(message, visible) {
      statusEl.textContent = message || '';
      statusEl.className = visible ? 'show' : '';
    }

    function loadScript(src) {
      return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = src;
        script.async = true;
        script.defer = true;
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
      });
    }

    function buildStopIcon(fillColor, strokeColor, size) {
      return {
        path: google.maps.SymbolPath.CIRCLE,
        fillColor,
        fillOpacity: 1,
        strokeColor,
        strokeOpacity: 1,
        strokeWeight: 2,
        scale: size,
      };
    }

    function resolveVehicleKind(seats) {
      const capacity = Number(seats || 14);
      const safeCapacity = Number.isFinite(capacity) && capacity > 0 ? capacity : 14;
      if (safeCapacity <= 1) return 'bike';
      if (safeCapacity <= 4) return 'car';
      if (safeCapacity <= 14) return 'microbus';
      if (safeCapacity <= 28) return 'minibus';
      return 'bus';
    }

    function vehicleTheme(seats) {
      const kind = resolveVehicleKind(seats);
      const themes = {
        bike: { accent: '#ef4444', glow: '#fecaca', label: 'BIKE', width: 18, length: 40, windowCount: 0 },
        car: { accent: '#dc2626', glow: '#fecaca', label: 'CAR', width: 27, length: 48, windowCount: 2 },
        microbus: { accent: '#111827', glow: '#e5e7eb', label: 'MICRO', width: 31, length: 56, windowCount: 3 },
        minibus: { accent: '#0A0A0A', glow: '#cbd5e1', label: 'MINI', width: 35, length: 62, windowCount: 4 },
        bus: { accent: '#991b1b', glow: '#fecaca', label: 'BUS', width: 39, length: 68, windowCount: 5 }
      };
      return Object.assign({ kind }, themes[kind]);
    }

    function vehicleBody(kind, theme) {
      if (kind === 'bike') {
        return '<g><ellipse cx="0" cy="-18" rx="5.5" ry="8.4" fill="#020617" stroke="#f8fafc" stroke-width="2"/><ellipse cx="0" cy="18" rx="5.5" ry="8.4" fill="#020617" stroke="#f8fafc" stroke-width="2"/><path d="M0 -18 C-8 -9 -8 9 0 18 C8 9 8 -9 0 -18Z" fill="url(#body)" stroke="#ffffff" stroke-width="1.8"/><path d="M0 -24 L-10 -14 M0 -24 L10 -14" stroke="#020617" stroke-width="2.4" stroke-linecap="round"/><circle cx="0" cy="-4" r="6.2" fill="' + theme.accent + '" stroke="#ffffff" stroke-width="1.5"/></g>';
      }
      const halfW = theme.width / 2;
      const halfL = theme.length / 2;
      const windowTop = -halfL + 12;
      const windowHeight = kind === 'car' ? 13 : 10;
      const sideWindowHeight = kind === 'car' ? 9 : 8;
      let windows = '';
      for (let index = 0; index < theme.windowCount; index += 1) {
        const y = -halfL + 25 + index * ((theme.length - 44) / Math.max(theme.windowCount, 1));
        windows += '<rect x="' + (-halfW + 5) + '" y="' + y + '" width="' + (theme.width - 10) + '" height="' + sideWindowHeight + '" rx="3" fill="url(#glass)" opacity="' + (kind === 'car' ? '0.78' : '0.86') + '"/>';
      }
      const routeStripe = kind === 'car'
        ? '<path d="M' + (-halfW + 4) + ' ' + (-halfL + 7) + 'H' + (halfW - 4) + '" stroke="' + theme.accent + '" stroke-width="3" stroke-linecap="round"/>'
        : '<path d="M' + (halfW - 5) + ' ' + (-halfL + 9) + 'V' + (halfL - 10) + '" stroke="' + theme.accent + '" stroke-width="3.5" stroke-linecap="round"/>';
      return '<g><rect x="' + (-halfW - 6) + '" y="' + (-halfL + 8) + '" width="5.5" height="13" rx="2.5" fill="#020617" opacity="0.9"/><rect x="' + (halfW + 0.5) + '" y="' + (-halfL + 8) + '" width="5.5" height="13" rx="2.5" fill="#020617" opacity="0.9"/><rect x="' + (-halfW - 6) + '" y="' + (halfL - 22) + '" width="5.5" height="13" rx="2.5" fill="#020617" opacity="0.9"/><rect x="' + (halfW + 0.5) + '" y="' + (halfL - 22) + '" width="5.5" height="13" rx="2.5" fill="#020617" opacity="0.9"/><path d="M' + (-halfW) + ' ' + (-halfL + 9) + 'C' + (-halfW) + ' ' + (-halfL + 2) + ' ' + (-halfW + 6) + ' ' + (-halfL) + ' 0 ' + (-halfL) + 'C' + (halfW - 6) + ' ' + (-halfL) + ' ' + halfW + ' ' + (-halfL + 2) + ' ' + halfW + ' ' + (-halfL + 9) + 'V' + (halfL - 9) + 'C' + halfW + ' ' + (halfL - 2) + ' ' + (halfW - 6) + ' ' + halfL + ' 0 ' + halfL + 'C' + (-halfW + 6) + ' ' + halfL + ' ' + (-halfW) + ' ' + (halfL - 2) + ' ' + (-halfW) + ' ' + (halfL - 9) + 'Z" fill="url(#body)" stroke="#ffffff" stroke-width="2"/><rect x="' + (-halfW + 5) + '" y="' + windowTop + '" width="' + (theme.width - 10) + '" height="' + windowHeight + '" rx="4" fill="url(#glass)"/>' + windows + '<rect x="' + (-halfW + 7) + '" y="' + (halfL - 12) + '" width="' + (theme.width - 14) + '" height="4" rx="2" fill="#111827" opacity="0.42"/>' + routeStripe + '<circle cx="' + (-halfW + 5) + '" cy="' + (halfL - 7) + '" r="2" fill="#ef4444"/><circle cx="' + (halfW - 5) + '" cy="' + (halfL - 7) + '" r="2" fill="#ef4444"/></g>';
    }

    function buildVehicleIcon(seats, heading) {
      const theme = vehicleTheme(seats);
      const seatLabel = seats ? String(seats) : theme.label;
      const rotation = Number.isFinite(Number(heading)) ? Number(heading) : 0;
      const body = vehicleBody(theme.kind, theme);
      const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="92" height="92" viewBox="0 0 92 92">' +
        '<defs>' +
        '<linearGradient id="body" x1="0" x2="1" y1="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="0.52" stop-color="#f8fafc"/><stop offset="1" stop-color="' + theme.glow + '"/></linearGradient>' +
        '<linearGradient id="glass" x1="0" x2="1" y1="0" y2="1"><stop offset="0" stop-color="#020617"/><stop offset="1" stop-color="#475569"/></linearGradient>' +
        '<filter id="shadow" x="-60%" y="-60%" width="220%" height="220%"><feDropShadow dx="0" dy="5" stdDeviation="4.5" flood-color="#020617" flood-opacity="0.38"/><feDropShadow dx="0" dy="0" stdDeviation="6" flood-color="#facc15" flood-opacity="0.72"/></filter>' +
        '</defs>' +
        '<ellipse cx="46" cy="71" rx="27" ry="8" fill="#020617" opacity="0.22"/>' +
        '<circle cx="46" cy="46" r="39" fill="none" stroke="#facc15" stroke-width="3" opacity=".8"/>' +
        '<g transform="translate(46 46) rotate(' + rotation + ') scale(1.08)" filter="url(#shadow)">' + body + '</g>' +
        '<g transform="translate(68 18)"><rect x="-15" y="-9" width="30" height="18" rx="9" fill="#020617" stroke="' + theme.accent + '" stroke-width="2"/><text x="0" y="4" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" font-weight="900" fill="#ffffff">' + seatLabel + '</text></g>' +
        '</svg>';
      return {
        url: 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg),
        scaledSize: new google.maps.Size(92, 92),
        anchor: new google.maps.Point(46, 46),
      };
    }

    async function init() {
      if (!apiKey) {
        document.body.innerHTML = '<div style="display:flex;align-items:center;justify-content:center;height:100%;padding:20px;color:#94a3b8;font:600 12px/1.6 -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif;text-align:center;background:#050505">مفتاح Google Maps غير متوفر لعرض الخريطة.</div>';
        return;
      }

      try {
        await loadScript('https://maps.googleapis.com/maps/api/js?key=' + encodeURIComponent(apiKey) + '&libraries=geometry');
      } catch (error) {
        document.body.innerHTML = '<div style="display:flex;align-items:center;justify-content:center;height:100%;padding:20px;color:#94a3b8;font:600 12px/1.6 -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif;text-align:center;background:#050505">تعذر تحميل Google Maps على هذا الجهاز.</div>';
        return;
      }

      const fallbackCenter = points[0] || { lat: 30.0444, lng: 31.2357 };
      const map = new google.maps.Map(document.getElementById('map'), {
        center: fallbackCenter,
        zoom: 11,
        disableDefaultUI: true,
        zoomControl: true,
        gestureHandling: 'greedy',
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: false,
      });

      const bounds = new google.maps.LatLngBounds();
      let routeDrawn = false;

      points.forEach((point, index) => {
        new google.maps.Marker({
          position: { lat: point.lat, lng: point.lng },
          map,
          title: point.label,
          label: {
            text: String(index + 1),
            color: '#ffffff',
            fontWeight: '700',
          },
          icon: buildStopIcon(
            index === 0 ? '#7c3aed' : index === points.length - 1 ? '#10b981' : '#111827',
            '#f8fafc',
            index === 0 || index === points.length - 1 ? 9 : 7
          ),
        });
        bounds.extend({ lat: point.lat, lng: point.lng });
      });

      if (driverMarker && Number.isFinite(Number(driverMarker.lat)) && Number.isFinite(Number(driverMarker.lng))) {
        const driverPosition = { lat: Number(driverMarker.lat), lng: Number(driverMarker.lng) };
        new google.maps.Marker({
          position: driverPosition,
          map,
          title: driverMarker.label || 'مركبة السائق',
          zIndex: 1000,
          icon: buildVehicleIcon(driverMarker.seats, driverMarker.heading),
        });
        bounds.extend(driverPosition);
      }

      if (routePolyline && google.maps.geometry?.encoding) {
        const decodedPath = google.maps.geometry.encoding.decodePath(routePolyline);
        new google.maps.Polyline({
          map,
          path: decodedPath,
          strokeColor: '#dc2626',
          strokeOpacity: 0.95,
          strokeWeight: 6,
        });
        decodedPath.forEach((point) => bounds.extend(point));
        routeDrawn = decodedPath.length > 1;
      }

      if (!routeDrawn && points.length > 1) {
        setStatus('جاري تحميل مسار الطريق من Google...', true);
        try {
          const response = await fetch(apiBaseUrl.replace(/\\/$/, '') + '/api/maps/route', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ points: points.map((point) => ({ lat: point.lat, lng: point.lng })) }),
          });
          const payload = await response.json();
          if (!response.ok || !payload?.success || !payload?.data?.polyline) {
            throw new Error(payload?.message || 'تعذر تحميل المسار');
          }
          const path = google.maps.geometry.encoding.decodePath(payload.data.polyline);
          new google.maps.Polyline({
            map,
            path,
            strokeColor: '#dc2626',
            strokeOpacity: 0.95,
            strokeWeight: 6,
          });
          path.forEach((point) => bounds.extend(point));
          if (!bounds.isEmpty()) map.fitBounds(bounds, 44);
          setStatus('', false);
        } catch (error) {
          setStatus('تعذر تحميل مسار Google الآن. تبقى المحطات ظاهرة بدون خط تقريبي.', true);
        }
      }

      if (!bounds.isEmpty()) {
        map.fitBounds(bounds, 44);
      }
    }

    init();
  </script>
</body>
</html>`;
}

function TripRouteMap({
  points,
  routePolyline,
  driver,
  vehicleSeats,
  height,
  fullscreenRequestKey = 0,
}: {
  points: TripPoint[];
  routePolyline?: string | null;
  driver?: DriverContact | null;
  vehicleSeats?: number | null;
  height: number;
  fullscreenRequestKey?: number;
}) {
  const [fullscreen, setFullscreen] = useState(false);
  useEffect(() => {
    if (fullscreenRequestKey > 0) {
      setFullscreen(true);
    }
  }, [fullscreenRequestKey]);

  const mappable = useMemo(
    () =>
      points
        .map((point) => ({
          lat: toNumber(point.latitude),
          lng: toNumber(point.longitude),
          stopOrder: point.stopOrder,
          name: point.name,
        }))
        .filter((point) => point.lat !== null && point.lng !== null)
        .sort((a, b) => a.stopOrder - b.stopOrder)
        .map((point) => ({
          lat: Number(point.lat),
          lng: Number(point.lng),
          label: `${point.stopOrder}. ${point.name}`,
        })),
    [points]
  );

  const driverMarker = useMemo(() => {
    const lat = toNumber(driver?.currentLat);
    const lng = toNumber(driver?.currentLng);
    if (lat === null || lng === null) return null;
    return {
      lat,
      lng,
      heading: toNumber(driver?.currentHeading),
      seats: vehicleSeats ?? (typeof driver?.seatsAvailable === 'number' ? driver.seatsAvailable : null),
      label: driver?.fullName || 'مركبة السائق',
    };
  }, [driver?.currentHeading, driver?.currentLat, driver?.currentLng, driver?.fullName, driver?.seatsAvailable, vehicleSeats]);

  const html = useMemo(() => buildRouteMapHtml(mappable, routePolyline, driverMarker), [driverMarker, mappable, routePolyline]);
  const mapRefreshKey = `${driverMarker?.lat || 'no-driver'}-${driverMarker?.lng || 'no-driver'}-${driverMarker?.seats || 'no-seats'}-${driverMarker?.heading || 'no-heading'}-${routePolyline?.length || 0}-${mappable.length}`;

  if (mappable.length < 2 && !routePolyline) {
    return (
      <View style={[styles.mapFallback, { height }]}>
        <Text style={styles.mapFallbackText}>ستظهر معاينة الخريطة عندما تتوفر إحداثيات محطات الرحلة.</Text>
      </View>
    );
  }

  const renderMap = (mapHeight: number, isFullscreen: boolean) => (
    <View style={[styles.mapWrap, { height: mapHeight }]}>
      <WebView
        key={`${isFullscreen ? 'full' : 'inline'}-${mapRefreshKey}`}
        source={{ html, baseUrl: 'https://softcarshuttle.com' }}
        originWhitelist={['*']}
        javaScriptEnabled
        scrollEnabled={false}
        bounces={false}
        style={styles.mapWebview}
      />
      {isFullscreen ? (
        <Pressable style={styles.mapExpandButton} onPress={() => setFullscreen(false)}>
          <Text style={styles.mapExpandButtonText}>×</Text>
        </Pressable>
      ) : null}
    </View>
  );

  return (
    <>
      {renderMap(height, false)}
      <Modal visible={fullscreen} transparent animationType="fade" onRequestClose={() => setFullscreen(false)}>
        <View style={styles.fullscreenMapRoot}>
          <View style={styles.fullscreenMapSurface}>
            {renderMap(screenHeight - 28, true)}
          </View>
        </View>
      </Modal>
    </>
  );
}

async function apiRequest<T>(path: string, token: string, options: RequestInit = {}) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(options.headers || {}),
    },
  });

  const raw = await response.text();
  let payload: Record<string, any> = {};
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    payload = { message: raw };
  }

  if (!response.ok) {
    const detailParts: string[] = [];
    if (payload?.details?.cutoffAt) {
      detailParts.push(`إغلاق الحجز: ${formatDate(payload.details.cutoffAt)}`);
    }
    if (payload?.details?.tripStart) {
      detailParts.push(`موعد الرحلة: ${formatDate(payload.details.tripStart)}`);
    }
    if (payload?.details?.earliestStart) {
      detailParts.push(`أقرب وقت متاح: ${formatDate(payload.details.earliestStart)}`);
    }
    const message =
      payload.error ||
      payload.message ||
      (raw ? String(raw).slice(0, 160) : '') ||
      `فشل الطلب (${response.status})`;
    throw new Error(detailParts.length ? `${message}\n${detailParts.join('\n')}` : message);
  }
  return payload as T;
}

async function apiJson(path: string, options: RequestInit = {}) {
  const response = await fetch(`${apiBaseUrl}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });

  const raw = await response.text();
  let payload: Record<string, any> = {};
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    payload = { message: raw };
  }

  return { response, payload };
}

function apiMessage(payload: Record<string, any>, fallback: string) {
  return String(payload?.message || payload?.error || fallback);
}

const screenHeight = Dimensions.get('window').height;
const sheetHeight = Math.min(screenHeight * 0.8, 620);
const sheetCollapsed = Math.max(220, sheetHeight - 130);

function PassengerApp() {
  const [booting, setBooting] = useState(true);
  const [loading, setLoading] = useState(false);
  const [searching, setSearching] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const [token, setToken] = useState('');
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [passwordVisible, setPasswordVisible] = useState(false);
  const [authMode, setAuthMode] = useState<'login' | 'register' | 'forgot'>('login');
  const [registerStep, setRegisterStep] = useState<'form' | 'otp'>('form');
  const [registerName, setRegisterName] = useState('');
  const [registerEmail, setRegisterEmail] = useState('');
  const [registerPhone, setRegisterPhone] = useState('');
  const [registerPassword, setRegisterPassword] = useState('');
  const [registerPasswordConfirm, setRegisterPasswordConfirm] = useState('');
  const [registerPasswordVisible, setRegisterPasswordVisible] = useState(false);
  const [registerPasswordConfirmVisible, setRegisterPasswordConfirmVisible] = useState(false);
  const [registerPoliciesAccepted, setRegisterPoliciesAccepted] = useState(false);
  const [registerOtp, setRegisterOtp] = useState('');
  const [registerOtpSent, setRegisterOtpSent] = useState(false);
  const [registerOtpLoading, setRegisterOtpLoading] = useState(false);
  const [registerOtpMessage, setRegisterOtpMessage] = useState('');
  const [registerOtpTone, setRegisterOtpTone] = useState<'info' | 'success' | 'error'>('info');
  const [registerResendSeconds, setRegisterResendSeconds] = useState(0);
  const [registerResendCooldownTotal, setRegisterResendCooldownTotal] = useState(60);
  const [resetPhone, setResetPhone] = useState('');
  const [resetOtp, setResetOtp] = useState('');
  const [resetPassword, setResetPassword] = useState('');
  const [resetPasswordConfirm, setResetPasswordConfirm] = useState('');
  const [resetPasswordVisible, setResetPasswordVisible] = useState(false);
  const [resetPasswordConfirmVisible, setResetPasswordConfirmVisible] = useState(false);
  const [resetOtpSent, setResetOtpSent] = useState(false);
  const [resetOtpLoading, setResetOtpLoading] = useState(false);
  const [resetOtpMessage, setResetOtpMessage] = useState('');
  const [resetOtpTone, setResetOtpTone] = useState<'info' | 'success' | 'error'>('info');
  const [resetResendSeconds, setResetResendSeconds] = useState(0);
  const [resetResendCooldownTotal, setResetResendCooldownTotal] = useState(60);

  const [query, setQuery] = useState('');
  const [fromQuery, setFromQuery] = useState('');
  const [toQuery, setToQuery] = useState('');
  const [serviceDateQuery, setServiceDateQuery] = useState('');
  const [passengerCoords, setPassengerCoords] = useState<{ lat: number; lng: number } | null>(null);
  const [locationSearchNote, setLocationSearchNote] = useState('');
  const [trips, setTrips] = useState<Trip[]>([]);
  const [reservations, setReservations] = useState<Reservation[]>([]);
  const [reservationTiers, setReservationTiers] = useState<ReservationTier[]>([]);
  const [loyalty, setLoyalty] = useState<PassengerLoyaltyPayload | null>(null);
  const [historyFilter, setHistoryFilter] = useState<HistoryFilter>('all');
  const [activeTab, setActiveTab] = useState<PassengerTab>('reserve');
  const [menuOpen, setMenuOpen] = useState(false);
  const [tripChatByTripId, setTripChatByTripId] = useState<Record<string, TripChatMessage[]>>({});
  const [tripChatParticipantsByTripId, setTripChatParticipantsByTripId] = useState<
    Record<string, TripChatPayload['participants']>
  >({});
  const [chatDraft, setChatDraft] = useState('');
  const [chatLoadingTripId, setChatLoadingTripId] = useState('');
  const [chatSendingTripId, setChatSendingTripId] = useState('');
  const [meUser, setMeUser] = useState<MobileMePayload['user'] | null>(null);
  const [notifications, setNotifications] = useState<NotificationItem[]>([]);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const [notificationPanelOpen, setNotificationPanelOpen] = useState(false);
  const [notificationFilter, setNotificationFilter] = useState<NotificationFilter>('all');
  const [notificationSearch, setNotificationSearch] = useState('');
  const [focusedNotificationId, setFocusedNotificationId] = useState('');
  const [notificationNextCursor, setNotificationNextCursor] = useState<string | null>(null);
  const [notificationLoading, setNotificationLoading] = useState(false);
  const [notificationPermissionStatus, setNotificationPermissionStatus] = useState<'checking' | 'granted' | 'denied'>('checking');
  const [pendingConfirmations, setPendingConfirmations] = useState<PassengerTripConfirmation[]>([]);
  const [confirmationPanelOpen, setConfirmationPanelOpen] = useState(false);
  const [confirmationBusyId, setConfirmationBusyId] = useState('');
  const [supportTickets, setSupportTickets] = useState<SupportTicket[]>([]);
  const [supportSubject, setSupportSubject] = useState('');
  const [supportMessage, setSupportMessage] = useState('');
  const [supportCategory, setSupportCategory] = useState<SupportTicket['category']>('GENERAL');
  const [supportPriority, setSupportPriority] = useState<SupportTicket['priority']>('NORMAL');
  const [supportSubmitting, setSupportSubmitting] = useState(false);
  const [expandedSupportTicketId, setExpandedSupportTicketId] = useState('');
  const [refundReservationId, setRefundReservationId] = useState('');
  const [refundScope, setRefundScope] = useState<'single' | 'trip-group'>('single');
  const [refundReason, setRefundReason] = useState('');
  const [refundSubmitting, setRefundSubmitting] = useState(false);
  const [reviewReservationId, setReviewReservationId] = useState('');
  const [reviewRating, setReviewRating] = useState(5);
  const [reviewBody, setReviewBody] = useState('');
  const [reviewSubmitting, setReviewSubmitting] = useState(false);
  const [notificationStatusNote, setNotificationStatusNote] = useState('جارٍ التحقق من قناة الإشعارات...');
  const [settingsSaving, setSettingsSaving] = useState(false);
  const [biometricAvailable, setBiometricAvailable] = useState(false);
  const [biometricEnabled, setBiometricEnabled] = useState(false);

  const [reservationModalOpen, setReservationModalOpen] = useState(false);
  const [selectedTripId, setSelectedTripId] = useState('');
  const [pickupPointId, setPickupPointId] = useState('');
  const [dropoffPointId, setDropoffPointId] = useState('');
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>('CASH');
  const [walletData, setWalletData] = useState<WalletSettingsPayload | null>(null);
  const [walletTopupAmount, setWalletTopupAmount] = useState('');
  const [walletTopupChannel, setWalletTopupChannel] = useState<'TRANSFER' | 'CARD'>('TRANSFER');
  const [walletTopupSender, setWalletTopupSender] = useState('');
  const [walletTopupSubmitting, setWalletTopupSubmitting] = useState(false);
  const [walletSenderNumber, setWalletSenderNumber] = useState('');
  const [walletRecipientNumber, setWalletRecipientNumber] = useState('');
  const [walletInstructions, setWalletInstructions] = useState('');
  const [selectedSeat, setSelectedSeat] = useState('');
  const [selectedTierId, setSelectedTierId] = useState('');
  const [voucherCode, setVoucherCode] = useState('');
  const [voucherQuote, setVoucherQuote] = useState<VoucherQuote | null>(null);
  const [voucherLoading, setVoucherLoading] = useState(false);
  const [voucherError, setVoucherError] = useState('');
  const [promotedVoucherCode, setPromotedVoucherCode] = useState('');
  const [activeVoucher, setActiveVoucher] = useState<ActiveVoucher | null>(null);
  const [voucherBroadcastVisible, setVoucherBroadcastVisible] = useState(false);
  const [voucherBroadcastSeconds, setVoucherBroadcastSeconds] = useState(15);
  const voucherBroadcastLoaded = useRef(false);
  const voucherPulse = useRef(new Animated.Value(0)).current;
  const [selectedServiceDateKeys, setSelectedServiceDateKeys] = useState<string[]>([]);
  const [reserveRoundTrip, setReserveRoundTrip] = useState(false);
  const [returnPickupPointId, setReturnPickupPointId] = useState('');
  const [returnDropoffPointId, setReturnDropoffPointId] = useState('');
  const [expandedReservationGroups, setExpandedReservationGroups] = useState<string[]>([]);
  const [detailFocusMode, setDetailFocusMode] = useState(false);
  const [reservationMapFullscreenRequest] = useState(0);
  const [pricingPreview, setPricingPreview] = useState<PricingPreview | null>(null);
  const [pricingLoading, setPricingLoading] = useState(false);
  const [pricingError, setPricingError] = useState('');
  const [bookingClientRequestId, setBookingClientRequestId] = useState(createClientRequestId());
  const [bookingDraftRestored, setBookingDraftRestored] = useState(false);
  const [bookingRecoveryNote, setBookingRecoveryNote] = useState('');
  const [networkNotice, setNetworkNotice] = useState('');
  const [updateChecking, setUpdateChecking] = useState(false);
  const [updateStatusNote, setUpdateStatusNote] = useState('التحديث التلقائي مفعّل عند تشغيل التطبيق.');
  const [cacheBusy, setCacheBusy] = useState(false);
  const [cacheSummary, setCacheSummary] = useState<PassengerCacheSummary>({
    tripCount: 0,
    reservationCount: 0,
    lastUpdatedAt: null,
  });
  const [localPreferences, setLocalPreferences] = useState<PassengerLocalPreferences>({
    favoriteTripIds: [],
    emergencyContactPhone: '',
    reduceMotion: false,
    tripRemindersEnabled: true,
    reminderLeadMinutes: 30,
  });
  const [reminderStatusNote, setReminderStatusNote] = useState('سيتم تجهيز تنبيهات الرحلات القادمة تلقائيًا.');
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const connectivity = useConnectivityStatus();
  const isOnline = connectivity.isOnline;
  const focusedPassengerConfirmation = pendingConfirmations[0] || null;

  const sheetTranslate = useRef(new Animated.Value(sheetCollapsed)).current;
  const sheetStartValue = useRef(sheetCollapsed);
  const sheetCurrentValue = useRef(sheetCollapsed);
  const registeredPushToken = useRef('');
  const handledNotificationResponseId = useRef('');

  useEffect(() => {
    const listener = sheetTranslate.addListener(({ value }) => {
      sheetCurrentValue.current = value;
    });
    return () => {
      sheetTranslate.removeListener(listener);
    };
  }, [sheetTranslate]);

  useEffect(() => {
    if (registerResendSeconds <= 0) return;
    const timer = setTimeout(() => {
      setRegisterResendSeconds((current) => Math.max(0, current - 1));
    }, 1000);
    return () => clearTimeout(timer);
  }, [registerResendSeconds]);

  useEffect(() => {
    if (resetResendSeconds <= 0) return;
    const timer = setTimeout(() => {
      setResetResendSeconds((current) => Math.max(0, current - 1));
    }, 1000);
    return () => clearTimeout(timer);
  }, [resetResendSeconds]);

  useEffect(() => {
    if (reservationModalOpen) {
      sheetTranslate.setValue(sheetCollapsed);
      sheetCurrentValue.current = sheetCollapsed;
      sheetStartValue.current = sheetCollapsed;
      setDetailFocusMode(false);
    }
  }, [reservationModalOpen, sheetTranslate]);

  function animateSheet(toValue: number) {
    if (localPreferences.reduceMotion) {
      sheetTranslate.setValue(toValue);
      return;
    }
    Animated.spring(sheetTranslate, {
      toValue,
      useNativeDriver: true,
      bounciness: 0,
    }).start();
  }

  function toggleDetailFocus(nextValue?: boolean) {
    const shouldFocus = typeof nextValue === 'boolean' ? nextValue : !detailFocusMode;
    setDetailFocusMode(shouldFocus);
    animateSheet(shouldFocus ? 0 : sheetCollapsed);
  }

  const panResponder = useMemo(
    () =>
      PanResponder.create({
        onMoveShouldSetPanResponder: (_, gesture) => Math.abs(gesture.dy) > 8,
        onPanResponderGrant: () => {
          sheetStartValue.current = sheetCurrentValue.current;
        },
        onPanResponderMove: (_, gesture) => {
          const next = Math.min(sheetCollapsed, Math.max(0, sheetStartValue.current + gesture.dy));
          sheetTranslate.setValue(next);
        },
        onPanResponderRelease: () => {
          const threshold = sheetCollapsed * 0.45;
          const shouldExpand = sheetCurrentValue.current < threshold;
          Animated.spring(sheetTranslate, {
            toValue: shouldExpand ? 0 : sheetCollapsed,
            useNativeDriver: true,
            bounciness: 0,
          }).start();
        },
      }),
    [sheetTranslate]
  );

  const selectedTrip = useMemo(
    () => trips.find((trip) => trip.id === selectedTripId) || null,
    [selectedTripId, trips]
  );
  const selectedReturnTrip = selectedTrip?.returnTrip || null;
  const roundTripBookingAvailable = Boolean(
    selectedTrip &&
    selectedReturnTrip &&
    String(selectedTrip.tripType || '').toUpperCase() === 'ROUND_TRIP' &&
    Number(selectedTrip.roundTripPrice || selectedReturnTrip.roundTripPrice || 0) > 0
  );
  const selectedTier = useMemo(
    () => reservationTiers.find((tier) => tier.id === selectedTierId) || null,
    [reservationTiers, selectedTierId]
  );
  const selectedTripGroupIds = useMemo(() => {
    if (!selectedTrip) return new Set<string>();
    const ids = new Set<string>();
    [selectedTrip.id, selectedTrip.recurrenceGroupId, selectedTrip.sourceTripId, selectedTrip.templateSourceTripId, selectedTrip.templateId]
      .filter((value): value is string => Boolean(value))
      .forEach((value) => ids.add(value));
    (selectedTrip.occurrences || []).forEach((occurrence) => {
      [occurrence.id, occurrence.sourceTripId, occurrence.templateSourceTripId, occurrence.templateId]
        .filter((value): value is string => Boolean(value))
        .forEach((value) => ids.add(value));
    });
    return ids;
  }, [selectedTrip]);
  const availableReservationTiers = useMemo(
    () =>
      reservationTiers.filter((tier) => {
        if (!tier.tripId) return true;
        return selectedTripGroupIds.has(tier.tripId);
      }),
    [reservationTiers, selectedTripGroupIds]
  );
  const serviceDateOptions = useMemo(() => {
    if (!selectedTrip) return [];
    const occurrences = selectedTrip.occurrences?.length
      ? selectedTrip.occurrences
      : [
          {
            id: selectedTrip.id,
            startTime: selectedTrip.startTime,
            estimatedEndTime: selectedTrip.estimatedEndTime,
            serviceDate: selectedTrip.serviceDate,
            seatsRemaining: selectedTrip.seatsRemaining,
            totalSeats: selectedTrip.totalSeats,
            status: 'SCHEDULED',
            reservations: selectedTrip.reservations,
          },
        ];
    const unique = new Map<string, (typeof occurrences)[number] & { dateKey: string }>();
    occurrences.forEach((occurrence) => {
      if (String(occurrence.status || 'SCHEDULED').toUpperCase() !== 'SCHEDULED') return;
      if (Number(occurrence.seatsRemaining || 0) <= 0) return;
      const dateKey = new Date(occurrence.startTime).toISOString().slice(0, 10);
      if (!unique.has(dateKey)) unique.set(dateKey, { ...occurrence, dateKey });
    });
    return [...unique.values()].sort(
      (left, right) => new Date(left.startTime).getTime() - new Date(right.startTime).getTime()
    );
  }, [selectedTrip]);
  const repeatedTripBooking = Boolean(
    selectedTrip &&
    !roundTripBookingAvailable &&
    (String(selectedTrip.tripType || '').toUpperCase() !== 'ONE_TIME' || serviceDateOptions.length > 1)
  );
  const recommendedTier = useMemo(() => {
    if (!repeatedTripBooking || selectedTier || selectedServiceDateKeys.length === 0) return null;
    return [...availableReservationTiers]
      .filter((tier) => Number(tier.durationDays || 0) > selectedServiceDateKeys.length)
      .sort((left, right) => Number(left.durationDays || 0) - Number(right.durationDays || 0))[0] || null;
  }, [availableReservationTiers, repeatedTripBooking, selectedServiceDateKeys.length, selectedTier]);
  const selectedDatesLabel = selectedServiceDateKeys
    .map((dateKey) => {
      const option = serviceDateOptions.find((item) => item.dateKey === dateKey);
      return option ? formatDate(option.startTime) : dateKey;
    })
    .join(' • ');
  const activeServiceDateOption = useMemo(() => {
    if (!selectedTrip) return null;
    const selectedDateKey = selectedServiceDateKeys[0];
    return (
      (selectedDateKey ? serviceDateOptions.find((item) => item.dateKey === selectedDateKey) : null) ||
      serviceDateOptions[0] ||
      null
    );
  }, [selectedServiceDateKeys, selectedTrip, serviceDateOptions]);
  const availablePaymentMethods = useMemo(() => {
    if (!selectedTier?.paymentMethods?.length) return PAYMENT_METHODS;
    const allowed = new Set(selectedTier.paymentMethods);
    return PAYMENT_METHODS.filter((method) => allowed.has(method.value));
  }, [selectedTier]);

  const orderedPoints = useMemo(
    () => [...(selectedTrip?.pickupPoints || [])].sort((a, b) => a.stopOrder - b.stopOrder),
    [selectedTrip]
  );
  const orderedReturnPoints = useMemo(
    () => [...(selectedReturnTrip?.pickupPoints || [])].sort((a, b) => a.stopOrder - b.stopOrder),
    [selectedReturnTrip]
  );

  const selectedPickupOrder = useMemo(
    () => orderedPoints.find((point) => point.id === pickupPointId)?.stopOrder || 0,
    [orderedPoints, pickupPointId]
  );

  const pickupChoices = useMemo(
    () => orderedPoints.filter((point) => point.pointType !== 'DROPOFF'),
    [orderedPoints]
  );

  const dropChoices = useMemo(
    () => orderedPoints.filter((point) => point.stopOrder > selectedPickupOrder && point.pointType !== 'PICKUP'),
    [orderedPoints, selectedPickupOrder]
  );
  const selectedReturnPickupOrder = useMemo(
    () => orderedReturnPoints.find((point) => point.id === returnPickupPointId)?.stopOrder || 0,
    [orderedReturnPoints, returnPickupPointId]
  );
  const returnPickupChoices = useMemo(
    () => orderedReturnPoints.filter((point) => point.pointType !== 'DROPOFF'),
    [orderedReturnPoints]
  );
  const returnDropChoices = useMemo(
    () => orderedReturnPoints.filter((point) => point.stopOrder > selectedReturnPickupOrder && point.pointType !== 'PICKUP'),
    [orderedReturnPoints, selectedReturnPickupOrder]
  );

  const availableSeats = useMemo(() => {
    if (!selectedTrip) return [];
    const seatSource = activeServiceDateOption
      ? {
          ...selectedTrip,
          reservations: activeServiceDateOption.reservations || [],
          totalSeats: activeServiceDateOption.totalSeats || selectedTrip.totalSeats,
        }
      : selectedTrip;
    const reserved = parseReservedSeats(seatSource);
    return createSeatMap(seatSource.totalSeats).filter((seat) => !reserved.has(seat));
  }, [activeServiceDateOption, selectedTrip]);

  const sortedReservations = useMemo(
    () =>
      [...reservations].sort(
        (left, right) => new Date(right.trip.startTime).getTime() - new Date(left.trip.startTime).getTime()
      ),
    [reservations]
  );
  const filteredHistoryReservations = useMemo(() => {
    if (historyFilter === 'all') return sortedReservations;
    if (historyFilter === 'refunds') {
      return sortedReservations.filter((reservation) => Boolean(reservation.refunds?.length));
    }
    return sortedReservations.filter((reservation) => {
      const reservationStatus = String(reservation.status || '').toUpperCase();
      const tripStatus = String(reservation.trip?.status || '').toUpperCase();
      if (historyFilter === 'completed') {
        return reservationStatus === 'COMPLETED' || tripStatus === 'COMPLETED';
      }
      if (historyFilter === 'cancelled') {
        return reservationStatus === 'CANCELLED' || tripStatus === 'CANCELLED';
      }
      return (
        ['RESERVED', 'BOARDED', 'IN_PROGRESS'].includes(reservationStatus) &&
        !['COMPLETED', 'CANCELLED'].includes(tripStatus)
      );
    });
  }, [historyFilter, sortedReservations]);
  const reservationDisplayGroups = useMemo(
    () => groupReservationsForDisplay(filteredHistoryReservations),
    [filteredHistoryReservations]
  );

  const activeReservation = sortedReservations.find((reservation) =>
    ['RESERVED', 'BOARDED', 'IN_PROGRESS'].includes(String(reservation.status || '').toUpperCase())
  );
  const liveActiveReservation = sortedReservations.find((reservation) => {
    const reservationStatus = String(reservation.status || '').toUpperCase();
    const tripStatus = String(reservation.trip?.status || '').toUpperCase();
    return ['RESERVED', 'BOARDED', 'IN_PROGRESS'].includes(reservationStatus) && tripStatus === 'IN_PROGRESS';
  });
  const activeTripDriver = activeReservation?.trip.driverProfile || null;
  const liveTripDriver = liveActiveReservation?.trip.driverProfile || null;
  const selectedTripDriver = selectedTrip?.driverProfile || null;
  const selectedTripServiceOptions = useMemo(() => {
    if (!selectedTrip) return [];
    return (selectedTrip.occurrences?.length
      ? selectedTrip.occurrences
      : [{ id: selectedTrip.id, startTime: selectedTrip.startTime, seatsRemaining: selectedTrip.seatsRemaining, status: 'SCHEDULED' }]
    )
      .filter((occurrence) => String(occurrence.status || 'SCHEDULED').toUpperCase() === 'SCHEDULED')
      .sort((left, right) => new Date(left.startTime).getTime() - new Date(right.startTime).getTime());
  }, [selectedTrip]);
  const pickupSearchOptions = useMemo(
    () => uniqueStopOptions(trips, 'pickup', fromQuery),
    [fromQuery, trips]
  );
  const dropoffSearchOptions = useMemo(
    () => uniqueStopOptions(trips, 'dropoff', toQuery),
    [toQuery, trips]
  );
  const displayedTrips = useMemo(() => {
    return trips
      .filter((trip) => tripMatchesMobileRoute(trip, fromQuery, toQuery, serviceDateQuery, query))
      .filter((trip) => !favoritesOnly || localPreferences.favoriteTripIds.includes(trip.id))
      .sort((left, right) => {
        if (passengerCoords) {
          return nearestMobilePickupDistance(left, passengerCoords) - nearestMobilePickupDistance(right, passengerCoords);
        }
        return new Date(mobileTripOccurrences(left)[0]?.startTime || left.startTime).getTime()
          - new Date(mobileTripOccurrences(right)[0]?.startTime || right.startTime).getTime();
      });
  }, [
    favoritesOnly,
    fromQuery,
    localPreferences.favoriteTripIds,
    passengerCoords,
    query,
    serviceDateQuery,
    toQuery,
    trips,
  ]);
  const activeChatTripId = liveActiveReservation?.trip.id || activeReservation?.trip.id || null;
  const activeTripChatMessages = activeChatTripId ? tripChatByTripId[activeChatTripId] || [] : [];
  const activeTripChatParticipants = activeChatTripId
    ? tripChatParticipantsByTripId[activeChatTripId] || null
    : null;
  const focusedNotification = useMemo(
    () => notifications.find((item) => item.id === focusedNotificationId) || null,
    [focusedNotificationId, notifications]
  );
  const filteredNotifications = useMemo(
    () => {
      const search = notificationSearch.trim().toLocaleLowerCase('ar');
      return notifications.filter((item) => {
        if (!matchesNotificationFilter(item, notificationFilter)) return false;
        if (!search) return true;
        return [item.title, item.message, formatNotificationTypeLabel(item.type)]
          .join(' ')
          .toLocaleLowerCase('ar')
          .includes(search);
      });
    },
    [notificationFilter, notificationSearch, notifications]
  );
  const roundTripSubtotal = roundTripBookingAvailable
    ? Number(selectedTrip?.roundTripPrice || selectedReturnTrip?.roundTripPrice || 0)
    : 0;
  const roundTripFinalPrice = roundTripSubtotal > 0 ? roundTripSubtotal * 1.14 : 0;
  const previewedPriceLabel = selectedTier
    ? formatMoney(selectedTier.packagePrice)
    : reserveRoundTrip && roundTripFinalPrice > 0
      ? formatMoney(roundTripFinalPrice)
    : pricingPreview
      ? formatMoney(pricingPreview.finalPrice)
      : formatMoney(selectedTrip?.basePrice);
  const cancelledReservations = sortedReservations.filter(
    (reservation) => String(reservation.status || '').toUpperCase() === 'CANCELLED'
  );
  const pendingRefundCount = sortedReservations.reduce(
    (count, reservation) =>
      count +
      (reservation.refunds || []).filter((refund) =>
        ['PENDING_REVIEW', 'APPROVED'].includes(String(refund.status || '').toUpperCase())
      ).length,
    0
  );

  useEffect(() => {
    (async () => {
      const [stored, initialUrl, savedBiometric, availableBiometric, savedPreferences] = await Promise.all([
        getStoredToken(),
        Linking.getInitialURL(),
        getBiometricEnabled(),
        canUseBiometrics().catch(() => false),
        loadPassengerPreferences(),
      ]);
      setBiometricEnabled(savedBiometric);
      setBiometricAvailable(availableBiometric);
      setLocalPreferences(savedPreferences);
      const sharedTripId = parseSharedTripId(initialUrl);
      if (sharedTripId) await savePendingSharedTrip(sharedTripId);
      if (stored) {
        const unlocked =
          !savedBiometric || !availableBiometric
            ? true
            : await authenticateDevice().catch(() => false);
        if (unlocked) setToken(stored);
      }
      setBooting(false);
    })();
  }, []);

  useEffect(() => {
    if (!isOnline) {
      setNetworkNotice('أنت غير متصل بالإنترنت. سنعرض آخر بيانات محفوظة ونستأنف المزامنة تلقائيًا.');
    } else {
      setNetworkNotice((current) => current.startsWith('أنت غير متصل') ? '' : current);
    }
  }, [isOnline]);

  useEffect(() => {
    if (!token || !connectivity.recoveredAt) return;
    let active = true;
    setNetworkNotice('عاد الاتصال بالإنترنت. جارٍ مزامنة رحلاتك وحجوزاتك...');
    void refreshAll(token, query)
      .then(() => {
        if (active) setNetworkNotice('تم تحديث رحلاتك وحجوزاتك بنجاح.');
      })
      .catch(() => {
        if (active) setNetworkNotice('عاد الاتصال، لكن تعذر إكمال المزامنة. اسحب الصفحة لأسفل للمحاولة.');
      });
    const timer = setTimeout(() => {
      if (active) setNetworkNotice('');
    }, 4500);
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [connectivity.recoveredAt, token]);

  useEffect(() => {
    void refreshLocalCacheSummary();
  }, []);

  useEffect(() => {
    const subscription = Linking.addEventListener('url', ({ url }) => {
      const sharedTripId = parseSharedTripId(url);
      if (!sharedTripId) return;
      void savePendingSharedTrip(sharedTripId);
      setActiveTab('reserve');
      if (!token) {
        setAuthMode('login');
        return;
      }
      void focusSharedTrip(sharedTripId);
    });
    return () => subscription.remove();
  }, [token, trips]);

  useEffect(() => {
    if (!token) return;
    void refreshAll(token, query);
  }, [token]);

  useEffect(() => {
    if (!token || voucherBroadcastLoaded.current) return;
    voucherBroadcastLoaded.current = true;
    void apiRequest<{ vouchers: ActiveVoucher[] }>('/api/vouchers/active', '')
      .then((payload) => {
        const latest = payload.vouchers?.[0];
        if (!latest) return;
        setActiveVoucher(latest);
        setVoucherBroadcastSeconds(15);
        setVoucherBroadcastVisible(true);
      })
      .catch(() => undefined);
  }, [token]);

  useEffect(() => {
    if (!voucherBroadcastVisible) return;
    const pulse = Animated.loop(
      Animated.sequence([
        Animated.timing(voucherPulse, { toValue: 1, duration: 650, useNativeDriver: true }),
        Animated.timing(voucherPulse, { toValue: 0, duration: 650, useNativeDriver: true }),
      ]),
    );
    pulse.start();
    const timer = setInterval(() => {
      setVoucherBroadcastSeconds((current) => {
        if (current <= 1) {
          setVoucherBroadcastVisible(false);
          return 0;
        }
        return current - 1;
      });
    }, 1000);
    return () => {
      clearInterval(timer);
      pulse.stop();
    };
  }, [voucherBroadcastVisible, voucherPulse]);

  useEffect(() => {
    if (!token || bookingDraftRestored || trips.length === 0) return;
    void restorePassengerJourney();
  }, [bookingDraftRestored, token, trips]);

  useEffect(() => {
    if (!reservationModalOpen || !selectedTripId) return;
    const draft: PassengerBookingDraft = {
      tripId: selectedTripId,
      pickupPointId,
      dropoffPointId,
      paymentMethod,
      walletSenderNumber,
      selectedSeat,
      selectedTierId,
      selectedServiceDateKeys,
      reserveRoundTrip,
      returnPickupPointId,
      returnDropoffPointId,
      clientRequestId: bookingClientRequestId,
      updatedAt: Date.now(),
    };
    const timer = setTimeout(() => {
      void saveBookingDraft(draft);
    }, 250);
    return () => clearTimeout(timer);
  }, [
    bookingClientRequestId,
    dropoffPointId,
    paymentMethod,
    pickupPointId,
    reservationModalOpen,
    reserveRoundTrip,
    returnDropoffPointId,
    returnPickupPointId,
    selectedSeat,
    selectedServiceDateKeys,
    selectedTierId,
    selectedTripId,
    walletSenderNumber,
  ]);

  useEffect(() => {
    if (selectedTierId && !availableReservationTiers.some((tier) => tier.id === selectedTierId)) {
      setSelectedTierId('');
    }
  }, [availableReservationTiers, selectedTierId]);

  useEffect(() => {
    if (!token) return;

    void syncNotificationSetup(token);
    const interval = setInterval(() => {
      void loadNotifications(token, false);
      void loadPendingConfirmations(token, true);
    }, NOTIFICATION_POLL_MS);

    return () => clearInterval(interval);
  }, [token]);

  useEffect(() => {
    if (!token || notificationPermissionStatus !== 'granted') return;
    let active = true;
    void syncPassengerTripReminders(reservations, {
      enabled: localPreferences.tripRemindersEnabled,
      leadMinutes: localPreferences.reminderLeadMinutes,
    })
      .then((count) => {
        if (!active) return;
        if (!localPreferences.tripRemindersEnabled) {
          setReminderStatusNote('تنبيهات مواعيد الرحلات متوقفة على هذا الهاتف.');
          return;
        }
        setReminderStatusNote(
          count > 0
            ? `تم تجهيز ${count.toLocaleString('ar-EG')} تنبيه للرحلات القادمة.`
            : 'لا توجد رحلة قادمة تحتاج إلى تنبيه محلي الآن.',
        );
      })
      .catch(() => {
        if (active) setReminderStatusNote('تعذر تحديث تنبيهات المواعيد الآن. سيتم تكرار المحاولة تلقائيًا.');
      });
    return () => {
      active = false;
    };
  }, [
    localPreferences.reminderLeadMinutes,
    localPreferences.tripRemindersEnabled,
    notificationPermissionStatus,
    reservations,
    token,
  ]);

  useEffect(() => {
    if (!token) return;

    const receivedSubscription = Notifications.addNotificationReceivedListener(() => {
      void loadNotifications(token, false);
      void loadPendingConfirmations(token, true);
    });
    const responseSubscription = Notifications.addNotificationResponseReceivedListener((response) => {
      void handleNotificationResponse(response);
    });

    void Notifications.getLastNotificationResponseAsync()
      .then((response) => {
        if (response) return handleNotificationResponse(response);
        return undefined;
      })
      .catch(() => undefined);

    return () => {
      receivedSubscription.remove();
      responseSubscription.remove();
    };
  }, [token, trips]);

  useEffect(() => {
    if (!token || !activeChatTripId) return;

    void loadTripChat(token, activeChatTripId);
    const interval = setInterval(() => {
      void loadTripChat(token, activeChatTripId, true);
    }, 8000);

    return () => clearInterval(interval);
  }, [activeChatTripId, token]);

  useEffect(() => {
    if (!token || !liveActiveReservation?.id) return;

    let active = true;
    const refreshLiveTrip = async () => {
      try {
        const [nextReservations] = await Promise.all([
          loadReservations(token),
          loadNotifications(token, false).catch(() => null),
          loadPendingConfirmations(token, true).catch(() => null),
        ]);
        if (!active) return;
        setReservations(nextReservations);
        if (activeChatTripId) {
          void loadTripChat(token, activeChatTripId, true);
        }
      } catch {
        // Silently fail - background refresh
      }
    };

    const interval = setInterval(() => {
      void refreshLiveTrip();
    }, LIVE_TRIP_REFRESH_MS);

    const appStateSubscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        void refreshLiveTrip();
      }
    });

    return () => {
      active = false;
      clearInterval(interval);
      appStateSubscription.remove();
    };
  }, [activeChatTripId, liveActiveReservation?.id, token]);

  useEffect(() => {
    if (!reservationModalOpen || !token || !selectedTrip || !pickupPointId || !dropoffPointId) {
      setPricingPreview(null);
      setPricingError('');
      setPricingLoading(false);
      return;
    }

    let active = true;
    setPricingLoading(true);
    setPricingError('');

    void apiRequest<PricingPreview>('/api/mobile/pricing/calculate', token, {
      method: 'POST',
      body: JSON.stringify({
        tripId: selectedTrip.id,
        pickupPointId,
        dropoffPointId,
        seats: 1,
      }),
    })
      .then((payload) => {
        if (!active) return;
        setPricingPreview(payload);
      })
      .catch((error) => {
        if (!active) return;
        setPricingPreview(null);
        setPricingError(error instanceof Error ? error.message : 'تعذر حساب سعر هذا المسار الآن.');
      })
      .finally(() => {
        if (!active) return;
        setPricingLoading(false);
      });

    return () => {
      active = false;
    };
  }, [reservationModalOpen, token, selectedTrip, pickupPointId, dropoffPointId]);

  useEffect(() => {
    if (!roundTripBookingAvailable || !selectedReturnTrip) {
      setReserveRoundTrip(false);
      setReturnPickupPointId('');
      setReturnDropoffPointId('');
      return;
    }
    if (!reserveRoundTrip) return;
    const ordered = [...(selectedReturnTrip.pickupPoints || [])].sort((a, b) => a.stopOrder - b.stopOrder);
    const currentPickup = ordered.find((point) => point.id === returnPickupPointId);
    const pickup = currentPickup || ordered.find((point) => point.pointType !== 'DROPOFF') || ordered[0];
    const currentDropoff = ordered.find((point) => point.id === returnDropoffPointId && point.stopOrder > (pickup?.stopOrder || 0));
    const dropoff = currentDropoff || ordered.find((point) => point.stopOrder > (pickup?.stopOrder || 0) && point.pointType !== 'PICKUP');
    setReturnPickupPointId(pickup?.id || '');
    setReturnDropoffPointId(dropoff?.id || '');
  }, [reserveRoundTrip, roundTripBookingAvailable, selectedReturnTrip, returnPickupPointId, returnDropoffPointId]);

  useEffect(() => {
    if (availablePaymentMethods.length && !availablePaymentMethods.some((method) => method.value === paymentMethod)) {
      setPaymentMethod(availablePaymentMethods[0].value);
    }
  }, [availablePaymentMethods, paymentMethod]);

  async function loadTrips(
    currentToken: string,
    search = '',
    routeSearch?: { from?: string; to?: string; date?: string; coords?: { lat: number; lng: number } | null }
  ) {
    const params: string[] = [];
    const q = search.trim();
    const from = String(routeSearch?.from || '').trim();
    const to = String(routeSearch?.to || '').trim();
    const date = String(routeSearch?.date || '').trim();
    if (q) params.push(`q=${encodeURIComponent(q)}`);
    if (from) params.push(`from=${encodeURIComponent(from)}`);
    if (to) params.push(`to=${encodeURIComponent(to)}`);
    if (date) params.push(`date=${encodeURIComponent(date)}`);
    if (routeSearch?.coords) {
      params.push(`lat=${encodeURIComponent(String(routeSearch.coords.lat))}`);
      params.push(`lng=${encodeURIComponent(String(routeSearch.coords.lng))}`);
    }
    const path = params.length ? `/api/mobile/trips?${params.join('&')}` : '/api/mobile/trips';
    const payload = await apiRequest<unknown>(path, currentToken);
    return parseArrayPayload<Trip>(payload);
  }

  async function loadReservations(currentToken: string) {
    const payload = await apiRequest<unknown>('/api/mobile/reservations', currentToken);
    return parseArrayPayload<Reservation>(payload);
  }

  async function loadReservationTiers(currentToken: string) {
    const payload = await apiRequest<{ tiers: ReservationTier[] }>('/api/mobile/tiers', currentToken);
    return payload.tiers || [];
  }

  async function loadLoyalty(currentToken: string) {
    const payload = await apiRequest<{ data: PassengerLoyaltyPayload }>('/api/mobile/loyalty', currentToken);
    return payload.data;
  }

  function openReservationReview(reservation: Reservation) {
    setReviewReservationId(reservation.id);
    setReviewRating(Math.max(1, Math.min(5, Number(reservation.review?.rating || 5))));
    setReviewBody(reservation.review?.reviewBody || '');
  }

  async function submitReservationReview() {
    if (!token || !reviewReservationId || reviewSubmitting) return;
    setReviewSubmitting(true);
    try {
      await apiRequest(`/api/mobile/reservations/${reviewReservationId}/review`, token, {
        method: 'POST',
        body: JSON.stringify({
          rating: reviewRating,
          reviewTitle: '',
          reviewBody: reviewBody.trim(),
          complaint: '',
        }),
      });
      setReviewReservationId('');
      setReviewBody('');
      await refreshAll(token, query);
      Alert.alert('تم حفظ التقييم', 'شكراً لك. تم ربط تقييمك بالرحلة والسائق.');
    } catch (error) {
      Alert.alert('تعذر حفظ التقييم', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setReviewSubmitting(false);
    }
  }

  async function loadWalletSettings(currentToken: string) {
    return apiRequest<WalletSettingsPayload>('/api/mobile/wallet/transactions', currentToken);
  }

  async function loadMe(currentToken: string) {
    return apiRequest<MobileMePayload>('/api/mobile/me', currentToken);
  }

  async function updateMobileSettings(nextSettings: Partial<MobileMePayload['user']>) {
    if (!token || settingsSaving) return;
    setSettingsSaving(true);
    try {
      const payload = await apiRequest<MobileMePayload>('/api/mobile/me', token, {
        method: 'PATCH',
        body: JSON.stringify(nextSettings),
      });
      setMeUser(payload.user);
      if (nextSettings.pushNotifications === false) {
        await unregisterCurrentPushDevice(token);
        setNotificationStatusNote('تم إيقاف الإشعارات الفورية لهذا الحساب.');
      } else if (nextSettings.pushNotifications === true) {
        setNotificationStatusNote('جارٍ ربط هذا الجهاز بالإشعارات...');
        await syncNotificationSetup(token);
      }
      Alert.alert('تم حفظ الإعدادات', 'تم تحديث إعدادات حسابك بنجاح.');
    } catch (error) {
      Alert.alert('تعذر حفظ الإعدادات', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setSettingsSaving(false);
    }
  }

  async function updateLocalPreferences(next: PassengerLocalPreferences, confirmation?: string) {
    setLocalPreferences(next);
    try {
      await savePassengerPreferences(next);
      if (confirmation) Alert.alert('تم الحفظ', confirmation);
    } catch {
      Alert.alert('تعذر الحفظ', 'لم نتمكن من حفظ هذا الإعداد على الهاتف. حاول مرة أخرى.');
    }
  }

  function toggleFavoriteTrip(tripId: string) {
    const isFavorite = localPreferences.favoriteTripIds.includes(tripId);
    const favoriteTripIds = isFavorite
      ? localPreferences.favoriteTripIds.filter((id) => id !== tripId)
      : [...localPreferences.favoriteTripIds, tripId];
    void updateLocalPreferences({ ...localPreferences, favoriteTripIds });
  }

  async function shareReservationTrip(reservation: Reservation) {
    const tripUrl = `https://softcarshuttle.com/trip/view/${encodeURIComponent(reservation.trip.id)}`;
    const message = [
      `رحلتي مع SOFT CAR: ${reservation.trip.title}`,
      `${reservation.pickupPoint.name} ← ${reservation.dropoffPoint.name}`,
      `موعد الصعود: ${formatDate(reservation.trip.startTime)}`,
      reservation.ticketCode ? `رقم التذكرة: ${reservation.ticketCode}` : '',
      tripUrl,
    ]
      .filter(Boolean)
      .join('\n');
    try {
      await Share.share({ message, url: tripUrl, title: `رحلة ${reservation.trip.title}` });
    } catch {
      Alert.alert('تعذر مشاركة الرحلة', 'حاول مرة أخرى أو افتح رابط الرحلة من سجل الحجوزات.');
    }
  }

  async function addReservationCalendarEvent(reservation: Reservation) {
    try {
      const result = await addReservationToDeviceCalendar(reservation);
      Alert.alert('تمت إضافة الرحلة', `تم حفظ موعد الرحلة في تقويم ${result.calendarTitle}.`);
    } catch (error) {
      Alert.alert('تعذر إضافة الرحلة للتقويم', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    }
  }

  function repeatReservation(reservation: Reservation) {
    const normalizedTitle = reservation.trip.title.trim().toLocaleLowerCase('ar');
    const matchingTrip =
      trips.find((trip) => trip.id === reservation.trip.id) ||
      trips.find((trip) => trip.title.trim().toLocaleLowerCase('ar') === normalizedTitle);

    setActiveTab('reserve');
    if (!matchingTrip) {
      setQuery(reservation.trip.title);
      setNetworkNotice('لم نجد موعدًا متاحًا لنفس الرحلة الآن. تم تجهيز البحث باسم الرحلة لإظهار أقرب بديل.');
      return;
    }

    openTripReservation(matchingTrip);
    const pickup = matchingTrip.pickupPoints.find(
      (point) => point.name.trim().toLocaleLowerCase('ar') === reservation.pickupPoint.name.trim().toLocaleLowerCase('ar')
    );
    const dropoff = matchingTrip.pickupPoints.find(
      (point) => point.name.trim().toLocaleLowerCase('ar') === reservation.dropoffPoint.name.trim().toLocaleLowerCase('ar')
    );
    if (pickup) setPickupPointId(pickup.id);
    if (dropoff) setDropoffPointId(dropoff.id);
    if (PAYMENT_METHODS.some((method) => method.value === reservation.paymentMethod)) {
      setPaymentMethod(reservation.paymentMethod as PaymentMethod);
    }
    setNetworkNotice('تم تجهيز نفس المسار. راجع الموعد والمقعد ثم أكّد الحجز.');
  }

  async function refreshLocalCacheSummary() {
    const summary = await getPassengerCacheSummary().catch(() => null);
    if (summary) setCacheSummary(summary);
  }

  async function checkForAppUpdate() {
    if (updateChecking) return;
    setUpdateChecking(true);
    try {
      if (!Updates.isEnabled) {
        const message = 'فحص التحديثات يعمل داخل النسخة المثبتة من المتجر أو ملف الإصدار، وليس داخل وضع التطوير.';
        setUpdateStatusNote(message);
        Alert.alert('التحديثات التلقائية', message);
        return;
      }

      setUpdateStatusNote('جارٍ فحص أحدث إصدار آمن...');
      const result = await Updates.checkForUpdateAsync();
      if (!result.isAvailable) {
        const message = 'أنت تستخدم أحدث تحديث متاح.';
        setUpdateStatusNote(message);
        Alert.alert('التطبيق محدّث', message);
        return;
      }

      setUpdateStatusNote('تم العثور على تحديث. جارٍ تنزيله...');
      await Updates.fetchUpdateAsync();
      setUpdateStatusNote('تم تنزيل التحديث وأصبح جاهزًا للتثبيت.');
      Alert.alert(
        'التحديث جاهز',
        'أعد تشغيل التطبيق الآن لتطبيق النسخة الجديدة. لن تفقد حجزك الجاري.',
        [
          { text: 'لاحقًا', style: 'cancel' },
          { text: 'إعادة التشغيل الآن', onPress: () => void Updates.reloadAsync() },
        ]
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : 'تعذر فحص التحديث الآن.';
      setUpdateStatusNote('تعذر فحص التحديث. تحقق من الاتصال ثم حاول مرة أخرى.');
      Alert.alert('تعذر فحص التحديث', message);
    } finally {
      setUpdateChecking(false);
    }
  }

  async function clearLocalCacheAndRefresh() {
    if (cacheBusy) return;
    setCacheBusy(true);
    try {
      await clearPassengerCache();
      await refreshLocalCacheSummary();
      if (token && isOnline) {
        await refreshAll(token, query);
        await refreshLocalCacheSummary();
      }
      Alert.alert(
        'تم تنظيف البيانات المؤقتة',
        isOnline
          ? 'تم تنزيل نسخة حديثة من الرحلات والحجوزات بدون حذف الحساب أو الحجز غير المكتمل.'
          : 'تم تنظيف البيانات المؤقتة. ستُحمّل نسخة جديدة عند عودة الاتصال.'
      );
    } catch (error) {
      Alert.alert('تعذر تنظيف البيانات', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setCacheBusy(false);
    }
  }

  function confirmClearLocalCache() {
    Alert.alert(
      'تنظيف البيانات المؤقتة',
      'لن يتم حذف حسابك أو جلسة الدخول أو تفاصيل الحجز غير المكتمل. سيتم فقط تحديث نسخ الرحلات والحجوزات المحفوظة.',
      [
        { text: 'إلغاء', style: 'cancel' },
        { text: 'تنظيف وتحديث', style: 'destructive', onPress: () => void clearLocalCacheAndRefresh() },
      ]
    );
  }

  async function toggleBiometricUnlock() {
    if (!biometricAvailable) {
      Alert.alert('البصمة غير متاحة', 'أضف بصمة أو قفل وجه من إعدادات الهاتف أولًا.');
      return;
    }
    const nextValue = !biometricEnabled;
    if (nextValue) {
      const confirmed = await authenticateDevice().catch(() => false);
      if (!confirmed) return;
    }
    await persistBiometricEnabled(nextValue);
    setBiometricEnabled(nextValue);
    Alert.alert('تم حفظ إعداد الأمان', nextValue ? 'سيطلب التطبيق التحقق عند فتح الحساب.' : 'تم إيقاف الفتح بالبصمة.');
  }

  async function loadSupportTickets(currentToken: string) {
    const payload = await apiRequest<unknown>('/api/mobile/support-tickets', currentToken);
    return parseArrayPayload<SupportTicket>(payload);
  }

  async function loadTripChat(currentToken: string, tripId: string, silent = false) {
    if (!tripId) return;
    if (!silent) setChatLoadingTripId(tripId);
    try {
      const payload = await apiRequest<TripChatPayload>(`/api/mobile/trips/${tripId}/messages`, currentToken);
      setTripChatByTripId((current) => ({ ...current, [tripId]: payload.messages }));
      setTripChatParticipantsByTripId((current) => ({ ...current, [tripId]: payload.participants }));
    } catch (error) {
      if (!silent) {
        Alert.alert('تعذر تحميل محادثة الرحلة', error instanceof Error ? error.message : 'تعذر تحميل رسائل الرحلة الآن.');
      }
    } finally {
      if (!silent) setChatLoadingTripId('');
    }
  }

  async function sendTripChatMessage() {
    if (!token || !activeChatTripId || !chatDraft.trim()) return;
    setChatSendingTripId(activeChatTripId);
    try {
      await apiRequest(`/api/mobile/trips/${activeChatTripId}/messages`, token, {
        method: 'POST',
        body: JSON.stringify({ message: chatDraft.trim() }),
      });
      setChatDraft('');
      await loadTripChat(token, activeChatTripId, true);
    } catch (error) {
      Alert.alert('تعذر إرسال الرسالة', error instanceof Error ? error.message : 'فشل إرسال رسالة الرحلة.');
    } finally {
      setChatSendingTripId('');
    }
  }

  async function updateAppBadge(count: number) {
    await Notifications.setBadgeCountAsync(Math.max(0, count)).catch(() => false);
  }

  async function loadNotifications(currentToken: string, _notifyOnNew = false, cursor = '') {
    if (!cursor) setNotificationLoading(true);
    try {
    const query = new URLSearchParams({ limit: '25' });
    if (cursor) query.set('cursor', cursor);
    const payload = await apiRequest<NotificationFeedPayload>(`/api/mobile/notifications?${query.toString()}`, currentToken);
    const nextNotifications = Array.isArray(payload?.notifications) ? payload.notifications : [];
    const nextUnreadCount = Number.isFinite(Number(payload?.unreadCount))
      ? Math.max(0, Number(payload.unreadCount))
      : nextNotifications.filter((item) => !item.readAt).length;
    setNotifications((current) => {
      if (!cursor) return nextNotifications;
      const merged = new Map(current.map((item) => [item.id, item]));
      nextNotifications.forEach((item) => merged.set(item.id, item));
      return [...merged.values()].sort(
        (left, right) => new Date(right.sentAt).getTime() - new Date(left.sentAt).getTime()
      );
    });
    setUnreadNotifications(nextUnreadCount);
    setNotificationNextCursor(payload?.nextCursor || null);
    await updateAppBadge(nextUnreadCount);
    } finally {
      if (!cursor) setNotificationLoading(false);
    }
  }

  async function loadPendingConfirmations(currentToken: string, openPanel = false) {
    try {
      const payload = await apiRequest<{ confirmations?: PassengerTripConfirmation[] }>(
        '/api/mobile/reservations/confirmations',
        currentToken,
      );
      const confirmations = Array.isArray(payload?.confirmations) ? payload.confirmations : [];
      setPendingConfirmations(confirmations);
      if (openPanel && confirmations.length > 0) {
        setConfirmationPanelOpen(true);
      }
      return confirmations;
    } catch (error) {
      if (openPanel) {
        Alert.alert('تعذر تحميل طلب التأكيد', error instanceof Error ? error.message : 'حاول مرة أخرى.');
      }
      return [];
    }
  }

  async function respondToFocusedConfirmation(action: 'confirm' | 'reject') {
    if (!token || !focusedPassengerConfirmation || confirmationBusyId) return;
    const confirmation = focusedPassengerConfirmation;
    setConfirmationBusyId(confirmation.id);
    try {
      await apiRequest(`/api/mobile/reservations/confirmations/${confirmation.id}`, token, {
        method: 'PATCH',
        body: JSON.stringify({
          action,
          confirmedPayment: action === 'confirm',
          confirmedBoarding: action === 'confirm',
          responseNote: action === 'reject'
            ? 'الراكب رفض تأكيد التحصيل أو الصعود من تطبيق الراكب.'
            : 'الراكب أكد التحصيل والصعود من تطبيق الراكب.',
        }),
      });
      setPendingConfirmations((current) => current.filter((item) => item.id !== confirmation.id));
      setConfirmationPanelOpen(false);
      await Promise.allSettled([
        refreshAll(token, query),
        loadNotifications(token, false),
      ]);
      Alert.alert(
        action === 'confirm' ? 'تم تأكيد الرحلة' : 'تم رفض طلب السائق',
        action === 'confirm'
          ? 'تم حفظ تأكيد الدفع والصعود وربطه بالحجز.'
          : 'تم إرسال الرفض للإدارة والسائق. إذا تكررت المحاولة سيتم فتح بلاغ تلقائي.'
      );
    } catch (error) {
      Alert.alert('تعذر إرسال الرد', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setConfirmationBusyId('');
    }
  }

  async function markAllNotificationsRead() {
    if (!token || unreadNotifications === 0) return;
    try {
      await apiRequest('/api/mobile/notifications', token, {
        method: 'POST',
        body: JSON.stringify({ action: 'mark-all-read' }),
      });
      setNotifications((current) =>
        current.map((item) => ({
          ...item,
          readAt: item.readAt || new Date().toISOString(),
        }))
      );
      setUnreadNotifications(0);
      await updateAppBadge(0);
    } catch (error) {
      Alert.alert('تعذر تحديث الإشعارات', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    }
  }

  async function markNotificationsRead(ids: string[], read = true) {
    const safeIds = ids.filter(Boolean);
    if (!token || safeIds.length === 0) return;
    const affectedUnread = notifications.filter((item) => safeIds.includes(item.id) && !item.readAt).length;
    try {
      await apiRequest('/api/mobile/notifications', token, {
        method: 'POST',
        body: JSON.stringify({ action: read ? 'mark-read' : 'mark-unread', ids: safeIds }),
      });
      const nowIso = read ? new Date().toISOString() : null;
      setNotifications((current) =>
        current.map((item) => (safeIds.includes(item.id) ? { ...item, readAt: nowIso } : item))
      );
      const nextUnread = read
        ? Math.max(0, unreadNotifications - affectedUnread)
        : unreadNotifications + safeIds.filter((id) => notifications.some((item) => item.id === id && item.readAt)).length;
      setUnreadNotifications(nextUnread);
      await updateAppBadge(nextUnread);
    } catch (error) {
      Alert.alert('تعذر تحديث الإشعار', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    }
  }

  async function deleteNotifications(ids: string[]) {
    const safeIds = ids.filter(Boolean);
    if (!token || safeIds.length === 0) return;
    const removedUnread = notifications.filter((item) => safeIds.includes(item.id) && !item.readAt).length;
    try {
      await apiRequest('/api/mobile/notifications', token, {
        method: 'POST',
        body: JSON.stringify({ action: 'delete', ids: safeIds }),
      });
      setNotifications((current) => current.filter((item) => !safeIds.includes(item.id)));
      setFocusedNotificationId('');
      const nextUnread = Math.max(0, unreadNotifications - removedUnread);
      setUnreadNotifications(nextUnread);
      await updateAppBadge(nextUnread);
    } catch (error) {
      Alert.alert('تعذر حذف الإشعار', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    }
  }

  async function openNotificationDetail(item: NotificationItem) {
    setFocusedNotificationId(item.id);
    if (!item.readAt) {
      await markNotificationsRead([item.id]);
    }
  }

  async function navigateFromNotification(actionUrlValue: unknown, typeValue: unknown) {
    const actionUrl = String(actionUrlValue || '');
    const type = String(typeValue || '').toLowerCase();
    const sharedTripMatch = actionUrl.match(/\/trip\/view\/([^/?#]+)/i);

    setNotificationPanelOpen(false);
    setFocusedNotificationId('');

    if (sharedTripMatch?.[1]) {
      const tripId = decodeURIComponent(sharedTripMatch[1]);
      await savePendingSharedTrip(tripId);
      setActiveTab('reserve');
      await focusSharedTrip(tripId);
      return;
    }
    if (actionUrl.includes('confirmationId=') || type.includes('confirmation')) {
      if (token) await loadPendingConfirmations(token, true);
      return;
    }
    if (actionUrl.includes('tab=history') || type.includes('reservation') || type.includes('refund') || type.includes('payment')) {
      setActiveTab('history');
      return;
    }
    if (actionUrl.includes('support') || type.includes('support') || type.includes('chat') || type.includes('ticket') || type.includes('complaint')) {
      setActiveTab('support');
      return;
    }
    if (actionUrl.includes('loyalty') || type.includes('loyalty') || type.includes('reward') || type.includes('tier')) {
      setActiveTab('loyalty');
      return;
    }
    if (actionUrl.includes('settings') || type.includes('security') || type.includes('account')) {
      setActiveTab('settings');
      return;
    }
    if (actionUrl.includes('/dashboard/user/live') || type.includes('trip') || type.includes('driver')) {
      setActiveTab('reserve');
      return;
    }
    if (actionUrl) {
      const targetUrl = actionUrl.startsWith('http') ? actionUrl : `${apiBaseUrl}${actionUrl}`;
      await Linking.openURL(targetUrl).catch(() => {
        Alert.alert('تعذر فتح الرابط', 'يمكنك مراجعة الإشعار من داخل التطبيق.');
      });
    }
  }

  function runNotificationAction(item: NotificationItem | null) {
    if (!item) return;
    void navigateFromNotification(item.actionUrl, item.type);
  }

  async function handleNotificationResponse(response: Notifications.NotificationResponse) {
    const responseId = response.notification.request.identifier;
    if (handledNotificationResponseId.current === responseId) return;
    handledNotificationResponseId.current = responseId;
    await Notifications.clearLastNotificationResponseAsync().catch(() => undefined);

    const data = response.notification.request.content.data || {};
    const notificationId = String(data.notificationId || '');
    if (notificationId && token) {
      await markNotificationsRead([notificationId]).catch(() => undefined);
    }
    await navigateFromNotification(data.actionUrl, data.type);
  }

  async function syncNotificationSetup(currentToken: string) {
    const account = await apiRequest<MobileMePayload>('/api/mobile/me', currentToken).catch(() => null);
    if (account?.user?.pushNotifications === false) {
      setNotificationPermissionStatus('denied');
      setNotificationStatusNote('إشعارات التطبيق متوقفة من إعدادات حسابك.');
      await unregisterCurrentPushDevice(currentToken);
      await loadNotifications(currentToken, false).catch(() => undefined);
      return;
    }

    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('softcar-updates', {
        name: 'تحديثات سوفت كار',
        description: 'تنبيهات الرحلات والحجوزات والدعم والمدفوعات',
        importance: Notifications.AndroidImportance.MAX,
        vibrationPattern: [0, 250, 250, 250],
        lightColor: '#D32F2F',
        sound: 'default',
        enableVibrate: true,
        showBadge: true,
      }).catch(() => undefined);
    }

    const permission = await Notifications.getPermissionsAsync();
    let finalStatus = permission.status;

    if (finalStatus !== 'granted') {
      const requestResult = await Notifications.requestPermissionsAsync();
      finalStatus = requestResult.status;
    }

    if (finalStatus !== 'granted') {
      setNotificationPermissionStatus('denied');
      setNotificationStatusNote('الإشعارات محظورة على هذا الجهاز.');
      await loadNotifications(currentToken, false).catch(() => undefined);
      return;
    }
    setNotificationPermissionStatus('granted');

    const projectId =
      Constants.easConfig?.projectId ||
      Constants.expoConfig?.extra?.eas?.projectId ||
      Constants.expoConfig?.extra?.expoProjectId ||
      '';

    if (projectId) {
      try {
        const expoToken = await Notifications.getExpoPushTokenAsync({ projectId });
        registeredPushToken.current = expoToken.data;
        await apiRequest('/api/mobile/push/register', currentToken, {
          method: 'POST',
          body: JSON.stringify({
            token: expoToken.data,
            platform: Platform.OS,
            deviceName: 'سوفت كار شاتل - الراكب',
          }),
        });
        setNotificationStatusNote('تم ربط الإشعارات الفورية بهذا الجهاز.');
      } catch {
        setNotificationStatusNote('الإشعارات المحلية تعمل. ما زال الإرسال الفوري يحتاج إلى معرّف مشروع Expo وبياناته.');
      }
    } else {
      setNotificationStatusNote('الإشعارات المحلية تعمل. أضف معرّف مشروع Expo لتفعيل الإرسال الفوري عن بعد.');
    }

    await loadNotifications(currentToken, false).catch(() => undefined);
  }

  async function openNotificationSettings() {
    const permission = await Notifications.getPermissionsAsync().catch(() => null);
    if (permission?.status !== 'granted' && permission?.canAskAgain) {
      const result = await Notifications.requestPermissionsAsync();
      if (result.status === 'granted' && token) {
        await syncNotificationSetup(token);
        return;
      }
    }
    await Linking.openSettings().catch(() => {
      Alert.alert('افتح إعدادات الهاتف', 'فعّل إشعارات سوفت كار من إعدادات التطبيقات.');
    });
  }

  async function unregisterCurrentPushDevice(currentToken: string) {
    if (!registeredPushToken.current) return;
    await apiRequest('/api/mobile/push/register', currentToken, {
      method: 'DELETE',
      body: JSON.stringify({ token: registeredPushToken.current }),
    }).catch(() => undefined);
    registeredPushToken.current = '';
    await updateAppBadge(0);
  }

  async function refreshAll(currentToken: string, search = '') {
    const [tripsResult, reservationsResult, meResult, tiersResult, walletResult, supportResult, loyaltyResult, confirmationsResult] = await Promise.allSettled([
      loadTrips(currentToken, search),
      loadReservations(currentToken),
      loadMe(currentToken),
      loadReservationTiers(currentToken),
      loadWalletSettings(currentToken),
      loadSupportTickets(currentToken),
      loadLoyalty(currentToken),
      loadPendingConfirmations(currentToken),
    ]);

    if (meResult.status === 'rejected') throw meResult.reason;
    if (!meResult.value?.user) {
      throw new Error('تعذر تحميل بيانات الحساب. سجّل الدخول مرة أخرى.');
    }
    setMeUser(meResult.value.user);

    if (tripsResult.status === 'fulfilled') {
      setTrips(tripsResult.value);
      await cacheTrips(tripsResult.value);
      setNetworkNotice('');
    } else {
      const cachedTrips = await getCachedTrips(24 * 60 * 60 * 1000);
      if (!cachedTrips) throw tripsResult.reason;
      setTrips(cachedTrips);
      setNetworkNotice('أنت تعمل الآن على آخر نسخة محفوظة من الرحلات. اسحب للتحديث عند عودة الاتصال.');
    }

    if (reservationsResult.status === 'fulfilled') {
      setReservations(reservationsResult.value);
      await cacheReservations(reservationsResult.value);
    } else {
      const cachedReservations = await getCachedReservations(24 * 60 * 60 * 1000);
      if (cachedReservations) setReservations(cachedReservations);
    }

    setReservationTiers(tiersResult.status === 'fulfilled' ? tiersResult.value : []);
    setSupportTickets(supportResult.status === 'fulfilled' ? supportResult.value : []);
    if (loyaltyResult.status === 'fulfilled') setLoyalty(loyaltyResult.value);
    if (confirmationsResult.status === 'fulfilled' && confirmationsResult.value.length > 0) {
      setConfirmationPanelOpen(true);
    }
    const walletPayload = walletResult.status === 'fulfilled' ? walletResult.value : null;
    setWalletData(walletPayload);
    if (walletPayload?.wallet) {
      setWalletRecipientNumber(walletPayload.wallet.recipientNumber || '');
      setWalletInstructions(walletPayload.wallet.instructionsAr || walletPayload.wallet.instructionsEn || '');
      setWalletTopupSender((current) => current || meUser?.phone || '');
    }
    await refreshLocalCacheSummary();
  }

  async function openDialer(phone: string | null | undefined) {
    try {
      const normalized = String(phone || '').trim();
      if (!normalized) {
        Alert.alert('لا يوجد رقم متاح', 'سيظهر رقم السائق هنا بعد تعيينه على هذه الرحلة.');
        return;
      }
      await Linking.openURL(`tel:${normalized}`);
    } catch (error) {
      Alert.alert('تعذر فتح الاتصال', error instanceof Error ? error.message : 'تعذر فتح شاشة الاتصال الآن.');
    }
  }

  async function createSupportTicket() {
    if (!token || supportSubmitting) return;
    const subject = supportSubject.trim();
    const message = supportMessage.trim();
    if (subject.length < 3 || message.length < 10) {
      Alert.alert('طلب الدعم يحتاج تفاصيل', 'اكتب عنوانًا مختصرًا ووصفًا لا يقل عن 10 أحرف.');
      return;
    }

    setSupportSubmitting(true);
    try {
      const ticket = await apiRequest<SupportTicket>('/api/mobile/support-tickets', token, {
        method: 'POST',
        body: JSON.stringify({
          subject,
          message,
          category: supportCategory,
          priority: supportPriority,
        }),
      });
      setSupportTickets((current) => [ticket, ...current.filter((item) => item.id !== ticket.id)]);
      setSupportSubject('');
      setSupportMessage('');
      setSupportCategory('GENERAL');
      setSupportPriority('NORMAL');
      setExpandedSupportTicketId(ticket.id);
      Alert.alert('تم إنشاء طلب الدعم', 'سيقوم فريق خدمة العملاء بمراجعته والرد عليه من لوحة المتابعة.');
    } catch (error) {
      Alert.alert('تعذر إنشاء طلب الدعم', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setSupportSubmitting(false);
    }
  }

  function openRefundRequest(reservationId: string, scope: 'single' | 'trip-group') {
    setRefundReservationId(reservationId);
    setRefundScope(scope);
    setRefundReason('');
  }

  async function submitRefundRequest() {
    if (!token || refundSubmitting || !refundReservationId) return;
    if (refundReason.trim().length < 10) {
      Alert.alert('سبب الاسترداد مطلوب', 'اكتب سببًا واضحًا لا يقل عن 10 أحرف.');
      return;
    }

    setRefundSubmitting(true);
    try {
      const result = await apiRequest<{ count: number; totalAmount: number }>('/api/mobile/refunds', token, {
        method: 'POST',
        body: JSON.stringify({
          reservationId: refundReservationId,
          scope: refundScope,
          reason: refundReason.trim(),
        }),
      });
      setRefundReservationId('');
      setRefundReason('');
      await refreshAll(token, query);
      Alert.alert(
        'تم إرسال طلب الاسترداد',
        `تم تسجيل ${result.count} طلب بقيمة إجمالية ${formatMoney(result.totalAmount)} وينتظر مراجعة الإدارة المالية.`
      );
    } catch (error) {
      Alert.alert('تعذر طلب الاسترداد', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setRefundSubmitting(false);
    }
  }

  async function submitWalletTopup() {
    if (!token || walletTopupSubmitting) return;

    const amount = Number(walletTopupAmount.replace(',', '.'));
    if (!Number.isFinite(amount) || amount <= 0) {
      Alert.alert('مبلغ غير صحيح', 'أدخل مبلغ شحن صحيح أكبر من صفر.');
      return;
    }
    if (walletTopupChannel === 'TRANSFER' && !walletTopupSender.trim()) {
      Alert.alert('رقم التحويل مطلوب', 'أدخل رقم الهاتف الذي تم التحويل منه حتى يراجع فريق المالية طلب الشحن.');
      return;
    }

    setWalletTopupSubmitting(true);
    try {
      const result = await apiRequest<any>('/api/mobile/wallet/transactions', token, {
        method: 'POST',
        body: JSON.stringify({
          amount,
          channel: walletTopupChannel,
          senderNumber: walletTopupSender.trim(),
        }),
      });

      if (walletTopupChannel === 'CARD') {
        const checkoutUrl =
          result?.checkout?.checkoutUrl ||
          result?.transaction?.checkoutUrl ||
          result?.checkoutUrl ||
          '';
        if (checkoutUrl) {
          await Linking.openURL(checkoutUrl);
          Alert.alert('تم فتح صفحة الدفع', 'بعد إتمام الدفع سيتم تحديث رصيد المحفظة تلقائيا.');
        } else {
          Alert.alert('بوابة الدفع غير جاهزة', result?.message || 'تم إنشاء طلب الدفع ولكن رابط بوابة فيزا غير متاح الآن.');
        }
      } else {
        Alert.alert('تم إرسال طلب الشحن', 'سيظهر المبلغ في الرصيد المتاح بعد مراجعة التحويل من فريق المالية.');
      }

      setWalletTopupAmount('');
      await refreshAll(token, query);
    } catch (error) {
      Alert.alert('تعذر شحن المحفظة', error instanceof Error ? error.message : 'حاول مرة أخرى.');
    } finally {
      setWalletTopupSubmitting(false);
    }
  }

  async function openPointDirections(point: { name?: string | null; latitude?: number | string | null; longitude?: number | string | null } | null | undefined) {
    try {
      const lat = Number(point?.latitude);
      const lng = Number(point?.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        Alert.alert('الاتجاهات غير متاحة', 'هذه المحطة لا تحتوي على إحداثيات صحيحة.');
        return;
      }

      const googleMapsUrl = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}&travelmode=walking`;
      await Linking.openURL(googleMapsUrl);
    } catch (error) {
      Alert.alert('تعذر فتح الاتجاهات', error instanceof Error ? error.message : 'تعذر فتح الخرائط الآن.');
    }
  }

  function openTripReservation(trip: Trip) {
    setBookingRecoveryNote('');
    setSelectedTripId(trip.id);
    setPricingPreview(null);
    setPricingError('');
    setPricingLoading(false);

    const ordered = [...(trip.pickupPoints || [])].sort((a, b) => a.stopOrder - b.stopOrder);
    const firstPickup = ordered.find((point) => point.pointType !== 'DROPOFF') || ordered[0];
    const firstDrop = ordered.find(
      (point) => point.stopOrder > (firstPickup?.stopOrder || 0) && point.pointType !== 'PICKUP'
    );

    const reserved = parseReservedSeats(trip);
    const firstOpenSeat = createSeatMap(trip.totalSeats).find((seat) => !reserved.has(seat)) || '';

    setPickupPointId(firstPickup?.id || '');
    setDropoffPointId(firstDrop?.id || '');
    setSelectedSeat(firstOpenSeat);
    setPaymentMethod('CASH');
    setWalletSenderNumber(meUser?.phone || walletSenderNumber);
    setSelectedTierId('');
    setVoucherCode(promotedVoucherCode);
    setVoucherQuote(null);
    setVoucherError('');
    setReserveRoundTrip(false);
    const orderedReturn = [...(trip.returnTrip?.pickupPoints || [])].sort((a, b) => a.stopOrder - b.stopOrder);
    const firstReturnPickup = orderedReturn.find((point) => point.pointType !== 'DROPOFF') || orderedReturn[0];
    const firstReturnDrop = orderedReturn.find(
      (point) => point.stopOrder > (firstReturnPickup?.stopOrder || 0) && point.pointType !== 'PICKUP'
    );
    setReturnPickupPointId(firstReturnPickup?.id || '');
    setReturnDropoffPointId(firstReturnDrop?.id || '');
    const occurrences = trip.occurrences?.length
      ? trip.occurrences
      : [{ id: trip.id, startTime: trip.startTime, seatsRemaining: trip.seatsRemaining, status: 'SCHEDULED' }];
    const firstDate = occurrences
      .filter((occurrence) => String(occurrence.status || 'SCHEDULED').toUpperCase() === 'SCHEDULED' && Number(occurrence.seatsRemaining || 0) > 0)
      .sort((left, right) => new Date(left.startTime).getTime() - new Date(right.startTime).getTime())[0];
    setSelectedServiceDateKeys(firstDate ? [new Date(firstDate.startTime).toISOString().slice(0, 10)] : []);
    setReservationModalOpen(true);
  }

  async function focusSharedTrip(sharedTripId: string) {
    const matchingTrip = trips.find(
      (trip) => trip.id === sharedTripId || (trip.occurrences || []).some((occurrence) => occurrence.id === sharedTripId)
    );
    if (!matchingTrip) {
      setNetworkNotice('تعذر العثور على الرحلة المشتركة ضمن الرحلات المتاحة حاليًا.');
      return;
    }
    setActiveTab('reserve');
    openTripReservation(matchingTrip);
    await clearPendingSharedTrip();
  }

  async function restorePassengerJourney() {
    const [pendingTripId, draft] = await Promise.all([
      loadPendingSharedTrip(),
      loadBookingDraft(),
    ]);

    if (pendingTripId) {
      await focusSharedTrip(pendingTripId);
      setBookingDraftRestored(true);
      return;
    }

    if (draft) {
      const matchingTrip = trips.find(
        (trip) => trip.id === draft.tripId || (trip.occurrences || []).some((occurrence) => occurrence.id === draft.tripId)
      );
      if (matchingTrip) {
        openTripReservation(matchingTrip);
        setPickupPointId(draft.pickupPointId);
        setDropoffPointId(draft.dropoffPointId);
        setPaymentMethod(draft.paymentMethod);
        setWalletSenderNumber(draft.walletSenderNumber);
        setSelectedSeat(draft.selectedSeat);
        setSelectedTierId(draft.selectedTierId);
        setSelectedServiceDateKeys(draft.selectedServiceDateKeys);
        setReserveRoundTrip(draft.reserveRoundTrip);
        setReturnPickupPointId(draft.returnPickupPointId);
        setReturnDropoffPointId(draft.returnDropoffPointId);
        setBookingClientRequestId(draft.clientRequestId || createClientRequestId());
        setBookingRecoveryNote('استعدنا تفاصيل الحجز غير المكتمل. راجع الرحلة والمحطات والتواريخ قبل التأكيد.');
      }
    }
    setBookingDraftRestored(true);
  }

  async function handleSearch() {
    if (!token) return;
    setSearching(true);
    try {
      const nextTrips = await loadTrips(token, query, {
        from: fromQuery,
        to: toQuery,
        date: serviceDateQuery,
        coords: passengerCoords,
      });
      setTrips(nextTrips);
      setSelectedTripId((current) => (current && nextTrips.some((trip) => trip.id === current) ? current : nextTrips[0]?.id || ''));
    } catch (error) {
      Alert.alert('فشل البحث', error instanceof Error ? error.message : 'تعذر تحميل الرحلات الآن');
    } finally {
      setSearching(false);
    }
  }

  async function handleNearestTripSearch() {
    if (!token) return;
    setSearching(true);
    try {
      const permission = await Location.requestForegroundPermissionsAsync();
      if (permission.status !== 'granted') {
        setLocationSearchNote('لم يتم السماح بالوصول للموقع. يمكنك الاختيار من القوائم يدويًا.');
        return;
      }
      setLocationSearchNote('جاري تحديد موقعك وترتيب أقرب الرحلات...');
      const location = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
      const coords = { lat: location.coords.latitude, lng: location.coords.longitude };
      setPassengerCoords(coords);
      const nextTrips = await loadTrips(token, query, {
        from: fromQuery,
        to: toQuery,
        date: serviceDateQuery,
        coords,
      });
      setTrips(nextTrips);
      setSelectedTripId((current) => (current && nextTrips.some((trip) => trip.id === current) ? current : nextTrips[0]?.id || ''));
      setLocationSearchNote('تم ترتيب الرحلات حسب أقرب نقطة صعود لموقعك الحالي.');
    } catch {
      setLocationSearchNote('تعذر تحديد الموقع الآن. جرّب البحث اليدوي من القوائم.');
    } finally {
      setSearching(false);
    }
  }

  function toggleServiceDate(dateKey: string) {
    setSelectedServiceDateKeys((current) => {
      const next = current.includes(dateKey)
        ? current.filter((item) => item !== dateKey)
        : [...current, dateKey];
      return next.sort();
    });
  }

  function applyRecommendedTier(tier: ReservationTier) {
    const neededCount = Number(tier.durationDays || 0);
    const optionKeys = serviceDateOptions.map((item) => item.dateKey);
    const current = new Set(selectedServiceDateKeys);
    for (const key of optionKeys) {
      if (current.size >= neededCount) break;
      current.add(key);
    }
    setSelectedServiceDateKeys([...current].sort());
    setSelectedTierId(tier.id);
  }

  async function handleRefresh() {
    if (!token) return;
    setRefreshing(true);
    try {
      await refreshAll(token, query);
      await loadNotifications(token, false);
    } catch (error) {
      Alert.alert('فشل التحديث', error instanceof Error ? error.message : 'تعذر تحديث البيانات الآن');
    } finally {
      setRefreshing(false);
    }
  }

  async function handleLogin() {
    if (!identifier.trim() || !password.trim()) {
      Alert.alert('بيانات ناقصة', 'أدخل البريد أو الهاتف وكلمة المرور.');
      return;
    }
    setLoading(true);
    try {
      const loginPayload = await apiRequest<unknown>(
        '/api/mobile/auth/login',
        '',
        {
          method: 'POST',
          body: JSON.stringify({
            identifier: identifier.trim(),
            password,
            platform: 'mobile-passenger',
            deviceName: 'سوفت كار شاتل - الراكب',
          }),
        }
      );
      const session = parseMobileLoginSession(loginPayload);

      if (session.user.role !== 'USER') {
        Alert.alert('نوع الحساب غير صحيح', 'استخدم حساب راكب لهذا التطبيق.');
        return;
      }

      await persistToken(session.token);
      setToken(session.token);
      setActiveTab('reserve');
      setPassword('');
      await refreshAll(session.token, query);
    } catch (error) {
      Alert.alert('فشل تسجيل الدخول', error instanceof Error ? error.message : 'تعذر تسجيل الدخول الآن');
    } finally {
      setLoading(false);
    }
  }

  function normalizeRegisterPhone(value: string) {
    const digits = value.replace(/\D+/g, '');
    if (/^20(1\d{9})$/.test(digits)) return `0${digits.slice(2)}`;
    if (/^1\d{9}$/.test(digits)) return `0${digits}`;
    return digits;
  }

  function openForgotPassword() {
    setAuthMode('forgot');
    setResetPhone(normalizeRegisterPhone(identifier || resetPhone));
    setResetOtp('');
    setResetOtpMessage('');
    setResetOtpTone('info');
  }

  async function requestResetOtp() {
    const normalizedPhone = normalizeRegisterPhone(resetPhone);
    if (!/^01\d{9}$/.test(normalizedPhone)) {
      setResetOtpTone('error');
      setResetOtpMessage('\u0623\u062f\u062e\u0644 \u0631\u0642\u0645 \u0645\u0648\u0628\u0627\u064a\u0644 \u0645\u0635\u0631\u064a \u0635\u062d\u064a\u062d \u064a\u0628\u062f\u0623 \u0628\u0640 01.');
      return;
    }

    setResetOtpLoading(true);
    setResetOtpTone('info');
    setResetOtpMessage('\u062c\u0627\u0631\u064a \u0625\u0631\u0633\u0627\u0644 \u0643\u0648\u062f \u0627\u0644\u0627\u0633\u062a\u0639\u0627\u062f\u0629...');
    try {
      const { response, payload } = await apiJson('/api/auth/forgot-password', {
        method: 'POST',
        body: JSON.stringify({ phone: normalizedPhone }),
      });
      const retryAfterSeconds = Number(payload?.retryAfterSeconds || 60);
      if (!response.ok) {
        if (response.status === 429 && retryAfterSeconds > 0) {
          setResetOtpSent(true);
          setResetResendCooldownTotal(Math.max(1, retryAfterSeconds));
          setResetResendSeconds(retryAfterSeconds);
          setResetOtpTone('info');
          setResetOtpMessage(apiMessage(payload, `\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0643\u0648\u062f \u0628\u0627\u0644\u0641\u0639\u0644. \u064a\u0645\u0643\u0646\u0643 \u0637\u0644\u0628 \u0643\u0648\u062f \u062c\u062f\u064a\u062f \u0628\u0639\u062f ${retryAfterSeconds} \u062b\u0627\u0646\u064a\u0629.`));
          return;
        }
        setResetOtpTone('error');
        setResetOtpMessage(apiMessage(payload, '\u062a\u0639\u0630\u0631 \u0625\u0631\u0633\u0627\u0644 \u0643\u0648\u062f \u0627\u0644\u0627\u0633\u062a\u0639\u0627\u062f\u0629 \u0627\u0644\u0622\u0646.'));
        return;
      }

      setResetPhone(normalizedPhone);
      setResetOtp('');
      setResetOtpSent(true);
      setResetResendCooldownTotal(Math.max(1, retryAfterSeconds));
      setResetResendSeconds(retryAfterSeconds);
      setResetOtpTone('success');
      setResetOtpMessage(apiMessage(payload, '\u062a\u0645 \u0625\u0631\u0633\u0627\u0644 \u0643\u0648\u062f \u0645\u0646 6 \u0623\u0631\u0642\u0627\u0645. \u0623\u062f\u062e\u0644 \u0627\u0644\u0643\u0648\u062f \u0648\u0643\u0644\u0645\u0629 \u0645\u0631\u0648\u0631 \u062c\u062f\u064a\u062f\u0629.'));
    } catch (error) {
      setResetOtpTone('error');
      setResetOtpMessage(error instanceof Error ? error.message : '\u062a\u0639\u0630\u0631 \u0625\u0631\u0633\u0627\u0644 \u0643\u0648\u062f \u0627\u0644\u0627\u0633\u062a\u0639\u0627\u062f\u0629 \u0627\u0644\u0622\u0646.');
    } finally {
      setResetOtpLoading(false);
    }
  }

  async function completeResetPassword() {
    const normalizedPhone = normalizeRegisterPhone(resetPhone);
    const normalizedOtp = resetOtp.replace(/\D+/g, '').slice(0, 6);
    if (!resetOtpSent) {
      Alert.alert('\u0643\u0648\u062f \u0645\u0637\u0644\u0648\u0628', '\u0627\u0637\u0644\u0628 \u0643\u0648\u062f \u0627\u0644\u0627\u0633\u062a\u0639\u0627\u062f\u0629 \u0623\u0648\u0644\u0627.');
      return;
    }
    if (!/^\d{6}$/.test(normalizedOtp)) {
      Alert.alert('\u0643\u0648\u062f \u063a\u064a\u0631 \u0645\u0643\u062a\u0645\u0644', '\u0623\u062f\u062e\u0644 \u0643\u0648\u062f \u0627\u0644\u062a\u062d\u0642\u0642 \u0627\u0644\u0645\u0643\u0648\u0646 \u0645\u0646 6 \u0623\u0631\u0642\u0627\u0645.');
      return;
    }
    if (resetPassword.length < 8) {
      Alert.alert('\u0643\u0644\u0645\u0629 \u0645\u0631\u0648\u0631 \u0636\u0639\u064a\u0641\u0629', '\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631 \u064a\u062c\u0628 \u0623\u0646 \u062a\u0643\u0648\u0646 8 \u0623\u062d\u0631\u0641 \u0639\u0644\u0649 \u0627\u0644\u0623\u0642\u0644.');
      return;
    }
    if (resetPassword !== resetPasswordConfirm) {
      Alert.alert('\u0639\u062f\u0645 \u062a\u0637\u0627\u0628\u0642', '\u062a\u0623\u0643\u064a\u062f \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631 \u063a\u064a\u0631 \u0645\u0637\u0627\u0628\u0642.');
      return;
    }

    setResetOtpLoading(true);
    setResetOtpTone('info');
    setResetOtpMessage('\u062c\u0627\u0631\u064a \u062a\u063a\u064a\u064a\u0631 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631...');
    try {
      const { response, payload } = await apiJson('/api/auth/reset-password', {
        method: 'POST',
        body: JSON.stringify({ phone: normalizedPhone, code: normalizedOtp, password: resetPassword }),
      });
      if (!response.ok) {
        setResetOtpTone('error');
        setResetOtpMessage(apiMessage(payload, '\u062a\u0639\u0630\u0631 \u062a\u063a\u064a\u064a\u0631 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631.'));
        return;
      }
      setIdentifier(normalizedPhone);
      setPassword('');
      setResetOtp('');
      setResetPassword('');
      setResetPasswordConfirm('');
      setResetOtpSent(false);
      setResetResendSeconds(0);
      setAuthMode('login');
      Alert.alert('\u062a\u0645 \u0627\u0644\u062a\u063a\u064a\u064a\u0631', apiMessage(payload, '\u062a\u0645 \u062a\u063a\u064a\u064a\u0631 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631. \u0633\u062c\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0628\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631 \u0627\u0644\u062c\u062f\u064a\u062f\u0629.'));
    } finally {
      setResetOtpLoading(false);
    }
  }

  function buildRegisterPayload() {
    return {
      name: registerName.trim(),
      email: registerEmail.trim().toLowerCase(),
      phone: normalizeRegisterPhone(registerPhone),
      password: registerPassword,
      image: '',
      acceptTerms: registerPoliciesAccepted,
    };
  }

  function resetRegisterOtpState() {
    setRegisterStep('form');
    setRegisterOtp('');
    setRegisterOtpSent(false);
    setRegisterOtpMessage('');
    setRegisterOtpTone('info');
    setRegisterResendSeconds(0);
    setRegisterResendCooldownTotal(60);
  }

  function clearRegisterForm() {
    setRegisterName('');
    setRegisterEmail('');
    setRegisterPhone('');
    setRegisterPassword('');
    setRegisterPasswordConfirm('');
    setRegisterPoliciesAccepted(false);
    resetRegisterOtpState();
  }

  async function openPassengerAccount(loginIdentifier: string, loginPassword: string) {
    const loginPayload = await apiRequest<unknown>(
      '/api/mobile/auth/login',
      '',
      {
        method: 'POST',
        body: JSON.stringify({
          identifier: loginIdentifier,
          password: loginPassword,
          platform: 'mobile-passenger',
          deviceName: 'سوفت كار شاتل - الراكب',
        }),
      }
    );
    const session = parseMobileLoginSession(loginPayload);

    if (session.user.role !== 'USER') {
      Alert.alert('تم إنشاء الحساب', 'سجل الدخول من تبويب الدخول للمتابعة.');
      setAuthMode('login');
      return false;
    }

    await persistToken(session.token);
    setToken(session.token);
    setActiveTab('reserve');
    setIdentifier(loginIdentifier);
    setPassword('');
    clearRegisterForm();
    await refreshAll(session.token, query);
    return true;
  }

  async function requestRegisterOtp(targetPhone: string) {
    setRegisterOtpLoading(true);
    setRegisterOtpTone('info');
    setRegisterOtpMessage('جاري إرسال كود التحقق إلى رقم الهاتف...');
    try {
      const { response, payload } = await apiJson('/api/auth/request-otp', {
        method: 'POST',
        body: JSON.stringify({ channel: 'phone', target: targetPhone }),
      });

      const retryAfterSeconds = Number(payload?.retryAfterSeconds || 60);
      if (!response.ok) {
        if (response.status === 429 && retryAfterSeconds > 0) {
          setRegisterOtpSent(true);
          setRegisterResendCooldownTotal(Math.max(1, retryAfterSeconds));
          setRegisterResendSeconds(retryAfterSeconds);
          setRegisterOtpTone('info');
          setRegisterOtpMessage(apiMessage(payload, `تم إرسال كود بالفعل. يمكنك طلب كود جديد بعد ${retryAfterSeconds} ثانية.`));
          return true;
        }
        setRegisterOtpTone('error');
        setRegisterOtpMessage(apiMessage(payload, 'تعذر إرسال كود التحقق الآن.'));
        return false;
      }

      setRegisterOtpSent(true);
      setRegisterResendCooldownTotal(Math.max(1, retryAfterSeconds));
      setRegisterResendSeconds(retryAfterSeconds);
      setRegisterOtpTone('success');
      setRegisterOtpMessage(apiMessage(payload, 'تم إرسال كود التحقق. ادخل الكود المكون من 6 أرقام لإتمام إنشاء الحساب.'));
      return true;
    } catch (error) {
      setRegisterOtpTone('error');
      setRegisterOtpMessage(
        error instanceof Error && error.message
          ? error.message
          : '\u062a\u0639\u0630\u0631 \u0625\u0631\u0633\u0627\u0644 \u0643\u0648\u062f \u0627\u0644\u062a\u062d\u0642\u0642 \u0627\u0644\u0622\u0646. \u062a\u0623\u0643\u062f \u0645\u0646 \u0627\u0644\u0627\u062a\u0635\u0627\u0644 \u062b\u0645 \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.'
      );
      return false;
    } finally {
      setRegisterOtpLoading(false);
    }
  }

  async function createAccountAfterOtp() {
    const payload = buildRegisterPayload();

    setLoading(true);
    try {
      const registrationPayload = await apiRequest<unknown>('/api/auth/register', '', {
        method: 'POST',
        body: JSON.stringify({
          ...payload,
          createMobileSession: true,
          platform: 'mobile-passenger',
          deviceName: 'سوفت كار شاتل - الراكب',
        }),
      });
      const session = parseMobileLoginSession(registrationPayload);
      if (session.user.role !== 'USER') {
        throw new Error('تم إنشاء الحساب لكن نوع الحساب غير مخصص للركاب.');
      }
      await persistToken(session.token);
      setToken(session.token);
      setIdentifier(payload.phone);
      setPassword('');
      setActiveTab('reserve');
      clearRegisterForm();
      await refreshAll(session.token, query);
      Alert.alert('مرحباً', 'تم تأكيد الهاتف وإنشاء الحساب وتسجيل الدخول بنجاح.');
    } catch (error) {
      Alert.alert('فشل إنشاء الحساب', error instanceof Error ? error.message : 'تعذر إنشاء الحساب الآن');
    } finally {
      setLoading(false);
    }
  }

  async function handleRegister() {
    const normalizedName = registerName.trim();
    const normalizedPhone = normalizeRegisterPhone(registerPhone);

    if (!normalizedName || normalizedName.length < 2) {
      Alert.alert('الاسم غير مكتمل', 'أدخل الاسم الكامل.');
      return;
    }
    if (!/^01\d{9}$/.test(normalizedPhone)) {
      Alert.alert('رقم الهاتف غير صحيح', 'أدخل رقم موبايل مصري صحيح يبدأ بـ 01 ويتكون من 11 رقمًا.');
      return;
    }
    if (registerPassword.length < 8) {
      Alert.alert('كلمة المرور ضعيفة', 'يجب أن تكون كلمة المرور 8 أحرف على الأقل.');
      return;
    }
    if (registerPassword !== registerPasswordConfirm) {
      Alert.alert('عدم تطابق كلمة المرور', 'تأكيد كلمة المرور غير مطابق.');
      return;
    }

    if (!registerPoliciesAccepted) {
      Alert.alert('الموافقة مطلوبة', 'وافق على الشروط والأحكام وسياسة الخصوصية قبل إنشاء الحساب.');
      return;
    }

    setLoading(true);
    try {
      const { response, payload } = await apiJson('/api/auth/register', {
        method: 'POST',
        body: JSON.stringify({ ...buildRegisterPayload(), preflight: true }),
      });

      if (!response.ok) {
        Alert.alert('فشل إنشاء الحساب', apiMessage(payload, 'تعذر مراجعة بيانات الحساب. تأكد من البيانات أو تواصل مع خدمة العملاء.'));
        return;
      }

      setAuthMode('register');
      setRegisterOtp('');
      setRegisterOtpSent(false);
      setRegisterOtpTone('info');
      setRegisterOtpMessage('\u062c\u0627\u0631\u064a \u0625\u0631\u0633\u0627\u0644 \u0643\u0648\u062f \u0627\u0644\u062a\u062d\u0642\u0642 \u0625\u0644\u0649 \u0631\u0642\u0645 \u0627\u0644\u0647\u0627\u062a\u0641...');
      setRegisterStep('otp');
      setLoading(false);
      await requestRegisterOtp(normalizedPhone);
    } catch (error) {
      Alert.alert('فشل إنشاء الحساب', error instanceof Error ? error.message : 'تعذر إنشاء الحساب الآن');
    } finally {
      setLoading(false);
    }
  }

  async function handleConfirmRegisterOtp() {
    const normalizedPhone = normalizeRegisterPhone(registerPhone);
    const normalizedOtp = registerOtp.replace(/\D+/g, '').slice(0, 6);

    if (!registerOtpSent) {
      Alert.alert('كود التحقق مطلوب', 'اطلب كود التحقق أولاً.');
      return;
    }
    if (!/^01\d{9}$/.test(normalizedPhone)) {
      Alert.alert('رقم الهاتف غير صحيح', 'ارجع وعدّل رقم الهاتف قبل تأكيد الكود.');
      return;
    }
    if (!/^\d{6}$/.test(normalizedOtp)) {
      Alert.alert('كود غير مكتمل', 'أدخل كود التحقق المكون من 6 أرقام.');
      return;
    }

    setRegisterOtpLoading(true);
    setRegisterOtpTone('info');
    setRegisterOtpMessage('جاري تأكيد كود التحقق...');
    try {
      const { response, payload } = await apiJson('/api/auth/verify-otp', {
        method: 'POST',
        body: JSON.stringify({ target: normalizedPhone, code: normalizedOtp }),
      });
      if (!response.ok) {
        setRegisterOtpTone('error');
        setRegisterOtpMessage(apiMessage(payload, 'كود التحقق غير صحيح أو انتهت صلاحيته.'));
        return;
      }

      setRegisterOtpTone('success');
      setRegisterOtpMessage(apiMessage(payload, 'تم تأكيد رقم الهاتف. جاري إنشاء الحساب...'));
      await createAccountAfterOtp();
    } finally {
      setRegisterOtpLoading(false);
    }
  }

  async function handleResendRegisterOtp() {
    if (registerResendSeconds > 0 || registerOtpLoading || loading) return;
    const normalizedPhone = normalizeRegisterPhone(registerPhone);
    setRegisterOtp('');
    await requestRegisterOtp(normalizedPhone);
  }

  async function handleReserve() {
    if (!token || !selectedTrip || !pickupPointId || !dropoffPointId || !selectedSeat) {
      Alert.alert('بيانات ناقصة', 'اختر نقطة الصعود والنزول وطريقة الدفع ومقعداً واحداً.');
      return;
    }
    if (pricingLoading) {
      Alert.alert('جارٍ تجهيز السعر', 'انتظر لحظة حتى يكتمل حساب سعر هذا المسار قبل تأكيد الحجز.');
      return;
    }
    if (pricingError) {
      Alert.alert('السعر غير متاح', pricingError);
      return;
    }
    if (paymentMethod === 'WALLET') {
      const walletAvailableBalance = Number(walletData?.account?.balance ?? walletData?.wallet?.balance ?? 0);
      const expectedWalletCharge =
        Number(pricingPreview?.finalPrice ?? 0) ||
        Number(selectedTier?.packagePrice ?? 0) ||
        Number(selectedTrip.basePrice ?? 0);
      if (walletAvailableBalance < expectedWalletCharge) {
        Alert.alert(
          'رصيد المحفظة غير كاف',
          `رصيدك المتاح ${formatMoney(walletAvailableBalance)} والمطلوب تقريبا ${formatMoney(expectedWalletCharge)}. اشحن المحفظة أولا ثم أكمل الحجز.`
        );
        setActiveTab('wallet');
        setReservationModalOpen(false);
        return;
      }
    }
    if (reserveRoundTrip && (!roundTripBookingAvailable || !selectedReturnTrip || !returnPickupPointId || !returnDropoffPointId)) {
      Alert.alert('بيانات العودة ناقصة', 'اختر نقطة الصعود ونقطة النزول لرحلة العودة قبل تأكيد حجز الذهاب والعودة.');
      return;
    }

    if (selectedTier && selectedTier.minimumSeats > 1) {
      Alert.alert('الباقة تحتاج مقاعد أكثر', `هذه الباقة تتطلب ${selectedTier.minimumSeats} مقاعد على الأقل.`);
      return;
    }
    if (repeatedTripBooking && selectedServiceDateKeys.length === 0) {
      Alert.alert('اختر مواعيد الرحلة', 'اختر موعدًا واحدًا على الأقل قبل تأكيد الرحلة المتكررة.');
      return;
    }
    if (voucherCode.trim() && !voucherQuote) {
      Alert.alert('تحقق من القسيمة', 'اضغط تطبيق القسيمة أولاً للتأكد من صلاحيتها والسعر النهائي.');
      return;
    }

    setLoading(true);
    try {
      let reservationResult: any = null;
      if (selectedTier || repeatedTripBooking) {
        const dateKeys = selectedServiceDateKeys.length
          ? selectedServiceDateKeys
          : [new Date(selectedTrip.startTime).toISOString().slice(0, 10)];
        const startDate = dateKeys[0];
        const endDate = dateKeys[dateKeys.length - 1];
        reservationResult = await apiRequest('/api/mobile/recurring-reservations', token, {
          method: 'POST',
          body: JSON.stringify({
            clientRequestId: bookingClientRequestId,
            tripId: selectedTrip.id,
            pickupPointId,
            dropoffPointId,
            tierId: selectedTier?.id || '',
            voucherCode: voucherQuote?.voucher.code || '',
            seats: 1,
            seatNumbers: selectedSeat,
            paymentMethod,
            startDate,
            endDate,
            weekdays: [...new Set(dateKeys.map((dateKey) => new Date(`${dateKey}T00:00:00`).getDay()))],
            selectedServiceDates: dateKeys,
          }),
        });
      } else {
        reservationResult = await apiRequest('/api/mobile/reservations', token, {
          method: 'POST',
          body: JSON.stringify({
            clientRequestId: bookingClientRequestId,
            tripId: selectedTrip.id,
            pickupPointId,
            dropoffPointId,
            seats: 1,
            seatNumbers: selectedSeat,
            paymentMethod,
            voucherCode: voucherQuote?.voucher.code || '',
            roundTrip: reserveRoundTrip,
            roundTripReturnTripId: reserveRoundTrip ? selectedReturnTrip?.id : '',
            returnPickupPointId: reserveRoundTrip ? returnPickupPointId : '',
            returnDropoffPointId: reserveRoundTrip ? returnDropoffPointId : '',
          }),
        });
      }

      await refreshAll(token, query);
      await clearBookingDraft();
      setBookingClientRequestId(createClientRequestId());
      setReservationModalOpen(false);
      Alert.alert('تم تأكيد الحجز', `تم حجز المقعد ${selectedSeat} بنجاح.`);
    } catch (error) {
      Alert.alert('فشل الحجز', error instanceof Error ? error.message : 'تعذر حجز الرحلة الآن');
    } finally {
      setLoading(false);
    }
  }

  async function validateVoucherCode() {
    if (!token || !selectedTrip || !pickupPointId || !dropoffPointId) {
      Alert.alert('اختر الرحلة أولاً', 'اختر نقطة الصعود والنزول قبل تطبيق القسيمة.');
      return;
    }
    if (!voucherCode.trim()) {
      setVoucherQuote(null);
      setVoucherError('أدخل كود القسيمة.');
      return;
    }
    setVoucherLoading(true);
    setVoucherError('');
    try {
      const quote = await apiRequest<VoucherQuote>('/api/mobile/vouchers/validate', token, {
        method: 'POST',
        body: JSON.stringify({
          code: voucherCode.trim(),
          tripId: selectedTrip.id,
          pickupPointId,
          dropoffPointId,
          seats: 1,
          selectedDateCount: repeatedTripBooking ? selectedServiceDateKeys.length : 1,
          tierId: selectedTier?.id || '',
        }),
      });
      setVoucherCode(quote.voucher.code);
      setVoucherQuote(quote);
      Alert.alert('تم تطبيق القسيمة', `وفرت ${formatMoney(quote.discountAmount)}. السعر بعد الخصم والضريبة ${formatMoney(quote.finalPrice)}.`);
    } catch (error) {
      setVoucherQuote(null);
      setVoucherError(error instanceof Error ? error.message : 'تعذر تطبيق القسيمة.');
    } finally {
      setVoucherLoading(false);
    }
  }

  async function handleLogout() {
    if (token) {
      await unregisterCurrentPushDevice(token);
    }
    await clearStoredToken();
    await clearBookingDraft();
    setToken('');
    setActiveTab('reserve');
    setMenuOpen(false);
    setTrips([]);
    setReservations([]);
    setReservationTiers([]);
    setWalletSenderNumber('');
    setWalletRecipientNumber('');
    setWalletInstructions('');
    setMeUser(null);
    setNotifications([]);
    setUnreadNotifications(0);
    setNotificationPanelOpen(false);
    setNotificationFilter('all');
    setNotificationSearch('');
    setFocusedNotificationId('');
    setNotificationNextCursor(null);
    setNotificationPermissionStatus('checking');
    setTripChatByTripId({});
    setTripChatParticipantsByTripId({});
    setChatDraft('');
    setChatLoadingTripId('');
    setChatSendingTripId('');
    setReservationModalOpen(false);
    setSelectedTripId('');
    setSelectedTierId('');
    setSelectedServiceDateKeys([]);
    setBookingClientRequestId(createClientRequestId());
    setBookingDraftRestored(false);
    handledNotificationResponseId.current = '';
  }

  function openPassengerMenuTab(nextTab: PassengerTab) {
    setActiveTab(nextTab);
    setMenuOpen(false);
  }

  function renderDriverAssistCard(driver: DriverContact | null | undefined, emptyLabel = 'سيتم تعيين السائق قريبًا') {
    return (
      <PassengerDriverAssistCard
        driver={driver}
        emptyLabel={emptyLabel}
        onCallDriver={(phone) => {
          void openDialer(phone);
        }}
      />
    );
  }

  function renderRefundControls(reservationsForRefund: Reservation[], scope: 'single' | 'trip-group') {
    const activeStatuses = new Set(['PENDING_REVIEW', 'APPROVED', 'PROCESSED']);
    const paidStatuses = new Set(['AUTHORIZED', 'PAID', 'PAID_CASH_COLLECTED', 'CASH_COLLECTED']);
    const latestRefund = reservationsForRefund
      .flatMap((reservation) => reservation.refunds || [])
      .sort((left, right) => new Date(right.createdAt).getTime() - new Date(left.createdAt).getTime())[0];
    const activeRefund = reservationsForRefund
      .flatMap((reservation) => reservation.refunds || [])
      .find((refund) => activeStatuses.has(String(refund.status || '').toUpperCase()));
    const refundable = reservationsForRefund.some((reservation) =>
      paidStatuses.has(String(reservation.paymentStatus || '').toUpperCase())
    );

    if (activeRefund || latestRefund) {
      const refund = activeRefund || latestRefund;
      return (
        <View style={styles.refundStatusCard}>
          <Text style={styles.refundStatusTitle}>حالة الاسترداد: {formatRefundStatusLabel(refund?.status || '')}</Text>
          <Text style={styles.refundStatusText}>الرقم المرجعي: {refund?.refundCode || '-'}</Text>
          <Text style={styles.refundStatusText}>القيمة: {formatMoney(refund?.amount)}</Text>
          <Text style={styles.refundStatusText}>السبب: {refund?.reason || '-'}</Text>
        </View>
      );
    }

    if (!refundable) return null;
    return (
      <Pressable
        style={styles.refundRequestButton}
        onPress={(event) => {
          event.stopPropagation();
          openRefundRequest(reservationsForRefund[0].id, scope);
        }}
      >
        <Text style={styles.refundRequestButtonText}>
          {scope === 'trip-group' ? 'طلب استرداد كل مواعيد الرحلة' : 'طلب استرداد هذا اليوم'}
        </Text>
      </Pressable>
    );
  }

  function renderReservationQuickActions(reservation: Reservation) {
    return (
      <View style={styles.reservationQuickActions}>
        <Pressable style={styles.secondaryActionButton} onPress={() => repeatReservation(reservation)}>
          <Text style={styles.secondaryActionButtonText}>احجز نفس المسار</Text>
        </Pressable>
        <Pressable
          style={styles.secondaryActionButton}
          onPress={() => {
            void shareReservationTrip(reservation);
          }}
        >
          <Text style={styles.secondaryActionButtonText}>مشاركة الرحلة</Text>
        </Pressable>
      </View>
    );
  }

  function renderReviewControl(reservation: Reservation) {
    if (String(reservation.status || '').toUpperCase() !== 'COMPLETED') return null;
    return (
      <Pressable
        style={styles.reviewActionButton}
        onPress={(event) => {
          event.stopPropagation();
          openReservationReview(reservation);
        }}
      >
        <Text style={styles.reviewActionButtonText}>
          {reservation.review ? `تعديل التقييم (${reservation.review.rating}/٥)` : 'قيّم هذه الرحلة'}
        </Text>
      </Pressable>
    );
  }

  if (booting) {
    return (
      <SafeAreaView style={styles.booting}>
        <StatusBar style="light" />
        <ActivityIndicator size="large" color="#D32F2F" />
        <Text style={styles.bootingText}>جارٍ فتح تطبيق الراكب...</Text>
      </SafeAreaView>
    );
  }

  if (!token) {
    const canConfirmRegisterOtp = registerOtpSent && /^\d{6}$/.test(registerOtp) && !registerOtpLoading && !loading;
    const registerResendProgress = registerResendSeconds > 0
      ? Math.round(((registerResendCooldownTotal - registerResendSeconds) / Math.max(1, registerResendCooldownTotal)) * 100)
      : 100;
    const resetResendProgress = resetResendSeconds > 0
      ? Math.round(((resetResendCooldownTotal - resetResendSeconds) / Math.max(1, resetResendCooldownTotal)) * 100)
      : 100;
    const canConfirmReset = resetOtpSent && /^\d{6}$/.test(resetOtp) && resetPassword.length >= 8 && resetPassword === resetPasswordConfirm && !resetOtpLoading;

    return (
      <SafeAreaView style={styles.loginContainer}>
        <StatusBar style="light" />
        <View style={styles.loginHero}>
          <Text style={styles.loginEyebrow}>سوفت كار شاتل</Text>
          <Text style={styles.loginTitle}>دخول الراكب</Text>
          <Text style={styles.loginSubtitle}>احجز رحلاتك، تابع التذكرة، وأدر رحلات الشاتل من تطبيق عربي واضح وسريع.</Text>
          <View style={styles.loginFeatureRow}>
            <View style={styles.loginFeaturePill}>
              <Text style={styles.loginFeaturePillText}>حجز سريع</Text>
            </View>
            <View style={styles.loginFeaturePill}>
              <Text style={styles.loginFeaturePillText}>تذكرة مباشرة</Text>
            </View>
            <View style={styles.loginFeaturePill}>
              <Text style={styles.loginFeaturePillText}>نفس حساب الويب</Text>
            </View>
          </View>
        </View>

        <View style={styles.loginCard}>
          <View style={styles.authModeSwitch}>
            <Pressable
              style={[styles.authModeButton, authMode === 'login' && styles.authModeButtonActive]}
              onPress={() => {
                setAuthMode('login');
                resetRegisterOtpState();
              }}
            >
              <Text style={[styles.authModeButtonText, authMode === 'login' && styles.authModeButtonTextActive]}>
                تسجيل الدخول
              </Text>
            </Pressable>
            <Pressable
              style={[styles.authModeButton, authMode === 'register' && styles.authModeButtonActive]}
              onPress={() => setAuthMode('register')}
            >
              <Text style={[styles.authModeButtonText, authMode === 'register' && styles.authModeButtonTextActive]}>
                إنشاء حساب
              </Text>
            </Pressable>
          </View>

          {authMode === 'login' ? (
            <>
              <TextInput
                value={identifier}
                onChangeText={setIdentifier}
                placeholder="البريد الإلكتروني أو الهاتف"
                placeholderTextColor="#93a1b6"
                autoCapitalize="none"
                style={styles.loginInput}
              />
              <View style={styles.passwordInputWrap}>
                <TextInput
                  value={password}
                  onChangeText={setPassword}
                  placeholder="كلمة المرور"
                  placeholderTextColor="#93a1b6"
                  secureTextEntry={!passwordVisible}
                  autoCapitalize="none"
                  textContentType="password"
                  style={[styles.loginInput, styles.passwordTextInput]}
                />
                <Pressable
                  style={styles.passwordToggle}
                  onPress={() => setPasswordVisible((current) => !current)}
                >
                  <Text style={styles.passwordToggleText}>{passwordVisible ? 'إخفاء' : 'إظهار'}</Text>
                </Pressable>
              </View>
              <Pressable style={styles.loginButton} onPress={handleLogin} disabled={loading}>
                <Text style={styles.loginButtonText}>{loading ? 'جارٍ تسجيل الدخول...' : 'تسجيل الدخول'}</Text>
              </Pressable>
              <Pressable style={styles.otpEditButton} onPress={openForgotPassword}>
                <Text style={styles.otpEditButtonText}>{'\u0646\u0633\u064a\u062a \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631\u061f'}</Text>
              </Pressable>
            </>
          ) : authMode === 'forgot' ? (
            <>
              <View style={styles.otpHeader}>
                <View style={styles.otpIconCircle}>
                  <Text style={styles.otpIconText}>6</Text>
                </View>
                <Text style={styles.otpTitle}>{'\u0627\u0633\u062a\u0639\u0627\u062f\u0629 \u0627\u0644\u062d\u0633\u0627\u0628'}</Text>
                <Text style={styles.otpSubtitle}>
                  {'\u0623\u062f\u062e\u0644 \u0631\u0642\u0645 \u0647\u0627\u062a\u0641\u0643 \u062b\u0645 \u0627\u0643\u062a\u0628 \u0643\u0648\u062f \u0627\u0644\u062a\u062d\u0642\u0642 \u0648\u0643\u0644\u0645\u0629 \u0645\u0631\u0648\u0631 \u062c\u062f\u064a\u062f\u0629.'}
                </Text>
              </View>

              <TextInput
                value={resetPhone}
                onChangeText={(value) => {
                  setResetPhone(normalizeRegisterPhone(value));
                  setResetOtpSent(false);
                  setResetOtp('');
                  setResetResendSeconds(0);
                }}
                placeholder="01XXXXXXXXX"
                placeholderTextColor="#93a1b6"
                keyboardType="phone-pad"
                style={styles.loginInput}
              />

              {resetOtpSent ? (
                <>
                  <TextInput
                    value={resetOtp}
                    onChangeText={(value) => setResetOtp(value.replace(/\D+/g, '').slice(0, 6))}
                    placeholder="••••••"
                    placeholderTextColor="#5f6b7d"
                    keyboardType="number-pad"
                    textContentType="oneTimeCode"
                    maxLength={6}
                    editable={!resetOtpLoading}
                    style={styles.otpInput}
                  />
                  <View style={styles.passwordInputWrap}>
                    <TextInput
                      value={resetPassword}
                      onChangeText={setResetPassword}
                      placeholder={"\u0643\u0644\u0645\u0629 \u0645\u0631\u0648\u0631 \u062c\u062f\u064a\u062f\u0629"}
                      placeholderTextColor="#93a1b6"
                      secureTextEntry={!resetPasswordVisible}
                      autoCapitalize="none"
                      textContentType="newPassword"
                      style={[styles.loginInput, styles.passwordTextInput]}
                    />
                    <Pressable
                      style={styles.passwordToggle}
                      onPress={() => setResetPasswordVisible((current) => !current)}
                    >
                      <Text style={styles.passwordToggleText}>{resetPasswordVisible ? 'إخفاء' : 'إظهار'}</Text>
                    </Pressable>
                  </View>
                  <View style={styles.passwordInputWrap}>
                    <TextInput
                      value={resetPasswordConfirm}
                      onChangeText={setResetPasswordConfirm}
                      placeholder={"\u062a\u0623\u0643\u064a\u062f \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631"}
                      placeholderTextColor="#93a1b6"
                      secureTextEntry={!resetPasswordConfirmVisible}
                      autoCapitalize="none"
                      textContentType="newPassword"
                      style={[styles.loginInput, styles.passwordTextInput]}
                    />
                    <Pressable
                      style={styles.passwordToggle}
                      onPress={() => setResetPasswordConfirmVisible((current) => !current)}
                    >
                      <Text style={styles.passwordToggleText}>{resetPasswordConfirmVisible ? 'إخفاء' : 'إظهار'}</Text>
                    </Pressable>
                  </View>
                  <View style={styles.otpTimerCard}>
                    <View style={styles.otpTimerHeader}>
                      <Text style={styles.otpTimerLabel}>
                        {resetResendSeconds > 0 ? '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0625\u0631\u0633\u0627\u0644 \u0645\u062a\u0627\u062d\u0629 \u0628\u0639\u062f' : '\u064a\u0645\u0643\u0646\u0643 \u0637\u0644\u0628 \u0643\u0648\u062f \u062c\u062f\u064a\u062f \u0627\u0644\u0622\u0646'}
                      </Text>
                      <Text style={styles.otpTimerValue}>
                        {resetResendSeconds > 0 ? `${resetResendSeconds} \u062b\u0627\u0646\u064a\u0629` : '\u062c\u0627\u0647\u0632'}
                      </Text>
                    </View>
                    <View style={styles.otpTimerTrack}>
                      <View style={[styles.otpTimerFill, { width: `${Math.max(0, Math.min(100, resetResendProgress))}%` }]} />
                    </View>
                  </View>
                </>
              ) : null}

              {resetOtpMessage ? (
                <View
                  style={[
                    styles.otpStatusBox,
                    resetOtpTone === 'success' && styles.otpStatusBoxSuccess,
                    resetOtpTone === 'error' && styles.otpStatusBoxError,
                  ]}
                >
                  <Text
                    style={[
                      styles.otpStatusText,
                      resetOtpTone === 'success' && styles.otpStatusTextSuccess,
                      resetOtpTone === 'error' && styles.otpStatusTextError,
                    ]}
                  >
                    {resetOtpMessage}
                  </Text>
                </View>
              ) : null}

              {!resetOtpSent ? (
                <Pressable style={styles.loginButton} onPress={requestResetOtp} disabled={resetOtpLoading}>
                  <Text style={styles.loginButtonText}>{resetOtpLoading ? '\u062c\u0627\u0631\u064a \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0643\u0648\u062f...' : '\u0625\u0631\u0633\u0627\u0644 \u0643\u0648\u062f \u0627\u0644\u0627\u0633\u062a\u0639\u0627\u062f\u0629'}</Text>
                </Pressable>
              ) : (
                <>
                  <Pressable
                    style={[styles.loginButton, !canConfirmReset && styles.loginButtonDisabled]}
                    onPress={completeResetPassword}
                    disabled={!canConfirmReset}
                  >
                    <Text style={styles.loginButtonText}>{resetOtpLoading ? '\u062c\u0627\u0631\u064a \u0627\u0644\u062a\u063a\u064a\u064a\u0631...' : '\u062a\u063a\u064a\u064a\u0631 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631'}</Text>
                  </Pressable>
                  <Pressable
                    style={[styles.otpSecondaryButton, (resetResendSeconds > 0 || resetOtpLoading) && styles.otpSecondaryButtonDisabled]}
                    onPress={requestResetOtp}
                    disabled={resetResendSeconds > 0 || resetOtpLoading}
                  >
                    <Text style={styles.otpSecondaryButtonText}>
                      {resetResendSeconds > 0 ? `\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0625\u0631\u0633\u0627\u0644 \u0628\u0639\u062f ${resetResendSeconds} \u062b\u0627\u0646\u064a\u0629` : '\u0625\u0639\u0627\u062f\u0629 \u0625\u0631\u0633\u0627\u0644 \u0627\u0644\u0643\u0648\u062f'}
                    </Text>
                  </Pressable>
                </>
              )}

              <Pressable
                style={styles.otpEditButton}
                onPress={() => {
                  setAuthMode('login');
                  setResetOtpMessage('');
                }}
              >
                <Text style={styles.otpEditButtonText}>{'\u0627\u0644\u0639\u0648\u062f\u0629 \u0644\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644'}</Text>
              </Pressable>
            </>
          ) : registerStep === 'otp' ? (
            <>
              <View style={styles.otpHeader}>
                <View style={styles.otpIconCircle}>
                  <Text style={styles.otpIconText}>•••</Text>
                </View>
                <Text style={styles.otpTitle}>تأكيد رقم الهاتف</Text>
                <Text style={styles.otpSubtitle}>
                  تم إرسال كود من 6 أرقام إلى {normalizeRegisterPhone(registerPhone)} لإتمام إنشاء الحساب.
                </Text>
              </View>

              <TextInput
                value={registerOtp}
                onChangeText={(value) => setRegisterOtp(value.replace(/\D+/g, '').slice(0, 6))}
                placeholder="••••••"
                placeholderTextColor="#5f6b7d"
                keyboardType="number-pad"
                textContentType="oneTimeCode"
                maxLength={6}
                editable={!registerOtpLoading && !loading}
                style={styles.otpInput}
              />
              <Text style={styles.otpHint}>اكتب الكود كما وصل في الرسالة. يمكنك لصق الكود كاملًا هنا.</Text>

              {registerOtpMessage ? (
                <View
                  style={[
                    styles.otpStatusBox,
                    registerOtpTone === 'success' && styles.otpStatusBoxSuccess,
                    registerOtpTone === 'error' && styles.otpStatusBoxError,
                  ]}
                >
                  <Text
                    style={[
                      styles.otpStatusText,
                      registerOtpTone === 'success' && styles.otpStatusTextSuccess,
                      registerOtpTone === 'error' && styles.otpStatusTextError,
                    ]}
                  >
                    {registerOtpMessage}
                  </Text>
                </View>
              ) : null}

              <View style={styles.otpTimerCard}>
                <View style={styles.otpTimerHeader}>
                  <Text style={styles.otpTimerLabel}>
                    {registerResendSeconds > 0 ? 'إعادة الإرسال متاحة بعد' : 'يمكنك طلب كود جديد الآن'}
                  </Text>
                  <Text style={styles.otpTimerValue}>
                    {registerResendSeconds > 0 ? `${registerResendSeconds} ثانية` : 'جاهز'}
                  </Text>
                </View>
                <View style={styles.otpTimerTrack}>
                  <View style={[styles.otpTimerFill, { width: `${Math.max(0, Math.min(100, registerResendProgress))}%` }]} />
                </View>
              </View>

              <Pressable
                style={[styles.loginButton, !canConfirmRegisterOtp && styles.loginButtonDisabled]}
                onPress={handleConfirmRegisterOtp}
                disabled={!canConfirmRegisterOtp}
              >
                <Text style={styles.loginButtonText}>
                  {loading ? 'جارٍ إنشاء الحساب...' : registerOtpLoading ? 'جارٍ التأكيد...' : 'تأكيد الكود وإنشاء الحساب'}
                </Text>
              </Pressable>

              <Pressable
                style={[styles.otpSecondaryButton, (registerResendSeconds > 0 || registerOtpLoading || loading) && styles.otpSecondaryButtonDisabled]}
                onPress={handleResendRegisterOtp}
                disabled={registerResendSeconds > 0 || registerOtpLoading || loading}
              >
                <Text style={styles.otpSecondaryButtonText}>
                  {registerResendSeconds > 0 ? `إعادة الإرسال بعد ${registerResendSeconds} ثانية` : 'إعادة إرسال الكود'}
                </Text>
              </Pressable>

              <Pressable
                style={styles.otpEditButton}
                onPress={() => {
                  setRegisterStep('form');
                  setRegisterOtp('');
                  setRegisterOtpMessage('');
                }}
                disabled={loading}
              >
                <Text style={styles.otpEditButtonText}>العودة لتعديل البيانات</Text>
              </Pressable>
            </>
          ) : (
            <>
              <TextInput
                value={registerName}
                onChangeText={setRegisterName}
                placeholder="الاسم الكامل"
                placeholderTextColor="#93a1b6"
                style={styles.loginInput}
              />
              <TextInput
                value={registerEmail}
                onChangeText={setRegisterEmail}
                placeholder="البريد الإلكتروني (اختياري عند استخدام الهاتف)"
                placeholderTextColor="#93a1b6"
                autoCapitalize="none"
                style={styles.loginInput}
              />
              <TextInput
                value={registerPhone}
                onChangeText={setRegisterPhone}
                placeholder="الهاتف (01XXXXXXXXX)"
                placeholderTextColor="#93a1b6"
                keyboardType="phone-pad"
                style={styles.loginInput}
              />
              <View style={styles.passwordInputWrap}>
                <TextInput
                  value={registerPassword}
                  onChangeText={setRegisterPassword}
                  placeholder="كلمة المرور (8 أحرف على الأقل)"
                  placeholderTextColor="#93a1b6"
                  secureTextEntry={!registerPasswordVisible}
                  autoCapitalize="none"
                  textContentType="newPassword"
                  style={[styles.loginInput, styles.passwordTextInput]}
                />
                <Pressable
                  style={styles.passwordToggle}
                  onPress={() => setRegisterPasswordVisible((current) => !current)}
                >
                  <Text style={styles.passwordToggleText}>{registerPasswordVisible ? 'إخفاء' : 'إظهار'}</Text>
                </Pressable>
              </View>
              <View style={styles.passwordInputWrap}>
                <TextInput
                  value={registerPasswordConfirm}
                  onChangeText={setRegisterPasswordConfirm}
                  placeholder="تأكيد كلمة المرور"
                  placeholderTextColor="#93a1b6"
                  secureTextEntry={!registerPasswordConfirmVisible}
                  autoCapitalize="none"
                  textContentType="newPassword"
                  style={[styles.loginInput, styles.passwordTextInput]}
                />
                <Pressable
                  style={styles.passwordToggle}
                  onPress={() => setRegisterPasswordConfirmVisible((current) => !current)}
                >
                  <Text style={styles.passwordToggleText}>{registerPasswordConfirmVisible ? 'إخفاء' : 'إظهار'}</Text>
                </Pressable>
              </View>
              <Pressable
                style={[styles.policyCheckRow, registerPoliciesAccepted && styles.policyCheckRowActive]}
                onPress={() => setRegisterPoliciesAccepted((current) => !current)}
              >
                <View style={[styles.policyCheckBox, registerPoliciesAccepted && styles.policyCheckBoxActive]}>
                  <Text style={styles.policyCheckMark}>{registerPoliciesAccepted ? '✓' : ''}</Text>
                </View>
                <Text style={styles.policyCheckText}>
                  أوافق على الشروط والأحكام وسياسة الخصوصية وقواعد الأسعار والاسترداد والدفع الآمن.
                </Text>
              </Pressable>
              <Pressable style={styles.loginButton} onPress={handleRegister} disabled={loading}>
                <Text style={styles.loginButtonText}>{loading ? 'جارٍ إنشاء الحساب...' : 'إنشاء الحساب'}</Text>
              </Pressable>
            </>
          )}
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar style="light" />
      <ScrollView
        contentContainerStyle={styles.scrollContent}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={handleRefresh} tintColor="#D32F2F" />}
      >
        <View style={styles.heroCard}>
          <View style={styles.heroTopRow}>
            <View style={styles.heroTopCopy}>
              <Text style={styles.heroEyebrow}>مساحة الراكب</Text>
              <Text style={styles.heroTitle}>ابحث عن الرحلة، افتح المسار، واحجز بسرعة.</Text>
              <Text style={styles.heroMeta}>ابحث مرة واحدة، اختر بطاقة الرحلة المناسبة، ثم أكمل الحجز من لوحة مركزة وواضحة.</Text>
            </View>
            <View style={styles.heroActionColumn}>
              <Pressable
                style={styles.notificationBellButton}
                accessibilityRole="button"
                accessibilityLabel={`فتح الإشعارات. ${unreadNotifications.toLocaleString('ar-EG')} غير مقروءة`}
                onPress={async () => {
                  setNotificationPanelOpen(true);
                }}
              >
                <Text style={styles.notificationBellIcon}>إشعارات</Text>
                <Text style={styles.notificationBellLabel}>التحديثات</Text>
                {unreadNotifications > 0 ? (
                  <View style={styles.notificationBellBadge}>
                    <Text style={styles.notificationBellBadgeText}>{unreadNotifications}</Text>
                  </View>
                ) : null}
              </Pressable>
              <Pressable
                style={styles.menuButton}
                accessibilityRole="button"
                accessibilityLabel="فتح قائمة صفحات حساب الراكب"
                onPress={() => setMenuOpen(true)}
              >
                <Text style={styles.menuButtonIcon}>☰</Text>
              </Pressable>
            </View>
          </View>
        </View>

        {networkNotice ? (
          <View style={styles.networkNotice}>
            <Text style={styles.networkNoticeText}>{networkNotice}</Text>
          </View>
        ) : null}

        {activeTab === 'reserve' || liveActiveReservation ? (
          <PassengerTravelReadiness
            online={isOnline}
            notificationReady={notificationPermissionStatus === 'granted'}
            locationReady={Boolean(passengerCoords)}
            hasReservation={Boolean(activeReservation)}
            paymentReady={!activeReservation || ['PAID', 'AUTHORIZED', 'PAID_CASH_COLLECTED', 'CASH_COLLECTED', 'PENDING_CASH_COLLECTION'].includes(String(activeReservation.paymentStatus || '').toUpperCase())}
            driverAssigned={Boolean(activeReservation?.trip.driverProfile)}
            onEnableLocation={() => void handleNearestTripSearch()}
            onEnableNotifications={() => void openNotificationSettings()}
            onOpenHistory={() => setActiveTab('history')}
            onOpenSupport={() => setActiveTab('support')}
          />
        ) : null}

        {liveActiveReservation ? (
          <PassengerJourneyCommandCenter
            reservation={liveActiveReservation}
            driver={liveTripDriver}
            live
            online={isOnline}
            unreadCount={unreadNotifications}
            onDirections={() => void openPointDirections(liveActiveReservation.pickupPoint)}
            onCallDriver={() => void openDialer(liveTripDriver?.phone)}
            onShare={() => void shareReservationTrip(liveActiveReservation)}
            onOpenHistory={() => setActiveTab('history')}
            onOpenNotifications={() => setNotificationPanelOpen(true)}
            onAddCalendar={() => void addReservationCalendarEvent(liveActiveReservation)}
          >
            {renderDriverAssistCard(liveTripDriver, 'سيظهر اسم السائق قريبًا')}
            {activeChatTripId === liveActiveReservation.trip.id ? (
              <PassengerTripChatPanel
                currentUserId={meUser?.id || null}
                messages={activeTripChatMessages}
                driverParticipant={activeTripChatParticipants?.driver || null}
                draft={chatDraft}
                sending={chatSendingTripId === liveActiveReservation.trip.id}
                onDraftChange={setChatDraft}
                onSend={() => {
                  void sendTripChatMessage();
                }}
              />
            ) : chatLoadingTripId === liveActiveReservation.trip.id ? (
              <Text style={styles.driverAssistMeta}>جارٍ تحميل محادثة الرحلة...</Text>
            ) : null}
            <View style={styles.focusMapCard}>
              <Text style={styles.focusTripTitle}>المسار المباشر</Text>
              <Text style={styles.focusTripRoute}>
                تعرض الخريطة موقع السائق ومسار الرحلة المعتمد على خرائط Google.
              </Text>
              {liveActiveReservation.trip.pickupPoints?.length ? (
                <TripRouteMap
                  points={liveActiveReservation.trip.pickupPoints}
                  routePolyline={liveActiveReservation.trip.routePolyline}
                  driver={liveTripDriver}
                  vehicleSeats={liveActiveReservation.trip.totalSeats ?? liveTripDriver?.seatsAvailable ?? null}
                  height={260}
                />
              ) : null}
            </View>
          </PassengerJourneyCommandCenter>
        ) : activeTab === 'reserve' ? (
          <>
            {activeReservation ? (
              <PassengerJourneyCommandCenter
                reservation={activeReservation}
                driver={activeTripDriver}
                live={false}
                online={isOnline}
                unreadCount={unreadNotifications}
                onDirections={() => void openPointDirections(activeReservation.pickupPoint)}
                onCallDriver={() => void openDialer(activeTripDriver?.phone)}
                onShare={() => void shareReservationTrip(activeReservation)}
                onOpenHistory={() => setActiveTab('history')}
                onOpenNotifications={() => setNotificationPanelOpen(true)}
                onAddCalendar={() => void addReservationCalendarEvent(activeReservation)}
              >
                {renderDriverAssistCard(activeTripDriver, 'سيظهر اسم السائق قريبًا')}
                {activeChatTripId === activeReservation.trip.id ? (
                  <PassengerTripChatPanel
                    currentUserId={meUser?.id || null}
                    messages={activeTripChatMessages}
                    driverParticipant={activeTripChatParticipants?.driver || null}
                    draft={chatDraft}
                    sending={chatSendingTripId === activeReservation.trip.id}
                    onDraftChange={setChatDraft}
                    onSend={() => {
                      void sendTripChatMessage();
                    }}
                  />
                ) : chatLoadingTripId === activeReservation.trip.id ? (
                  <Text style={styles.driverAssistMeta}>جارٍ تحميل محادثة الرحلة...</Text>
                ) : null}
                {activeReservation.trip.pickupPoints?.length ? (
                  <View style={styles.focusMapCard}>
                    <TripRouteMap
                      points={activeReservation.trip.pickupPoints}
                      routePolyline={activeReservation.trip.routePolyline}
                      driver={activeTripDriver}
                      vehicleSeats={activeReservation.trip.totalSeats ?? activeTripDriver?.seatsAvailable ?? null}
                      height={220}
                    />
                  </View>
                ) : null}
              </PassengerJourneyCommandCenter>
            ) : null}

            <View style={styles.searchCard}>
              <Text style={styles.routeSearchTitle}>ابحث عن الرحلة المناسبة</Text>
              <Text style={styles.routeSearchHint}>اختر من وإلى من المحطات الموجودة فعلاً، وحدد التاريخ أو رتب الرحلات حسب أقرب نقطة صعود.</Text>
              <View style={styles.routeSearchGrid}>
                <View style={styles.routeField}>
                  <Text style={styles.routeFieldLabel}>من</Text>
                  <TextInput
                    value={fromQuery}
                    onChangeText={setFromQuery}
                    placeholder="نقطة الصعود"
                    placeholderTextColor="#9ca3af"
                    style={styles.searchInput}
                  />
                  {pickupSearchOptions.length > 0 ? (
                    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.stopSuggestionRow}>
                      {pickupSearchOptions.map((point) => (
                        <Pressable key={point.id} style={styles.stopSuggestionChip} onPress={() => setFromQuery(point.name)}>
                          <Text style={styles.stopSuggestionText}>{point.name}</Text>
                        </Pressable>
                      ))}
                    </ScrollView>
                  ) : null}
                </View>

                <View style={styles.routeField}>
                  <Text style={styles.routeFieldLabel}>إلى</Text>
                  <TextInput
                    value={toQuery}
                    onChangeText={setToQuery}
                    placeholder="نقطة النزول"
                    placeholderTextColor="#9ca3af"
                    style={styles.searchInput}
                  />
                  {dropoffSearchOptions.length > 0 ? (
                    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.stopSuggestionRow}>
                      {dropoffSearchOptions.map((point) => (
                        <Pressable key={point.id} style={styles.stopSuggestionChip} onPress={() => setToQuery(point.name)}>
                          <Text style={styles.stopSuggestionText}>{point.name}</Text>
                        </Pressable>
                      ))}
                    </ScrollView>
                  ) : null}
                </View>

                <View style={styles.routeField}>
                  <Text style={styles.routeFieldLabel}>التاريخ</Text>
                  <TextInput
                    value={serviceDateQuery}
                    onChangeText={(value) => setServiceDateQuery(value.replace(/[^\d-]/g, '').slice(0, 10))}
                    placeholder="YYYY-MM-DD"
                    placeholderTextColor="#9ca3af"
                    style={styles.searchInput}
                  />
                </View>
              </View>
              <TextInput
                value={query}
                onChangeText={setQuery}
                placeholder="بحث إضافي باسم الرحلة أو الوجهة"
                placeholderTextColor="#93a1b6"
                style={styles.searchInput}
              />
              <View style={styles.routeActionRow}>
                <Pressable style={[styles.searchButton, styles.routeActionButton]} onPress={handleSearch} disabled={searching}>
                  <Text style={styles.searchButtonText}>{searching ? 'جارٍ البحث...' : 'ابحث'}</Text>
                </Pressable>
                <Pressable style={[styles.locationSearchButton, styles.routeActionButton]} onPress={handleNearestTripSearch} disabled={searching}>
                  <Text style={styles.locationSearchButtonText}>الأقرب لي</Text>
                </Pressable>
              </View>
              {locationSearchNote ? <Text style={styles.locationSearchNote}>{locationSearchNote}</Text> : null}
            </View>

              <View style={styles.sectionCard}>
                <View style={styles.sectionHeader}>
                  <Text style={styles.sectionTitle}>الرحلات المقترحة</Text>
                  <View style={styles.sectionHeaderActions}>
                    <Pressable
                      style={[styles.supportPill, favoritesOnly && styles.supportPillActive]}
                      onPress={() => setFavoritesOnly((current) => !current)}
                    >
                      <Text style={[styles.supportPillText, favoritesOnly && styles.supportPillTextActive]}>
                        {favoritesOnly ? 'عرض كل الرحلات' : `المفضلة ${localPreferences.favoriteTripIds.length}`}
                      </Text>
                    </Pressable>
                    <Text style={styles.sectionBadge}>{displayedTrips.length}</Text>
                  </View>
                </View>

              {displayedTrips.length === 0 ? (
                <Text style={styles.emptyStateText}>لا توجد رحلات متاحة لهذا البحث حالياً.</Text>
              ) : (
                <View style={styles.tripList}>
                  {displayedTrips.map((trip) => {
                    const ordered = [...(trip.pickupPoints || [])].sort((a, b) => a.stopOrder - b.stopOrder);
                    const startPoint = ordered[0];
                    const endPoint = ordered[ordered.length - 1];
                    const serviceOptions = (trip.occurrences?.length
                      ? trip.occurrences
                      : [{ id: trip.id, startTime: trip.startTime, seatsRemaining: trip.seatsRemaining, status: 'SCHEDULED' }]
                    )
                      .filter((occurrence) => String(occurrence.status || 'SCHEDULED').toUpperCase() === 'SCHEDULED')
                      .sort((left, right) => new Date(left.startTime).getTime() - new Date(right.startTime).getTime());
                    const nextService = serviceOptions[0] || trip;
                    const isRepeating = serviceOptions.length > 1;

                    return (
                      <Pressable
                        key={trip.id}
                        style={[styles.tripCard, selectedTripId === trip.id && styles.tripCardSelected]}
                        onPress={() => setSelectedTripId(trip.id)}
                      >
                        <View style={styles.tripCardHeader}>
                          <Text style={styles.tripCardTitle}>{trip.title}</Text>
                          <Text style={styles.tripSeatsBadge}>
                            {isRepeating ? `${serviceOptions.length} أيام` : `${trip.seatsRemaining} مقعد`}
                          </Text>
                        </View>
                        <Text style={styles.tripCardRoute}>
                          {startPoint?.name || trip.mainDestination}
                          {' ← '}
                          {endPoint?.name || trip.endDestination}
                        </Text>
                        <Text style={styles.tripServiceClass}>
                          {trip.serviceClassNameAr || (trip.serviceClassCode === 'LUXURY_SEDAN' ? 'سيدان فاخرة' : trip.serviceClassCode === 'ECONOMY_COASTER' ? 'كوستر اقتصادية' : 'هاي إيس عادية')}
                          {' · '}
                          {trip.totalSeats} مقعد
                        </Text>
                        <View style={styles.tripCardBottom}>
                          <Text style={styles.tripCardMeta}>
                            {isRepeating ? `القادم ${formatDate(nextService.startTime)}` : formatDate(trip.startTime)}
                          </Text>
                          <Text style={styles.tripCardPrice}>{formatMoney(trip.basePrice)}</Text>
                        </View>
                        {isRepeating ? (
                          <View style={styles.tripDateChipRow}>
                            {serviceOptions.slice(0, 5).map((occurrence) => (
                              <Text key={occurrence.id} style={styles.tripDateChip}>
                                {new Date(occurrence.startTime).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })}
                              </Text>
                            ))}
                            {serviceOptions.length > 5 ? <Text style={styles.tripDateChip}>+{serviceOptions.length - 5}</Text> : null}
                          </View>
                        ) : null}
                        <View style={styles.tripCardActionRow}>
                          <View style={styles.tripCardActionHint}>
                            <Text style={styles.tripCardActionHintText}>
                              {selectedTripId === trip.id ? 'الرحلة مركزة الآن' : isRepeating ? 'بطاقة واحدة لكل مواعيد التكرار' : 'اضغط لتركيز الرحلة'}
                            </Text>
                          </View>
                          <Pressable
                            style={[
                              styles.tripFavoriteButton,
                              localPreferences.favoriteTripIds.includes(trip.id) && styles.tripFavoriteButtonActive,
                            ]}
                            onPress={() => toggleFavoriteTrip(trip.id)}
                          >
                            <Text
                              style={[
                                styles.tripFavoriteButtonText,
                                localPreferences.favoriteTripIds.includes(trip.id) && styles.tripFavoriteButtonTextActive,
                              ]}
                            >
                              {localPreferences.favoriteTripIds.includes(trip.id) ? 'محفوظة' : 'حفظ'}
                            </Text>
                          </Pressable>
                          <Pressable style={styles.tripCardActionWrap} onPress={() => openTripReservation(trip)}>
                            <Text style={styles.tripCardAction}>احجز</Text>
                          </Pressable>
                        </View>
                      </Pressable>
                    );
                  })}
                </View>
              )}
            </View>

            <View style={styles.sectionCard}>
              <View style={styles.sectionHeader}>
                <Text style={styles.sectionTitle}>تفاصيل حجز الرحلة</Text>
                <Text style={styles.sectionBadge}>{selectedTrip ? 'مركزة' : 'بانتظار الاختيار'}</Text>
              </View>

              {selectedTrip ? (
                <>
                  <View style={styles.focusMapCard}>
                    <TripRouteMap
                      points={orderedPoints}
                      routePolyline={selectedTrip.routePolyline}
                      driver={selectedTripDriver}
                      vehicleSeats={selectedTrip.totalSeats ?? selectedTripDriver?.seatsAvailable ?? null}
                      height={200}
                    />
                  </View>
                  <View style={styles.focusDetailsCard}>
                    <Text style={styles.focusTripTitle}>{selectedTrip.title}</Text>
                    <Text style={styles.focusTripRoute}>
                      {orderedPoints[0]?.name || selectedTrip.mainDestination}
                      {' ← '}
                      {orderedPoints[orderedPoints.length - 1]?.name || selectedTrip.endDestination}
                    </Text>
                    {selectedTripServiceOptions.length > 1 ? (
                      <View style={styles.recurringSummaryCard}>
                        <View style={styles.recurringSummaryHeader}>
                          <Text style={styles.recurringSummaryTitle}>رحلة متكررة في بطاقة واحدة</Text>
                          <Text style={styles.tripSeatsBadge}>{selectedTripServiceOptions.length} مواعيد</Text>
                        </View>
                        <Text style={styles.recurringSummaryHint}>
                          افتح الحجز لاختيار موعد واحد أو عدة مواعيد من نفس الرحلة بدون بطاقات مكررة.
                        </Text>
                        <View style={styles.tripDateChipRow}>
                          {selectedTripServiceOptions.slice(0, 6).map((occurrence) => (
                            <Text key={occurrence.id} style={styles.tripDateChip}>
                              {new Date(occurrence.startTime).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })}
                            </Text>
                          ))}
                          {selectedTripServiceOptions.length > 6 ? <Text style={styles.tripDateChip}>+{selectedTripServiceOptions.length - 6}</Text> : null}
                        </View>
                      </View>
                    ) : null}
                    <View style={styles.focusStatsGrid}>
                      <View style={styles.focusStatCard}>
                        <Text style={styles.focusStatLabel}>الانطلاق</Text>
                        <Text style={styles.focusStatValue}>{formatDate(selectedTrip.startTime)}</Text>
                      </View>
                      <View style={styles.focusStatCard}>
                        <Text style={styles.focusStatLabel}>الوصول</Text>
                        <Text style={styles.focusStatValue}>{formatDate(selectedTrip.estimatedEndTime || null)}</Text>
                      </View>
                      <View style={styles.focusStatCard}>
                        <Text style={styles.focusStatLabel}>المقاعد المتبقية</Text>
                        <Text style={styles.focusStatValue}>{selectedTrip.seatsRemaining}</Text>
                      </View>
                      <View style={styles.focusStatCard}>
                        <Text style={styles.focusStatLabel}>السعر</Text>
                        <Text style={styles.focusStatValue}>{formatMoney(selectedTrip.basePrice)}</Text>
                      </View>
                    </View>
                    {renderDriverAssistCard(selectedTripDriver, 'سيتم تعيين السائق قريبًا')}
                    <View style={styles.focusActionRow}>
                      <Pressable style={styles.secondaryActionButton} onPress={() => setSelectedTripId('')}>
                        <Text style={styles.secondaryActionButtonText}>اختر رحلة أخرى</Text>
                      </Pressable>
                      <Pressable style={styles.primaryActionButton} onPress={() => openTripReservation(selectedTrip)}>
                        <Text style={styles.primaryActionButtonText}>افتح الحجز</Text>
                      </Pressable>
                    </View>
                  </View>
                </>
              ) : (
                <Text style={styles.emptyStateText}>
                  اختر بطاقة رحلة من الأعلى لعرض الملخص، ثم أكمل الحجز من اللوحة الكاملة.
                </Text>
              )}
            </View>
          </>
        ) : null}

        {activeTab === 'wallet' ? (
          <View style={styles.sectionCard}>
            <View style={styles.sectionHeader}>
              <View>
                <Text style={styles.sectionTitle}>محفظة SOFT CAR</Text>
                <Text style={styles.emptyStateText}>اشحن الرصيد، ادفع الحجوزات، واستقبل قيمة الاسترداد في مكان واحد.</Text>
              </View>
              <Text style={styles.sectionBadge}>{walletData?.account?.status || walletData?.wallet?.status || 'ACTIVE'}</Text>
            </View>

            <View style={styles.focusStatsGrid}>
              <View style={styles.focusStatCard}>
                <Text style={styles.focusStatLabel}>الرصيد المتاح</Text>
                <Text style={styles.focusStatValue}>{formatMoney(walletData?.account?.balance ?? walletData?.wallet?.balance ?? 0)}</Text>
              </View>
              <View style={styles.focusStatCard}>
                <Text style={styles.focusStatLabel}>قيد المراجعة</Text>
                <Text style={styles.focusStatValue}>{formatMoney(walletData?.account?.pendingCredit ?? walletData?.wallet?.pendingCredit ?? 0)}</Text>
              </View>
              <View style={styles.focusStatCard}>
                <Text style={styles.focusStatLabel}>استردادات للمحفظة</Text>
                <Text style={styles.focusStatValue}>{formatMoney(walletData?.account?.totalRefunded ?? walletData?.wallet?.totalRefunded ?? 0)}</Text>
              </View>
            </View>

            <View style={styles.walletProofCard}>
              <Text style={styles.walletProofTitle}>شحن المحفظة</Text>
              <View style={styles.supportPillRow}>
                {[
                  { key: 'TRANSFER' as const, label: 'تحويل نقدي' },
                  { key: 'CARD' as const, label: 'فيزا / بطاقة' },
                ].map((option) => (
                  <Pressable
                    key={option.key}
                    style={[styles.supportPill, walletTopupChannel === option.key && styles.supportPillActive]}
                    onPress={() => setWalletTopupChannel(option.key)}
                    disabled={walletTopupSubmitting}
                  >
                    <Text style={[styles.supportPillText, walletTopupChannel === option.key && styles.supportPillTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                ))}
              </View>
              <TextInput
                value={walletTopupAmount}
                onChangeText={setWalletTopupAmount}
                placeholder="قيمة الشحن"
                placeholderTextColor="#93a1b6"
                keyboardType="decimal-pad"
                editable={!walletTopupSubmitting}
                style={[styles.searchInput, styles.walletSenderInput]}
              />
              {walletTopupChannel === 'TRANSFER' ? (
                <>
                  <Text style={styles.walletProofMeta}>رقم الاستلام: {walletRecipientNumber || 'يظهر بعد مزامنة إعدادات المدير'}</Text>
                  {walletInstructions ? <Text style={styles.walletProofText}>{walletInstructions}</Text> : null}
                  <TextInput
                    value={walletTopupSender}
                    onChangeText={setWalletTopupSender}
                    placeholder="رقم الهاتف المحول منه"
                    placeholderTextColor="#93a1b6"
                    keyboardType="phone-pad"
                    editable={!walletTopupSubmitting}
                    style={[styles.searchInput, styles.walletSenderInput]}
                  />
                </>
              ) : (
                <Text style={styles.walletProofText}>سيتم فتح صفحة دفع آمنة لإتمام شحن المحفظة بالبطاقة ثم تحديث الرصيد تلقائيا.</Text>
              )}
              <Pressable
                style={[styles.primaryActionButton, walletTopupSubmitting && styles.disabledActionButton]}
                disabled={walletTopupSubmitting}
                onPress={() => void submitWalletTopup()}
              >
                <Text style={styles.primaryActionButtonText}>{walletTopupSubmitting ? 'جاري الشحن...' : 'إرسال طلب الشحن'}</Text>
              </Pressable>
            </View>

            {(walletData?.pendingTransactions || []).length > 0 ? (
              <View style={styles.benefitCard}>
                <Text style={styles.benefitTitle}>طلبات شحن قيد المراجعة</Text>
                {(walletData?.pendingTransactions || []).slice(0, 5).map((transaction) => (
                  <View key={transaction.id} style={styles.reservationMiniRow}>
                    <View style={styles.flexOne}>
                      <Text style={styles.reservationMeta}>{formatMoney(transaction.amount)}</Text>
                      <Text style={styles.reservationMeta}>{formatPaymentMethodLabel(transaction.method)} - {transaction.status}</Text>
                    </View>
                    <Text style={styles.tripDateChip}>{formatDate(transaction.createdAt)}</Text>
                  </View>
                ))}
              </View>
            ) : null}

            <View style={styles.benefitCard}>
              <Text style={styles.benefitTitle}>حركة المحفظة</Text>
              {(walletData?.ledger || []).length === 0 ? (
                <Text style={styles.benefitText}>لا توجد عمليات حتى الآن. اشحن المحفظة أو اطلب استردادا لتظهر الحركة هنا.</Text>
              ) : (
                (walletData?.ledger || []).slice(0, 12).map((entry) => (
                  <View key={entry.id} style={styles.reservationMiniRow}>
                    <View style={styles.flexOne}>
                      <Text style={styles.reservationMeta}>{entry.note || (entry.direction === 'CREDIT' ? 'إضافة رصيد' : 'خصم من الرصيد')}</Text>
                      <Text style={styles.reservationMeta}>بعد العملية: {formatMoney(entry.balanceAfter)} - {formatDate(entry.createdAt)}</Text>
                    </View>
                    <Text style={[styles.tripDateChip, entry.direction === 'CREDIT' ? styles.tripDateChipActive : null]}>
                      {entry.direction === 'CREDIT' ? '+' : '-'}{formatMoney(entry.amount)}
                    </Text>
                  </View>
                ))
              )}
            </View>
          </View>
        ) : null}

        {activeTab === 'history' ? (
          <View style={styles.sectionCard}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>سجل الحجوزات</Text>
              <Text style={styles.sectionBadge}>{filteredHistoryReservations.length}</Text>
            </View>
            <View style={styles.supportPillRow}>
              {[
                { key: 'all' as const, label: 'الكل' },
                { key: 'upcoming' as const, label: 'القادمة' },
                { key: 'completed' as const, label: 'المكتملة' },
                { key: 'cancelled' as const, label: 'الملغاة' },
                { key: 'refunds' as const, label: 'الاستردادات' },
              ].map((item) => (
                <Pressable
                  key={item.key}
                  style={[styles.supportPill, historyFilter === item.key && styles.supportPillActive]}
                  onPress={() => setHistoryFilter(item.key)}
                >
                  <Text style={[styles.supportPillText, historyFilter === item.key && styles.supportPillTextActive]}>
                    {item.label}
                  </Text>
                </Pressable>
              ))}
            </View>
            {filteredHistoryReservations.length === 0 ? (
              <View style={styles.benefitCard}>
                <Text style={styles.benefitTitle}>لا توجد نتائج في هذا التصنيف</Text>
                <Text style={styles.benefitText}>غيّر التصنيف أو اسحب الصفحة لأسفل لتحديث سجل حسابك.</Text>
              </View>
            ) : (
              reservationDisplayGroups.map((group) => {
                const first = group[0];
                const groupKey = reservationDisplayGroupKey(first);
                const expanded = expandedReservationGroups.includes(groupKey);
                const groupTotal = group.reduce((sum, reservation) => sum + Number(reservation.totalPrice || 0), 0);
                const paidPackage = isReservationPaidPackage(group);

                if (group.length === 1) {
                  const reservation = first;
                  const singleTotalLabel = paidPackage
                    ? 'مدفوع مرة واحدة - لا يوجد دفع لاحق'
                    : formatMoney(reservation.totalPrice);
                  if (paidPackage) {
                    return (
                      <Pressable
                        key={reservation.id}
                        style={styles.reservationCard}
                        onPress={() =>
                          setExpandedReservationGroups((current) =>
                            current.includes(groupKey)
                              ? current.filter((item) => item !== groupKey)
                              : [...current, groupKey]
                          )
                        }
                      >
                        <View style={styles.reservationHeader}>
                          <Text style={styles.reservationTripTitle}>{reservation.trip.title}</Text>
                          <Text style={styles.reservationStatus}>{formatReservationStatusLabel(reservation.status)}</Text>
                        </View>
                        <Text style={styles.reservationMeta}>{reservation.pickupPoint.name}{' ← '}{reservation.dropoffPoint.name}</Text>
                        <Text style={styles.reservationMeta}>موعد الصعود: {formatDate(reservation.trip.startTime)}</Text>
                        <View style={styles.reservationFooter}>
                          <Text style={styles.reservationMeta}>المقعد: {reservation.seatNumbers || '-'}</Text>
                          <Text style={styles.reservationMeta}>التذكرة: {reservation.ticketCode || '-'}</Text>
                        </View>
                        <Text style={styles.reservationMeta}>الدفع: {formatPaymentMethodLabel(reservation.paymentMethod)} / باقة مدفوعة</Text>
                        <Text style={styles.reservationMeta}>{singleTotalLabel}</Text>
                        {expanded ? (
                          <View style={styles.reservationGroupDetails}>
                            <Text style={styles.reservationMeta}>حالة الدفع: {reservation.paymentStatus || 'باقة مدفوعة'}</Text>
                            <Text style={styles.reservationMeta}>رقم الحجز: {reservation.id}</Text>
                            <Text style={styles.reservationMeta}>حالة الرحلة: {formatTripStatusLabel(reservation.trip.status)}</Text>
                            <ReservationReceiptButton reservation={reservation} />
                            {renderReservationQuickActions(reservation)}
                            {renderRefundControls([reservation], 'single')}
                            {renderReviewControl(reservation)}
                          </View>
                        ) : (
                          <Text style={styles.reservationMeta}>اضغط لمراجعة تفاصيل السجل كاملة</Text>
                        )}
                      </Pressable>
                    );
                  }
                  return (
                    <Pressable
                      key={reservation.id}
                      style={styles.reservationCard}
                      onPress={() =>
                        setExpandedReservationGroups((current) =>
                          current.includes(groupKey)
                            ? current.filter((item) => item !== groupKey)
                            : [...current, groupKey]
                        )
                      }
                    >
                      <View style={styles.reservationHeader}>
                        <Text style={styles.reservationTripTitle}>{reservation.trip.title}</Text>
                        <Text style={styles.reservationStatus}>{formatReservationStatusLabel(reservation.status)}</Text>
                      </View>
                      <Text style={styles.reservationMeta}>
                        {reservation.pickupPoint.name}
                        {' ← '}
                        {reservation.dropoffPoint.name}
                      </Text>
                      <Text style={styles.reservationMeta}>موعد الصعود: {formatDate(reservation.trip.startTime)}</Text>
                      <View style={styles.reservationFooter}>
                        <Text style={styles.reservationMeta}>المقعد: {reservation.seatNumbers || '-'}</Text>
                        <Text style={styles.reservationMeta}>التذكرة: {reservation.ticketCode || '-'}</Text>
                      </View>
                      <Text style={styles.reservationMeta}>الدفع: {formatPaymentMethodLabel(reservation.paymentMethod)}</Text>
                      <Text style={styles.reservationMeta}>الإجمالي: {formatMoney(reservation.totalPrice)}</Text>
                      {expanded ? (
                        <View style={styles.reservationGroupDetails}>
                          <Text style={styles.reservationMeta}>حالة الدفع: {reservation.paymentStatus || '-'}</Text>
                          <Text style={styles.reservationMeta}>رقم الحجز: {reservation.id}</Text>
                          <Text style={styles.reservationMeta}>حالة الرحلة: {formatTripStatusLabel(reservation.trip.status)}</Text>
                          <ReservationReceiptButton reservation={reservation} />
                          {renderReservationQuickActions(reservation)}
                          {renderRefundControls([reservation], 'single')}
                          {renderReviewControl(reservation)}
                        </View>
                      ) : (
                        <Text style={styles.reservationMeta}>اضغط لمراجعة تفاصيل السجل كاملة</Text>
                      )}
                    </Pressable>
                  );
                }

                if (paidPackage) {
                  return (
                    <Pressable
                      key={groupKey}
                      style={styles.reservationCard}
                      onPress={() =>
                        setExpandedReservationGroups((current) =>
                          current.includes(groupKey)
                            ? current.filter((item) => item !== groupKey)
                            : [...current, groupKey]
                        )
                      }
                    >
                      <View style={styles.reservationHeader}>
                        <Text style={styles.reservationTripTitle}>{first.trip.title}</Text>
                        <Text style={styles.reservationStatus}>{group.length} مواعيد</Text>
                      </View>
                      <Text style={styles.reservationMeta}>{first.pickupPoint.name}{' ← '}{first.dropoffPoint.name}</Text>
                      <View style={styles.tripDateChipRow}>
                        {group.slice(0, 8).map((reservation) => (
                          <Text key={reservation.id} style={styles.tripDateChip}>
                            {new Date(reservation.trip.startTime).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })}
                          </Text>
                        ))}
                        {group.length > 8 ? <Text style={styles.tripDateChip}>+{group.length - 8}</Text> : null}
                      </View>
                      <View style={styles.reservationFooter}>
                        <Text style={styles.reservationMeta}>المقعد: {first.seatNumbers || '-'}</Text>
                        <Text style={styles.reservationMeta}>باقة مدفوعة</Text>
                      </View>
                      <Text style={styles.reservationMeta}>تم تحصيل النقد مرة واحدة. الأيام التالية لا تطلب دفعًا جديدًا.</Text>
                      <Text style={styles.reservationMeta}>{expanded ? 'اضغط لإغلاق التفاصيل' : 'اضغط لعرض كل يوم ووقته'}</Text>
                      {expanded ? (
                        <View style={styles.reservationGroupDetails}>
                          {group.map((reservation) => (
                            <View key={reservation.id} style={styles.reservationMiniRow}>
                              <View style={styles.flexOne}>
                                <Text style={styles.reservationMeta}>{formatDate(reservation.trip.startTime)}</Text>
                                <Text style={styles.reservationMeta}>{reservation.ticketCode || '-'}</Text>
                              </View>
                              {renderReviewControl(reservation)}
                            </View>
                          ))}
                          <ReservationReceiptButton reservation={first} />
                          {renderReservationQuickActions(first)}
                          {renderRefundControls(group, 'trip-group')}
                        </View>
                      ) : null}
                    </Pressable>
                  );
                }

                return (
                  <Pressable
                    key={groupKey}
                    style={styles.reservationCard}
                    onPress={() =>
                      setExpandedReservationGroups((current) =>
                        current.includes(groupKey)
                          ? current.filter((item) => item !== groupKey)
                          : [...current, groupKey]
                      )
                    }
                  >
                    <View style={styles.reservationHeader}>
                      <Text style={styles.reservationTripTitle}>{first.trip.title}</Text>
                      <Text style={styles.reservationStatus}>{group.length} مواعيد</Text>
                    </View>
                    <Text style={styles.reservationMeta}>
                      {first.pickupPoint.name}
                      {' ← '}
                      {first.dropoffPoint.name}
                    </Text>
                    <View style={styles.tripDateChipRow}>
                      {group.slice(0, 8).map((reservation) => (
                        <Text key={reservation.id} style={styles.tripDateChip}>
                          {new Date(reservation.trip.startTime).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })}
                        </Text>
                      ))}
                      {group.length > 8 ? <Text style={styles.tripDateChip}>+{group.length - 8}</Text> : null}
                    </View>
                    <View style={styles.reservationFooter}>
                      <Text style={styles.reservationMeta}>المقعد: {first.seatNumbers || '-'}</Text>
                      <Text style={styles.reservationMeta}>الإجمالي: {formatMoney(groupTotal)}</Text>
                    </View>
                    <Text style={styles.reservationMeta}>{expanded ? 'اضغط لإغلاق التفاصيل' : 'اضغط لعرض كل يوم ووقته'}</Text>
                    {expanded ? (
                      <View style={styles.reservationGroupDetails}>
                        {group.map((reservation) => (
                          <View key={reservation.id} style={styles.reservationMiniRow}>
                            <View style={styles.flexOne}>
                              <Text style={styles.reservationMeta}>{formatDate(reservation.trip.startTime)}</Text>
                              <Text style={styles.reservationMeta}>{reservation.ticketCode || '-'}</Text>
                            </View>
                            {renderReviewControl(reservation)}
                          </View>
                        ))}
                        <ReservationReceiptButton reservation={first} />
                        {renderReservationQuickActions(first)}
                        {renderRefundControls(group, 'trip-group')}
                      </View>
                    ) : null}
                  </Pressable>
                );
              })
            )}
          </View>
        ) : null}

        {activeTab === 'loyalty' ? (
          <>
          <View style={styles.sectionCard}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>برنامج الولاء</Text>
              <Text style={styles.sectionBadge}>{loyalty?.summary.currentLevel.name || 'جارٍ التحديث'}</Text>
            </View>
            {loyalty ? (
              <>
              <View style={styles.loyaltyHeroCard}>
                <Text style={styles.loyaltyEyebrow}>مكافآت سوفت كار</Text>
                <Text style={styles.loyaltyPoints}>{loyalty.summary.points.toLocaleString('ar-EG')} نقطة</Text>
                <Text style={styles.loyaltyHint}>{loyalty.summary.pointsRule}</Text>
                <View style={styles.loyaltyProgressTrack}>
                  <View style={[styles.loyaltyProgressFill, { width: `${loyalty.summary.progressPercent}%` }]} />
                </View>
                <Text style={styles.loyaltyHint}>
                  {loyalty.summary.nextLevel
                    ? `يتبقى ${loyalty.summary.pointsUntilNextLevel.toLocaleString('ar-EG')} نقطة للوصول إلى ${loyalty.summary.nextLevel.name}.`
                    : 'وصلت إلى أعلى مستوى ولاء حالي.'}
                </Text>
              </View>
              <View style={styles.focusStatsGrid}>
                <View style={styles.focusStatCard}>
                  <Text style={styles.focusStatLabel}>رحلات مدفوعة ومكتملة</Text>
                  <Text style={styles.focusStatValue}>{loyalty.summary.completedTrips.toLocaleString('ar-EG')}</Text>
                </View>
                <View style={styles.focusStatCard}>
                  <Text style={styles.focusStatLabel}>الإنفاق المؤهل</Text>
                  <Text style={styles.focusStatValue}>{formatMoney(loyalty.summary.lifetimeSpend)}</Text>
                </View>
                <View style={styles.focusStatCard}>
                  <Text style={styles.focusStatLabel}>المستوى الحالي</Text>
                  <Text style={styles.focusStatValue}>{loyalty.summary.currentLevel.name}</Text>
                </View>
                <View style={styles.focusStatCard}>
                  <Text style={styles.focusStatLabel}>مكافآت مؤهلة</Text>
                  <Text style={styles.focusStatValue}>{loyalty.rewards.filter((reward) => reward.eligible).length.toLocaleString('ar-EG')}</Text>
                </View>
              </View>

              <View style={styles.sectionHeader}>
                <Text style={styles.supportPanelTitle}>مزايا المستوى</Text>
                <Text style={styles.sectionBadge}>{loyalty.summary.currentLevel.name}</Text>
              </View>
              <View style={styles.benefitList}>
                {loyalty.summary.currentLevel.benefits.map((benefit) => (
                  <View key={benefit} style={styles.benefitCard}>
                    <Text style={styles.benefitTitle}>{benefit}</Text>
                  </View>
                ))}
              </View>

              <View style={styles.sectionHeader}>
                <Text style={styles.supportPanelTitle}>المكافآت المنشورة</Text>
                <Text style={styles.sectionBadge}>{loyalty.rewards.length.toLocaleString('ar-EG')}</Text>
              </View>
              {loyalty.rewards.length ? (
                <View style={styles.benefitList}>
                  {loyalty.rewards.map((reward) => (
                    <View key={reward.id} style={[styles.benefitCard, reward.eligible && styles.loyaltyRewardEligible]}>
                      <View style={styles.sectionHeader}>
                        <Text style={styles.benefitTitle}>{reward.name}</Text>
                        <Text style={styles.sectionBadge}>{reward.eligible ? 'مؤهل الآن' : `${reward.progressPercent}%`}</Text>
                      </View>
                      {reward.description ? <Text style={styles.benefitText}>{reward.description}</Text> : null}
                      <View style={styles.loyaltyProgressTrack}>
                        <View style={[styles.loyaltyProgressFill, { width: `${reward.progressPercent}%` }]} />
                      </View>
                      {!reward.eligible ? (
                        <Text style={styles.benefitText}>
                          {reward.requirements.remainingTrips > 0
                            ? `يتبقى ${reward.requirements.remainingTrips.toLocaleString('ar-EG')} رحلة مكتملة. `
                            : ''}
                          {reward.requirements.remainingSpend > 0
                            ? `ويتـبقى إنفاق ${formatMoney(reward.requirements.remainingSpend)}.`
                            : ''}
                        </Text>
                      ) : null}
                      {reward.benefits.map((benefit) => (
                        <Text key={benefit} style={styles.benefitText}>• {benefit}</Text>
                      ))}
                    </View>
                  ))}
                </View>
              ) : (
                <View style={styles.benefitCard}>
                  <Text style={styles.benefitTitle}>لا توجد مكافآت منشورة حالياً</Text>
                  <Text style={styles.benefitText}>ستظهر عروض الشرائح المؤهلة هنا فور نشرها من الإدارة.</Text>
                </View>
              )}

              <View style={styles.sectionHeader}>
                <Text style={styles.supportPanelTitle}>سجل اكتساب النقاط</Text>
                <Text style={styles.sectionBadge}>{loyalty.activity.length.toLocaleString('ar-EG')}</Text>
              </View>
              {loyalty.activity.length ? (
                <View style={styles.benefitList}>
                  {loyalty.activity.map((item) => (
                    <View key={item.id} style={styles.loyaltyActivityRow}>
                      <View style={styles.flexOne}>
                        <Text style={styles.benefitTitle}>{item.tripTitle}</Text>
                        <Text style={styles.benefitText}>{formatDate(item.serviceDate)} · {formatMoney(item.amount)}</Text>
                        {item.ticketCode ? <Text style={styles.benefitText}>التذكرة: {item.ticketCode}</Text> : null}
                      </View>
                      <Text style={styles.loyaltyActivityPoints}>+{item.points.toLocaleString('ar-EG')}</Text>
                    </View>
                  ))}
                </View>
              ) : (
                <Text style={styles.emptyStateText}>تبدأ النقاط بعد اكتمال أول رحلة مدفوعة.</Text>
              )}
              </>
            ) : (
              <View style={styles.benefitCard}>
                <Text style={styles.benefitTitle}>تعذر تحميل الولاء الآن</Text>
                <Text style={styles.benefitText}>اسحب الصفحة لأسفل لإعادة المحاولة دون التأثير على الحجز أو السجل.</Text>
                <Pressable style={styles.secondaryActionButton} onPress={() => void handleRefresh()}>
                  <Text style={styles.secondaryActionButtonText}>إعادة المحاولة</Text>
                </Pressable>
              </View>
            )}
          </View>
          </>
        ) : null}

        {activeTab === 'compliance' ? (
          <>
          <View style={styles.sectionCard}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>الأمان والامتثال</Text>
              <Text style={styles.sectionBadge}>نشط</Text>
            </View>
            <View style={styles.complianceGrid}>
              <View style={styles.focusStatsGrid}>
                <View style={styles.focusStatCard}>
                  <Text style={styles.focusStatLabel}>حجوزات نشطة</Text>
                  <Text style={styles.focusStatValue}>{activeReservation ? '١' : '٠'}</Text>
                </View>
                <View style={styles.focusStatCard}>
                  <Text style={styles.focusStatLabel}>تنبيهات غير مقروءة</Text>
                  <Text style={styles.focusStatValue}>{unreadNotifications.toLocaleString('ar-EG')}</Text>
                </View>
                <View style={styles.focusStatCard}>
                  <Text style={styles.focusStatLabel}>طلبات استرداد مفتوحة</Text>
                  <Text style={styles.focusStatValue}>{pendingRefundCount.toLocaleString('ar-EG')}</Text>
                </View>
                <View style={styles.focusStatCard}>
                  <Text style={styles.focusStatLabel}>حجوزات ملغاة</Text>
                  <Text style={styles.focusStatValue}>{cancelledReservations.length.toLocaleString('ar-EG')}</Text>
                </View>
              </View>
              <View style={styles.complianceCard}>
                <Text style={styles.complianceTitle}>محطات معتمدة فقط</Text>
                <Text style={styles.complianceText}>الحجز يتم من نقاط صعود ونزول مسجلة في النظام وليس من نقطة عشوائية على الخريطة.</Text>
              </View>
              <View style={styles.complianceCard}>
                <Text style={styles.complianceTitle}>تذكرة ورقم مقعد</Text>
                <Text style={styles.complianceText}>بعد الحجز يظهر كود التذكرة والمقعد داخل سجل الرحلات والرحلة النشطة.</Text>
              </View>
              <View style={styles.complianceCard}>
                <Text style={styles.complianceTitle}>إشعارات الرحلة</Text>
                <Text style={styles.complianceText}>{notificationStatusNote}</Text>
              </View>
              <View style={styles.complianceCard}>
                <Text style={styles.complianceTitle}>دردشة السائق</Text>
                <Text style={styles.complianceText}>عند وجود رحلة نشطة تظهر المحادثة مع السائق داخل بطاقة الرحلة نفسها.</Text>
              </View>
            </View>
            <Pressable
              style={styles.primaryActionButton}
              onPress={async () => {
                setNotificationPanelOpen(true);
              }}
            >
              <Text style={styles.primaryActionButtonText}>فتح مركز الإشعارات</Text>
            </Pressable>
          </View>
          </>
        ) : null}

        {activeTab === 'support' ? (
          <>
          <SupportChatPanel token={token} userId={meUser?.id} />
          <View style={styles.sectionCard}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>الدعم والمساعدة</Text>
              <Text style={styles.sectionBadge}>24/7</Text>
            </View>
            <View style={styles.supportHero}>
              <Text style={styles.supportTitle}>كل أدوات المساعدة في مكان واحد</Text>
              <Text style={styles.supportText}>استخدم الاتصال وقت الرحلة، راجع الإشعارات، أو افتح الدردشة مع السائق عندما تكون لديك رحلة نشطة.</Text>
            </View>
            <View style={styles.supportPanel}>
              <Text style={styles.supportPanelTitle}>إنشاء طلب دعم حقيقي</Text>
              <Text style={styles.supportPanelText}>يتم حفظ الطلب في لوحة المتابعة مع النوع والأولوية والحالة وسجل كامل.</Text>
              <View style={styles.supportPillRow}>
                {SUPPORT_CATEGORIES.map((category) => (
                  <Pressable
                    key={category}
                    style={[styles.supportPill, supportCategory === category && styles.supportPillActive]}
                    onPress={() => setSupportCategory(category)}
                  >
                    <Text style={[styles.supportPillText, supportCategory === category && styles.supportPillTextActive]}>{formatSupportCategoryLabel(category)}</Text>
                  </Pressable>
                ))}
              </View>
              <View style={styles.supportPillRow}>
                {SUPPORT_PRIORITIES.map((priority) => (
                  <Pressable
                    key={priority}
                    style={[styles.supportPill, supportPriority === priority && styles.supportPillActive]}
                    onPress={() => setSupportPriority(priority)}
                  >
                    <Text style={[styles.supportPillText, supportPriority === priority && styles.supportPillTextActive]}>{formatSupportPriorityLabel(priority)}</Text>
                  </Pressable>
                ))}
              </View>
              <TextInput
                value={supportSubject}
                onChangeText={setSupportSubject}
                placeholder="عنوان الطلب"
                placeholderTextColor="#94a3b8"
                style={styles.supportInput}
              />
              <TextInput
                value={supportMessage}
                onChangeText={setSupportMessage}
                placeholder="اكتب ما حدث، رقم الرحلة أو التاريخ أو مشكلة الدفع"
                placeholderTextColor="#94a3b8"
                style={[styles.supportInput, styles.supportTextArea]}
                multiline
              />
              <Pressable
                style={[styles.primaryActionButton, supportSubmitting && styles.disabledActionButton]}
                disabled={supportSubmitting}
                onPress={() => {
                  void createSupportTicket();
                }}
              >
                <Text style={styles.primaryActionButtonText}>{supportSubmitting ? 'جاري الإرسال...' : 'إرسال الطلب'}</Text>
              </Pressable>
            </View>
            <View style={styles.supportPanel}>
              <View style={styles.sectionHeader}>
                <Text style={styles.supportPanelTitle}>سجل طلبات الدعم</Text>
                <Text style={styles.sectionBadge}>{supportTickets.length}</Text>
              </View>
              {supportTickets.length === 0 ? (
                <Text style={styles.emptyStateText}>لا توجد طلبات دعم بعد. أنشئ طلبًا من الأعلى عندما تحتاج للمساعدة.</Text>
              ) : null}
              {supportTickets.map((ticket) => {
                const expanded = expandedSupportTicketId === ticket.id;
                return (
                  <Pressable
                    key={ticket.id}
                    style={styles.supportTicketCard}
                    onPress={() => setExpandedSupportTicketId(expanded ? '' : ticket.id)}
                  >
                    <View style={styles.supportTicketHeader}>
                      <View style={styles.flexOne}>
                        <Text style={styles.supportTicketTitle}>{ticket.subject}</Text>
                        <Text style={styles.supportTicketMeta}>{formatSupportCategoryLabel(ticket.category)} | {formatSupportPriorityLabel(ticket.priority)} | {formatDate(ticket.createdAt)}</Text>
                      </View>
                      <Text style={styles.supportTicketStatus}>{formatSupportStatusLabel(ticket.status)}</Text>
                    </View>
                    {expanded ? (
                      <View style={styles.supportTicketDetails}>
                        <Text style={styles.supportTicketBody}>{ticket.message}</Text>
                        <Text style={styles.supportTicketMeta}>آخر تحديث {formatDate(ticket.updatedAt)}</Text>
                        {ticket.resolution ? <Text style={styles.supportTicketResolution}>الحل: {ticket.resolution}</Text> : null}
                      </View>
                    ) : null}
                  </Pressable>
                );
              })}
            </View>
            <View style={styles.focusActionRow}>
              <Pressable
                style={styles.secondaryActionButton}
                onPress={() => {
                  void openDialer('01050996940');
                }}
              >
                <Text style={styles.secondaryActionButtonText}>اتصال بالدعم</Text>
              </Pressable>
              <Pressable
                style={styles.primaryActionButton}
                onPress={async () => {
                  setNotificationPanelOpen(true);
                }}
              >
                <Text style={styles.primaryActionButtonText}>الإشعارات</Text>
              </Pressable>
            </View>
            {localPreferences.emergencyContactPhone ? (
              <Pressable
                style={styles.supportTicketCard}
                onPress={() => {
                  void openDialer(localPreferences.emergencyContactPhone);
                }}
              >
                <View style={styles.sectionHeader}>
                  <View style={styles.flexOne}>
                    <Text style={styles.supportTicketTitle}>جهة اتصال الطوارئ</Text>
                    <Text style={styles.supportTicketMeta}>{localPreferences.emergencyContactPhone}</Text>
                  </View>
                  <Text style={styles.sectionBadge}>اتصال</Text>
                </View>
              </Pressable>
            ) : null}
            {activeChatTripId ? (
              <PassengerTripChatPanel
                currentUserId={meUser?.id || null}
                messages={activeTripChatMessages}
                driverParticipant={activeTripChatParticipants?.driver || null}
                draft={chatDraft}
                sending={chatSendingTripId === activeChatTripId}
                onDraftChange={setChatDraft}
                onSend={() => {
                  void sendTripChatMessage();
                }}
              />
            ) : (
              <Text style={styles.emptyStateText}>ستظهر محادثة السائق هنا فور وجود رحلة نشطة مرتبطة بحسابك.</Text>
            )}
          </View>
          </>
        ) : null}

        {activeTab === 'settings' ? (
          <View style={styles.sectionCard}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>الإعدادات</Text>
              <Text style={styles.sectionBadge}>{settingsSaving ? 'جارٍ الحفظ' : 'مباشر'}</Text>
            </View>
            <Text style={styles.reservationMeta}>كل اختيار هنا يتم حفظه في حسابك ويظهر على الويب والتطبيقات عند تسجيل الدخول.</Text>
            <Text style={styles.supportPanelTitle}>اللغة</Text>
            <View style={[styles.supportPill, styles.supportPillActive]}>
              <Text style={[styles.supportPillText, styles.supportPillTextActive]}>العربية</Text>
            </View>
            <Text style={styles.reservationMeta}>واجهة التطبيق عربية بالكامل ومهيأة للقراءة من اليمين إلى اليسار.</Text>

            <Text style={styles.supportPanelTitle}>المظهر</Text>
            <View style={[styles.supportPill, styles.supportPillActive]}>
              <Text style={[styles.supportPillText, styles.supportPillTextActive]}>داكن عالي التباين</Text>
            </View>
            <Text style={styles.reservationMeta}>ألوان سوفت كار الحمراء والسوداء والبيضاء مطبقة مع تباين واضح للنصوص والأزرار.</Text>

            <Text style={styles.supportPanelTitle}>قنوات الإشعارات</Text>
            <Pressable style={styles.supportTicketCard} onPress={() => void toggleBiometricUnlock()}>
              <View style={styles.sectionHeader}>
                <View style={styles.flexOne}>
                  <Text style={styles.supportTicketTitle}>فتح آمن بالبصمة أو الوجه</Text>
                  <Text style={styles.supportTicketMeta}>يحمي الجلسة المحفوظة على هذا الهاتف ويستخدم قفل الجهاز نفسه.</Text>
                </View>
                <Text style={styles.sectionBadge}>{biometricEnabled ? 'مفعّل' : biometricAvailable ? 'متوقف' : 'غير متاح'}</Text>
              </View>
            </Pressable>
            <View style={styles.supportPanel}>
              {[
                { key: 'pushNotifications' as const, label: 'إشعارات التطبيق', hint: notificationStatusNote },
                { key: 'phoneNotifications' as const, label: 'تنبيهات الهاتف', hint: 'مكالمات أو رسائل عند الضرورة التشغيلية.' },
                { key: 'emailNotifications' as const, label: 'تنبيهات البريد', hint: 'نسخة من التذاكر والحجوزات المهمة.' },
              ].map((channel) => {
                const enabled = meUser?.[channel.key] !== false;
                return (
                  <Pressable
                    key={channel.key}
                    style={styles.supportTicketCard}
                    disabled={settingsSaving}
                    onPress={() => updateMobileSettings({ [channel.key]: !enabled } as Partial<MobileMePayload['user']>)}
                  >
                    <View style={styles.sectionHeader}>
                      <View style={styles.flexOne}>
                        <Text style={styles.supportTicketTitle}>{channel.label}</Text>
                        <Text style={styles.supportTicketMeta}>{channel.hint}</Text>
                      </View>
                      <Text style={styles.sectionBadge}>{enabled ? 'مفعّل' : 'متوقف'}</Text>
                    </View>
                  </Pressable>
                );
              })}
            </View>
            <View style={styles.supportPanel}>
              <View style={styles.sectionHeader}>
                <View style={styles.flexOne}>
                  <Text style={styles.supportPanelTitle}>تذكير موعد الرحلة</Text>
                  <Text style={styles.supportPanelText}>{reminderStatusNote}</Text>
                </View>
                <Text style={styles.sectionBadge}>
                  {localPreferences.tripRemindersEnabled ? 'مفعّل' : 'متوقف'}
                </Text>
              </View>
              <Pressable
                accessibilityRole="switch"
                accessibilityState={{ checked: localPreferences.tripRemindersEnabled }}
                style={[
                  styles.supportTicketCard,
                  localPreferences.tripRemindersEnabled && styles.supportPillActive,
                ]}
                onPress={() =>
                  void updateLocalPreferences({
                    ...localPreferences,
                    tripRemindersEnabled: !localPreferences.tripRemindersEnabled,
                  })
                }
              >
                <Text
                  style={[
                    styles.supportTicketTitle,
                    localPreferences.tripRemindersEnabled && styles.supportPillTextActive,
                  ]}
                >
                  {localPreferences.tripRemindersEnabled
                    ? 'إيقاف التذكير المحلي'
                    : 'تشغيل التذكير المحلي'}
                </Text>
                <Text
                  style={[
                    styles.supportTicketMeta,
                    localPreferences.tripRemindersEnabled && styles.supportPillTextActive,
                  ]}
                >
                  يعمل على الهاتف حتى إذا لم يكن التطبيق مفتوحًا، ولا يغيّر إشعارات الإدارة.
                </Text>
              </Pressable>
              {localPreferences.tripRemindersEnabled ? (
                <>
                  <Text style={styles.supportPanelText}>نبّهني قبل موعد الصعود بـ</Text>
                  <View style={styles.supportPillRow}>
                    {[15, 30, 60].map((minutes) => {
                      const selected = localPreferences.reminderLeadMinutes === minutes;
                      return (
                        <Pressable
                          key={minutes}
                          accessibilityRole="radio"
                          accessibilityState={{ selected }}
                          style={[styles.supportPill, selected && styles.supportPillActive]}
                          onPress={() =>
                            void updateLocalPreferences({
                              ...localPreferences,
                              reminderLeadMinutes: minutes,
                            })
                          }
                        >
                          <Text style={[styles.supportPillText, selected && styles.supportPillTextActive]}>
                            {minutes.toLocaleString('ar-EG')} دقيقة
                          </Text>
                        </Pressable>
                      );
                    })}
                  </View>
                </>
              ) : null}
            </View>
            <Pressable
              style={styles.supportTicketCard}
              onPress={() => {
                if (notificationPermissionStatus === 'denied') {
                  void openNotificationSettings();
                } else {
                  setNotificationPanelOpen(true);
                }
              }}
            >
              <View style={styles.sectionHeader}>
                <View style={styles.flexOne}>
                  <Text style={styles.supportTicketTitle}>حالة إذن الهاتف</Text>
                  <Text style={styles.supportTicketMeta}>
                    {notificationPermissionStatus === 'granted'
                      ? 'الهاتف يسمح بعرض التنبيهات. اضغط لفتح مركز الإشعارات.'
                      : notificationPermissionStatus === 'denied'
                        ? 'الإذن غير متاح. اضغط لفتح إعدادات الهاتف وتفعيله.'
                        : 'جارٍ التحقق من إعدادات الإشعارات على هذا الجهاز.'}
                  </Text>
                </View>
                <Text style={styles.sectionBadge}>
                  {notificationPermissionStatus === 'granted' ? 'مسموح' : notificationPermissionStatus === 'denied' ? 'متوقف' : 'فحص'}
                </Text>
              </View>
            </Pressable>
            <Pressable
              style={styles.supportTicketCard}
              onPress={() => void checkForAppUpdate()}
              disabled={updateChecking}
            >
              <View style={styles.sectionHeader}>
                <View style={styles.flexOne}>
                  <Text style={styles.supportTicketTitle}>تحديث التطبيق</Text>
                  <Text style={styles.supportTicketMeta}>{updateStatusNote}</Text>
                </View>
                <Text style={styles.sectionBadge}>{updateChecking ? 'جارٍ الفحص' : `الإصدار ${appConfig.expo.version}`}</Text>
              </View>
            </Pressable>
            <Pressable
              style={styles.supportTicketCard}
              onPress={confirmClearLocalCache}
              disabled={cacheBusy}
            >
              <View style={styles.sectionHeader}>
                <View style={styles.flexOne}>
                  <Text style={styles.supportTicketTitle}>البيانات المحفوظة على الهاتف</Text>
                  <Text style={styles.supportTicketMeta}>
                    {cacheSummary.tripCount} رحلة و{cacheSummary.reservationCount} حجز
                    {cacheSummary.lastUpdatedAt
                      ? ` · آخر تحديث ${new Date(cacheSummary.lastUpdatedAt).toLocaleString('ar-EG')}`
                      : ' · لا توجد بيانات مؤقتة'}
                  </Text>
                  <Text style={styles.supportTicketMeta}>اضغط لتنظيف النسخ المؤقتة وتنزيل بيانات حديثة بأمان.</Text>
                </View>
                <Text style={styles.sectionBadge}>{cacheBusy ? 'جارٍ التنظيف' : isOnline ? 'متصل' : 'غير متصل'}</Text>
              </View>
            </Pressable>
            <View style={styles.supportPanel}>
              <Text style={styles.supportPanelTitle}>السلامة وسهولة الاستخدام</Text>
              <Text style={styles.supportPanelText}>
                احفظ رقم شخص تثق به للاتصال السريع من صفحة الدعم، وتحكم في تقليل الحركة داخل شاشة الحجز.
              </Text>
              <TextInput
                value={localPreferences.emergencyContactPhone}
                onChangeText={(value) =>
                  setLocalPreferences((current) => ({
                    ...current,
                    emergencyContactPhone: value.replace(/[^\d+]/g, '').slice(0, 16),
                  }))
                }
                placeholder="رقم جهة اتصال الطوارئ"
                placeholderTextColor="#94a3b8"
                keyboardType="phone-pad"
                style={styles.supportInput}
              />
              <View style={styles.focusActionRow}>
                <Pressable
                  style={styles.secondaryActionButton}
                  onPress={() =>
                    void updateLocalPreferences(
                      localPreferences,
                      'تم حفظ جهة اتصال الطوارئ على هذا الهاتف.'
                    )
                  }
                >
                  <Text style={styles.secondaryActionButtonText}>حفظ الرقم</Text>
                </Pressable>
                <Pressable
                  style={[styles.secondaryActionButton, localPreferences.reduceMotion && styles.supportPillActive]}
                  onPress={() =>
                    void updateLocalPreferences({
                      ...localPreferences,
                      reduceMotion: !localPreferences.reduceMotion,
                    })
                  }
                >
                  <Text
                    style={[
                      styles.secondaryActionButtonText,
                      localPreferences.reduceMotion && styles.supportPillTextActive,
                    ]}
                  >
                    {localPreferences.reduceMotion ? 'الحركة المخففة مفعّلة' : 'تفعيل الحركة المخففة'}
                  </Text>
                </Pressable>
              </View>
            </View>
            <Text style={styles.reservationMeta}>الحالة الحالية: العربية، مظهر داكن عالي التباين.</Text>
            <AccountSecurityPanel token={token} />
          </View>
        ) : null}

        {activeTab === 'profile' ? (
          <>
          <View style={styles.sectionCard}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>الملف الشخصي</Text>
              <Text style={styles.sectionBadge}>الحساب</Text>
            </View>
            <Text style={styles.reservationMeta}>الاسم: {meUser?.name || '-'}</Text>
            <Text style={styles.reservationMeta}>البريد الإلكتروني: {meUser?.email || '-'}</Text>
            <Text style={styles.reservationMeta}>الهاتف: {meUser?.phone || '-'}</Text>
            <Text style={styles.reservationMeta}>نوع الحساب: راكب</Text>
            <View style={styles.benefitList}>
              {[
                { tab: 'history' as const, title: 'سجل الرحلات والمدفوعات', text: 'راجع كل الحجوزات والتذاكر والاستردادات.' },
                { tab: 'loyalty' as const, title: 'برنامج الولاء', text: 'شاهد نقاطك والمكافآت المؤهلة وسجل اكتسابها.' },
                { tab: 'support' as const, title: 'الدعم وخدمة العملاء', text: 'ابدأ محادثة أو افتح طلب دعم مرتبط بحسابك.' },
                { tab: 'settings' as const, title: 'الأمان والإعدادات', text: 'تحكم في الإشعارات والبصمة والجلسات النشطة.' },
              ].map((item) => (
                <Pressable key={item.tab} style={styles.benefitCard} onPress={() => setActiveTab(item.tab)}>
                  <Text style={styles.benefitTitle}>{item.title}</Text>
                  <Text style={styles.benefitText}>{item.text}</Text>
                </Pressable>
              ))}
            </View>
            <Pressable style={styles.signOutButton} onPress={handleLogout}>
              <Text style={styles.signOutButtonText}>تسجيل الخروج</Text>
            </Pressable>
          </View>
          </>
        ) : null}
      </ScrollView>

      <Modal visible={voucherBroadcastVisible && Boolean(activeVoucher)} transparent animationType="fade" onRequestClose={() => setVoucherBroadcastVisible(false)}>
        <View style={styles.voucherBroadcastRoot}>
          <View style={styles.voucherBroadcastCard}>
            <Pressable accessibilityRole="button" accessibilityLabel="إغلاق العرض" onPress={() => setVoucherBroadcastVisible(false)} style={styles.voucherBroadcastClose}>
              <Text style={styles.voucherBroadcastCloseText}>×</Text>
            </Pressable>
            {activeVoucher?.imageUrl ? (
              <Image source={{ uri: activeVoucher.imageUrl.startsWith('http') ? activeVoucher.imageUrl : `${apiBaseUrl}${activeVoucher.imageUrl}` }} style={styles.voucherBroadcastImage} />
            ) : (
              <Animated.View style={[styles.voucherBroadcastGift, { transform: [{ scale: voucherPulse.interpolate({ inputRange: [0, 1], outputRange: [1, 1.08] }) }] }]}>
                <Text style={styles.voucherBroadcastGiftText}>%</Text>
              </Animated.View>
            )}
            <View style={styles.voucherBroadcastBody}>
              <Text style={styles.voucherBroadcastEyebrow}>عرض جديد من SOFT CAR</Text>
              <Text style={styles.voucherBroadcastTitle}>{activeVoucher?.name}</Text>
              {activeVoucher?.description ? <Text style={styles.voucherBroadcastDescription}>{activeVoucher.description}</Text> : null}
              <View style={styles.voucherBroadcastCodeRow}>
                <View><Text style={styles.voucherBroadcastMeta}>كود القسيمة</Text><Text style={styles.voucherBroadcastCode}>{activeVoucher?.code}</Text></View>
                <View><Text style={styles.voucherBroadcastMeta}>يغلق خلال</Text><Text style={styles.voucherBroadcastSeconds}>{voucherBroadcastSeconds.toLocaleString('ar-EG')} ث</Text></View>
              </View>
              <Pressable
                style={styles.voucherBroadcastAction}
                onPress={() => {
                  if (activeVoucher) {
                    setPromotedVoucherCode(activeVoucher.code);
                    setVoucherCode(activeVoucher.code);
                    setActiveTab('reserve');
                  }
                  setVoucherBroadcastVisible(false);
                }}
              >
                <Text style={styles.voucherBroadcastActionText}>استخدم القسيمة في الحجز</Text>
              </Pressable>
              <Text style={styles.voucherBroadcastHint}>يمكنك الإغلاق الآن أو سيختفي العرض تلقائياً بعد 15 ثانية.</Text>
            </View>
          </View>
        </View>
      </Modal>

      <Modal
        visible={Boolean(reviewReservationId)}
        transparent
        animationType="fade"
        onRequestClose={() => {
          if (!reviewSubmitting) setReviewReservationId('');
        }}
      >
        <View style={styles.refundModalRoot}>
          <Pressable
            style={styles.refundModalBackdrop}
            onPress={() => {
              if (!reviewSubmitting) setReviewReservationId('');
            }}
          />
          <View style={styles.refundModalCard}>
            <Text style={styles.refundModalTitle}>تقييم الرحلة</Text>
            <Text style={styles.refundModalText}>يساعد تقييمك فريق التشغيل على تحسين الرحلات ومتابعة جودة الخدمة.</Text>
            <View style={styles.reviewStarsRow}>
              {[1, 2, 3, 4, 5].map((rating) => (
                <Pressable
                  key={rating}
                  style={[styles.reviewStarButton, reviewRating === rating && styles.reviewStarButtonActive]}
                  disabled={reviewSubmitting}
                  onPress={() => setReviewRating(rating)}
                >
                  <Text style={[styles.reviewStarText, reviewRating === rating && styles.reviewStarTextActive]}>
                    {rating.toLocaleString('ar-EG')}
                  </Text>
                </Pressable>
              ))}
            </View>
            <TextInput
              value={reviewBody}
              onChangeText={setReviewBody}
              placeholder="اكتب ملاحظتك عن الرحلة أو السائق (اختياري)"
              placeholderTextColor="#7F8A9A"
              multiline
              maxLength={1000}
              textAlignVertical="top"
              editable={!reviewSubmitting}
              style={styles.refundReasonInput}
            />
            <View style={styles.refundModalActions}>
              <Pressable
                style={styles.secondaryActionButton}
                disabled={reviewSubmitting}
                onPress={() => setReviewReservationId('')}
              >
                <Text style={styles.secondaryActionButtonText}>إلغاء</Text>
              </Pressable>
              <Pressable
                style={[styles.primaryActionButton, reviewSubmitting && styles.disabledActionButton]}
                disabled={reviewSubmitting}
                onPress={() => void submitReservationReview()}
              >
                {reviewSubmitting ? (
                  <ActivityIndicator color="#0A0A0A" />
                ) : (
                  <Text style={styles.primaryActionButtonText}>حفظ التقييم</Text>
                )}
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>

      <Modal
        visible={Boolean(refundReservationId)}
        transparent
        animationType="fade"
        onRequestClose={() => {
          if (!refundSubmitting) setRefundReservationId('');
        }}
      >
        <View style={styles.refundModalRoot}>
          <Pressable
            style={styles.refundModalBackdrop}
            onPress={() => {
              if (!refundSubmitting) setRefundReservationId('');
            }}
          />
          <View style={styles.refundModalCard}>
            <Text style={styles.refundModalTitle}>طلب استرداد</Text>
            <Text style={styles.refundModalText}>
              {refundScope === 'trip-group'
                ? 'سيتم إرسال طلب مالي لكل الأيام المدفوعة في هذه الرحلة.'
                : 'سيتم إرسال طلب مالي لهذا اليوم فقط.'}
            </Text>
            <TextInput
              value={refundReason}
              onChangeText={setRefundReason}
              placeholder="اكتب سبب الاسترداد بالتفصيل"
              placeholderTextColor="#7F8A9A"
              multiline
              textAlignVertical="top"
              editable={!refundSubmitting}
              style={styles.refundReasonInput}
            />
            <View style={styles.refundModalActions}>
              <Pressable
                style={styles.secondaryActionButton}
                disabled={refundSubmitting}
                onPress={() => setRefundReservationId('')}
              >
                <Text style={styles.secondaryActionButtonText}>إلغاء</Text>
              </Pressable>
              <Pressable
                style={[styles.primaryActionButton, refundSubmitting && styles.disabledActionButton]}
                disabled={refundSubmitting}
                onPress={() => void submitRefundRequest()}
              >
                <Text style={styles.primaryActionButtonText}>
                  {refundSubmitting ? 'جارٍ الإرسال...' : 'إرسال للمراجعة المالية'}
                </Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>

      <Modal
        visible={menuOpen}
        transparent
        animationType="fade"
        onRequestClose={() => setMenuOpen(false)}
      >
        <View style={styles.drawerRoot}>
          <Pressable style={styles.drawerBackdrop} onPress={() => setMenuOpen(false)} />
          <View style={styles.drawerPanel}>
            <View style={styles.drawerHeader}>
              <View>
                <Text style={styles.drawerEyebrow}>القائمة</Text>
                <Text style={styles.drawerTitle}>رحلات الراكب</Text>
                <Text style={styles.drawerSubtitle}>بدّل بين الحجز والسجل والإعدادات من قائمة جانبية واحدة.</Text>
              </View>
              <Pressable style={styles.drawerCloseButton} onPress={() => setMenuOpen(false)}>
                <Text style={styles.drawerCloseButtonText}>إغلاق</Text>
              </Pressable>
            </View>

            <ScrollView
              style={styles.drawerMenuScroll}
              contentContainerStyle={styles.drawerMenuList}
              showsVerticalScrollIndicator={false}
              keyboardShouldPersistTaps="handled"
            >
              {[
                { key: 'reserve' as const, label: 'الحجز', hint: 'ابحث عن الرحلات وافتح لوحة الحجز المركزة.' },
                { key: 'wallet' as const, label: 'المحفظة', hint: 'اشحن الرصيد وراجع الاستردادات ومدفوعات الحجز.' },
                { key: 'history' as const, label: 'السجل', hint: 'راجع التذاكر والحجوزات السابقة.' },
                { key: 'loyalty' as const, label: 'برنامج الولاء', hint: 'نقاطك، مستواك، ومزايا الرحلات المكتملة.' },
                { key: 'compliance' as const, label: 'الأمان والامتثال', hint: 'قواعد المحطات المعتمدة، التذاكر، والتنبيهات.' },
                { key: 'support' as const, label: 'الدعم', hint: 'الاتصال بالدعم وفتح دردشة الرحلة النشطة.' },
                { key: 'settings' as const, label: 'الإعدادات', hint: 'اللغة والمظهر والإشعارات.' },
                { key: 'profile' as const, label: 'حسابي', hint: 'بيانات الحساب وتسجيل الخروج.' },
              ].map((tabItem) => (
                <Pressable
                  key={tabItem.key}
                  style={[styles.drawerMenuButton, activeTab === tabItem.key && styles.drawerMenuButtonActive]}
                  accessibilityRole="button"
                  accessibilityState={{ selected: activeTab === tabItem.key }}
                  accessibilityLabel={`فتح صفحة ${tabItem.label}`}
                  onPress={() => openPassengerMenuTab(tabItem.key)}
                >
                  <Text style={[styles.drawerMenuButtonText, activeTab === tabItem.key && styles.drawerMenuButtonTextActive]}>{tabItem.label}</Text>
                  <Text style={[styles.drawerMenuHint, activeTab === tabItem.key && styles.drawerMenuHintActive]}>{tabItem.hint}</Text>
                </Pressable>
              ))}

              <Pressable
                style={styles.drawerMenuButton}
                onPress={async () => {
                  setMenuOpen(false);
                  setNotificationPanelOpen(true);
                }}
              >
                <Text style={styles.drawerMenuButtonText}>الإشعارات</Text>
                <Text style={styles.drawerMenuHint}>عرض آخر التحديثات والتنبيهات.</Text>
              </Pressable>

              <Pressable
                style={[styles.drawerMenuButton, styles.drawerDangerButton]}
                onPress={() => {
                  setMenuOpen(false);
                  void handleLogout();
                }}
              >
                <Text style={[styles.drawerMenuButtonText, styles.drawerDangerButtonText]}>تسجيل الخروج</Text>
                <Text style={[styles.drawerMenuHint, styles.drawerDangerHint]}>إنهاء الجلسة الحالية والعودة لتسجيل الدخول.</Text>
              </Pressable>
            </ScrollView>
          </View>
        </View>
      </Modal>

      <Modal
        visible={confirmationPanelOpen && Boolean(focusedPassengerConfirmation)}
        transparent
        animationType="fade"
        onRequestClose={() => setConfirmationPanelOpen(false)}
      >
        <View style={styles.confirmationOverlay}>
          <View style={styles.confirmationPanel}>
            <View style={styles.confirmationPanelHeader}>
              <View style={styles.confirmationPulse} />
              <View style={styles.confirmationPanelCopy}>
                <Text style={styles.confirmationEyebrow}>تأكيد مهم من السائق</Text>
                <Text style={styles.passengerConfirmationTitle}>
                  {focusedPassengerConfirmation?.type === 'CASH_COLLECTION'
                    ? 'هل دفعت قيمة الرحلة؟'
                    : focusedPassengerConfirmation?.type === 'BOARDING'
                      ? 'هل صعدت إلى السيارة؟'
                      : 'هل دفعت وصعدت إلى السيارة؟'}
                </Text>
                <Text style={styles.confirmationSubtitle}>
                  المحاولة {focusedPassengerConfirmation?.attemptNumber || 1} من {focusedPassengerConfirmation?.maxAttempts || 3}. أكد فقط إذا تم الإجراء فعلا.
                </Text>
              </View>
            </View>

            <View style={styles.confirmationTripCard}>
              <Text style={styles.confirmationTripName}>{focusedPassengerConfirmation?.trip.title || '-'}</Text>
              <Text style={styles.confirmationTripMeta}>موعد الرحلة: {formatDate(focusedPassengerConfirmation?.trip.startTime || null)}</Text>
              <Text style={styles.confirmationTripMeta}>
                من {focusedPassengerConfirmation?.reservation.pickupPoint?.name || '-'} إلى {focusedPassengerConfirmation?.reservation.dropoffPoint?.name || '-'}
              </Text>
            </View>

            <View style={styles.confirmationDetailsGrid}>
              <View style={styles.confirmationDetailBox}>
                <Text style={styles.confirmationDetailLabel}>السائق</Text>
                <Text style={styles.confirmationDetailValue}>{focusedPassengerConfirmation?.driver?.name || 'غير معين'}</Text>
                <Text style={styles.confirmationDetailHint}>
                  {focusedPassengerConfirmation?.driver?.carModel || '-'} {focusedPassengerConfirmation?.driver?.carPlateNumber || ''}
                </Text>
              </View>
              <View style={styles.confirmationDetailBox}>
                <Text style={styles.confirmationDetailLabel}>المبلغ</Text>
                <Text style={styles.confirmationDetailValue}>{formatMoney(focusedPassengerConfirmation?.requestedCashAmount || 0)}</Text>
                <Text style={styles.confirmationDetailHint}>{focusedPassengerConfirmation?.paymentMethod || '-'}</Text>
              </View>
            </View>

            <View style={styles.confirmationWarningBox}>
              <Text style={styles.confirmationWarningText}>
                إذا لم يحدث الدفع أو الصعود اضغط رفض. بعد ثلاث محاولات غير مؤكدة يتم فتح بلاغ تلقائي للإدارة لمراجعة السائق.
              </Text>
            </View>

            <View style={styles.confirmationActionRow}>
              <Pressable
                style={[styles.confirmationRejectButton, confirmationBusyId && styles.disabledActionButton]}
                disabled={Boolean(confirmationBusyId)}
                onPress={() => void respondToFocusedConfirmation('reject')}
              >
                <Text style={styles.confirmationRejectText}>
                  {confirmationBusyId ? 'جار الإرسال...' : 'لم يحدث ذلك'}
                </Text>
              </Pressable>
              <Pressable
                style={[styles.confirmationConfirmButton, confirmationBusyId && styles.disabledActionButton]}
                disabled={Boolean(confirmationBusyId)}
                onPress={() => void respondToFocusedConfirmation('confirm')}
              >
                <Text style={styles.confirmationConfirmText}>
                  {confirmationBusyId ? 'جار التأكيد...' : 'أؤكد الدفع والصعود'}
                </Text>
              </Pressable>
            </View>

            <Pressable style={styles.confirmationLaterButton} onPress={() => setConfirmationPanelOpen(false)}>
              <Text style={styles.confirmationLaterText}>الرد لاحقا من الإشعارات</Text>
            </Pressable>
          </View>
        </View>
      </Modal>

      <Modal
        visible={notificationPanelOpen}
        transparent
        animationType="slide"
        onRequestClose={() => setNotificationPanelOpen(false)}
      >
        <View style={styles.notificationModalRoot}>
          <View style={styles.notificationPanel}>
            <View style={styles.notificationPanelHeader}>
              <View>
                <Text style={styles.notificationPanelTitle}>الإشعارات</Text>
                <Text style={styles.notificationPanelMeta}>{notificationStatusNote}</Text>
              </View>
              <View style={styles.notificationHeaderActions}>
                <Pressable
                  style={styles.notificationRefreshButton}
                  disabled={notificationLoading}
                  onPress={() => {
                    if (token) void loadNotifications(token, false);
                  }}
                >
                  <Text style={styles.notificationRefreshButtonText}>
                    {notificationLoading ? 'جارٍ التحديث' : 'تحديث'}
                  </Text>
                </Pressable>
                <Pressable style={styles.modalCloseButton} onPress={() => setNotificationPanelOpen(false)}>
                  <Text style={styles.modalCloseButtonText}>إغلاق</Text>
                </Pressable>
              </View>
            </View>

            <View style={styles.notificationFilterRow}>
              {[
                { key: 'all' as const, label: 'الكل' },
                { key: 'unread' as const, label: 'غير مقروء' },
                { key: 'trip' as const, label: 'الرحلات' },
                { key: 'support' as const, label: 'الدعم' },
                { key: 'system' as const, label: 'النظام' },
              ].map((filterItem) => (
                <Pressable
                  key={filterItem.key}
                  style={[
                    styles.notificationFilterChip,
                    notificationFilter === filterItem.key && styles.notificationFilterChipActive,
                  ]}
                  onPress={() => setNotificationFilter(filterItem.key)}
                >
                  <Text
                    style={[
                      styles.notificationFilterText,
                      notificationFilter === filterItem.key && styles.notificationFilterTextActive,
                    ]}
                  >
                    {filterItem.label}
                  </Text>
                </Pressable>
              ))}
            </View>

            <TextInput
              value={notificationSearch}
              onChangeText={setNotificationSearch}
              placeholder="ابحث في عنوان الإشعار أو محتواه..."
              placeholderTextColor="#718096"
              style={styles.notificationSearchInput}
            />

            {focusedNotification ? (
              <View style={styles.notificationFocusCard}>
                <Text style={styles.notificationFocusEyebrow}>{formatNotificationTypeLabel(focusedNotification.type)}</Text>
                <Text style={styles.notificationFocusTitle}>{focusedNotification.title}</Text>
                <Text style={styles.notificationFocusBody}>{focusedNotification.message}</Text>
                <Text style={styles.notificationFocusTime}>{formatDate(focusedNotification.sentAt)}</Text>
                <View style={styles.notificationFocusActions}>
                  <Pressable style={styles.secondaryActionButton} onPress={() => setFocusedNotificationId('')}>
                    <Text style={styles.secondaryActionButtonText}>إغلاق التفاصيل</Text>
                  </Pressable>
                  <Pressable
                    style={[
                      styles.primaryActionButton,
                      !focusedNotification.actionUrl && styles.disabledActionButton,
                    ]}
                    disabled={!focusedNotification.actionUrl}
                    onPress={() => runNotificationAction(focusedNotification)}
                  >
                    <Text style={styles.primaryActionButtonText}>{getNotificationActionLabel(focusedNotification)}</Text>
                  </Pressable>
                </View>
                <View style={styles.notificationFocusActions}>
                  <Pressable
                    style={styles.notificationUtilityButton}
                    onPress={() => void markNotificationsRead([focusedNotification.id], !focusedNotification.readAt)}
                  >
                    <Text style={styles.notificationUtilityButtonText}>
                      {focusedNotification.readAt ? 'تعليم كغير مقروء' : 'تعليم كمقروء'}
                    </Text>
                  </Pressable>
                  <Pressable
                    style={[styles.notificationUtilityButton, styles.notificationDeleteButton]}
                    onPress={() => {
                      Alert.alert('حذف الإشعار', 'سيتم حذف هذا الإشعار من حسابك نهائيًا.', [
                        { text: 'إلغاء', style: 'cancel' },
                        {
                          text: 'حذف',
                          style: 'destructive',
                          onPress: () => void deleteNotifications([focusedNotification.id]),
                        },
                      ]);
                    }}
                  >
                    <Text style={[styles.notificationUtilityButtonText, styles.notificationDeleteButtonText]}>حذف</Text>
                  </Pressable>
                </View>
              </View>
            ) : null}

            <View style={styles.notificationBulkRow}>
              <Text style={styles.notificationBulkMeta}>
                {filteredNotifications.length} إشعار ظاهر · {unreadNotifications} غير مقروء
              </Text>
              <Pressable
                style={[styles.notificationMarkAllButton, unreadNotifications === 0 && styles.disabledActionButton]}
                disabled={unreadNotifications === 0}
                onPress={() => void markAllNotificationsRead()}
              >
                <Text style={styles.notificationMarkAllText}>تعليم الكل كمقروء</Text>
              </Pressable>
            </View>

            <ScrollView contentContainerStyle={styles.notificationList}>
              {filteredNotifications.length === 0 ? (
                <Text style={styles.emptyStateText}>لا توجد إشعارات حتى الآن.</Text>
              ) : (
                filteredNotifications.map((item) => (
                  <Pressable
                    key={item.id}
                    style={[
                      styles.notificationCard,
                      !item.readAt && styles.notificationCardUnread,
                      focusedNotificationId === item.id && styles.notificationCardFocused,
                    ]}
                    onPress={() => void openNotificationDetail(item)}
                  >
                    <View style={styles.notificationCardHeader}>
                      <Text style={styles.notificationCardTitle}>{item.title}</Text>
                      <Text style={styles.notificationCardTime}>{formatDate(item.sentAt)}</Text>
                    </View>
                    <Text style={styles.notificationCardBody}>{item.message}</Text>
                    <View style={styles.notificationCardFooter}>
                      <Text style={styles.notificationCardType}>{formatNotificationTypeLabel(item.type)}</Text>
                      <Text style={styles.notificationCardAction}>عرض التفاصيل</Text>
                    </View>
                  </Pressable>
                ))
              )}
              {notificationNextCursor ? (
                <Pressable
                  style={styles.notificationLoadMoreButton}
                  onPress={() => {
                    if (token) void loadNotifications(token, false, notificationNextCursor);
                  }}
                >
                  <Text style={styles.notificationLoadMoreText}>تحميل إشعارات أقدم</Text>
                </Pressable>
              ) : notifications.length > 0 ? (
                <Text style={styles.notificationEndText}>وصلت إلى نهاية سجل الإشعارات.</Text>
              ) : null}
            </ScrollView>
          </View>
        </View>
      </Modal>

      <Modal
        visible={reservationModalOpen}
        transparent
        animationType="fade"
        onRequestClose={() => setReservationModalOpen(false)}
      >
        <View style={styles.modalRoot}>
          <TripRouteMap
            points={orderedPoints}
            routePolyline={selectedTrip?.routePolyline}
            driver={selectedTripDriver}
            vehicleSeats={selectedTrip?.totalSeats ?? selectedTripDriver?.seatsAvailable ?? null}
            height={screenHeight}
            fullscreenRequestKey={reservationMapFullscreenRequest}
          />

          <View style={styles.modalTopBar}>
            <Text style={styles.modalTopTitle}>{selectedTrip?.title || 'مسار الرحلة'}</Text>
            <View style={styles.modalTopActions}>
              <Pressable style={styles.modalGhostButton} onPress={() => toggleDetailFocus()}>
                <Text style={styles.modalGhostButtonText}>{detailFocusMode ? 'عرض الخريطة' : 'تركيز التفاصيل'}</Text>
              </Pressable>
              <Pressable style={styles.modalCloseButton} onPress={() => setReservationModalOpen(false)}>
                <Text style={styles.modalCloseButtonText}>إغلاق</Text>
              </Pressable>
            </View>
          </View>

          <Animated.View style={[styles.bottomSheet, { transform: [{ translateY: sheetTranslate }] }]}>
            <View style={styles.sheetHandleZone} {...panResponder.panHandlers}>
              <Pressable
                style={styles.sheetHandlePressable}
                onPress={() => toggleDetailFocus()}
              >
                <View style={styles.sheetHandle} />
                <Text style={styles.sheetTitle}>مراجعة الحجز</Text>
                <Text style={styles.sheetHint}>{'\u0627\u0636\u063a\u0637 \u0647\u0646\u0627 \u0644\u062a\u0643\u0628\u064a\u0631 \u062a\u0641\u0627\u0635\u064a\u0644 \u0627\u0644\u0631\u062d\u0644\u0629'}</Text>
              </Pressable>
            </View>

            <ScrollView style={styles.sheetScroll} contentContainerStyle={styles.sheetContent}>
              {bookingRecoveryNote ? (
                <View style={styles.bookingRecoveryCard}>
                  <View style={styles.bookingRecoveryCopy}>
                    <Text style={styles.bookingRecoveryTitle}>تم استعادة حجزك</Text>
                    <Text style={styles.bookingRecoveryText}>{bookingRecoveryNote}</Text>
                  </View>
                  <Pressable style={styles.bookingRecoveryDismiss} onPress={() => setBookingRecoveryNote('')}>
                    <Text style={styles.bookingRecoveryDismissText}>حسنًا</Text>
                  </Pressable>
                </View>
              ) : null}
              <Pressable style={[styles.tripSummaryCard, detailFocusMode && styles.tripSummaryCardFocused]} onPress={() => toggleDetailFocus()}>
                <Text style={styles.tripSummaryTitle}>{selectedTrip?.title || '-'}</Text>
                <Text style={styles.tripSummaryMeta}>الانطلاق: {formatDate(selectedTrip?.startTime || null)}</Text>
                <Text style={styles.tripSummaryMeta}>الوصول: {formatDate(selectedTrip?.estimatedEndTime || null)}</Text>
                <Text style={styles.tripSummaryMeta}>السعر المتوقع: {previewedPriceLabel}</Text>
                <View style={styles.tripSummaryActionRow}>
                  <Text style={styles.tripSummaryActionText}>
                    {detailFocusMode ? 'اضغط لإعادة إبراز الخريطة.' : 'اضغط لتكبير تفاصيل الرحلة وتقليل تركيز الخريطة.'}
                  </Text>
                </View>
              </Pressable>

              <Text style={styles.inputLabel}>نقطة الصعود</Text>
              {renderDriverAssistCard(selectedTripDriver, 'سيتم تعيين السائق قريبًا')}
              <View style={styles.pointOptionList}>
                {pickupChoices.map((point) => (
                  <Pressable
                    key={point.id}
                    style={[styles.pointOptionCard, pickupPointId === point.id && styles.pointOptionCardActive]}
                    onPress={() => {
                      setPickupPointId(point.id);
                      const nextDrop = orderedPoints.find(
                        (candidate) => candidate.stopOrder > point.stopOrder && candidate.pointType !== 'PICKUP'
                      );
                      setDropoffPointId(nextDrop?.id || '');
                    }}
                  >
                    <View style={styles.pointOptionOrderWrap}>
                      <Text style={styles.pointOptionOrderText}>{point.stopOrder}</Text>
                    </View>
                    <View style={styles.pointOptionBody}>
                      <Text style={[styles.pointOptionTitle, pickupPointId === point.id && styles.pointOptionTitleActive]}>
                        {point.name}
                      </Text>
                      <Text style={[styles.pointOptionMeta, pickupPointId === point.id && styles.pointOptionMetaActive]}>
                        الوصول المتوقع {formatPointEta(selectedTrip?.startTime, point)}
                      </Text>
                    </View>
                  </Pressable>
                ))}
              </View>

              <Text style={styles.inputLabel}>نقطة النزول</Text>
              <View style={styles.pointOptionList}>
                {dropChoices.map((point) => (
                  <Pressable
                    key={point.id}
                    style={[styles.pointOptionCard, dropoffPointId === point.id && styles.pointOptionCardActive]}
                    onPress={() => setDropoffPointId(point.id)}
                  >
                    <View style={styles.pointOptionOrderWrap}>
                      <Text style={styles.pointOptionOrderText}>{point.stopOrder}</Text>
                    </View>
                    <View style={styles.pointOptionBody}>
                      <Text style={[styles.pointOptionTitle, dropoffPointId === point.id && styles.pointOptionTitleActive]}>
                        {point.name}
                      </Text>
                      <Text style={[styles.pointOptionMeta, dropoffPointId === point.id && styles.pointOptionMetaActive]}>
                        الوصول المتوقع {formatPointEta(selectedTrip?.startTime, point)}
                      </Text>
                    </View>
                  </Pressable>
                ))}
              </View>

              {roundTripBookingAvailable ? (
                <View style={styles.pricingPreviewCard}>
                  <View style={styles.pricingPreviewHeader}>
                    <Text style={styles.pricingPreviewTitle}>حجز ذهاب وعودة</Text>
                    <Text style={styles.tripSeatsBadge}>{formatMoney(roundTripFinalPrice)}</Text>
                  </View>
                  <Text style={styles.pricingPreviewHint}>
                    السعر قبل الضريبة {formatMoney(roundTripSubtotal)}، وضريبة التذاكر 14% {formatMoney(roundTripFinalPrice - roundTripSubtotal)}.
                  </Text>
                  <Pressable
                    style={[styles.choicePill, reserveRoundTrip && styles.choicePillActive, { alignSelf: 'flex-start' }]}
                    onPress={() => setReserveRoundTrip((current) => !current)}
                  >
                    <Text style={[styles.choicePillText, reserveRoundTrip && styles.choicePillTextActive]}>
                      {reserveRoundTrip ? 'تم اختيار الذهاب والعودة' : 'إضافة رحلة العودة للحجز'}
                    </Text>
                  </Pressable>
                  {reserveRoundTrip ? (
                    <>
                      <Text style={styles.inputLabel}>صعود العودة</Text>
                      <View style={styles.pointOptionList}>
                        {returnPickupChoices.map((point) => (
                          <Pressable
                            key={point.id}
                            style={[styles.pointOptionCard, returnPickupPointId === point.id && styles.pointOptionCardActive]}
                            onPress={() => {
                              setReturnPickupPointId(point.id);
                              const nextDrop = orderedReturnPoints.find(
                                (candidate) => candidate.stopOrder > point.stopOrder && candidate.pointType !== 'PICKUP'
                              );
                              setReturnDropoffPointId(nextDrop?.id || '');
                            }}
                          >
                            <View style={styles.pointOptionOrderWrap}>
                              <Text style={styles.pointOptionOrderText}>{point.stopOrder}</Text>
                            </View>
                            <View style={styles.pointOptionBody}>
                              <Text style={[styles.pointOptionTitle, returnPickupPointId === point.id && styles.pointOptionTitleActive]}>{point.name}</Text>
                              <Text style={[styles.pointOptionMeta, returnPickupPointId === point.id && styles.pointOptionMetaActive]}>
                                موعد العودة {formatPointEta(selectedReturnTrip?.startTime, point)}
                              </Text>
                            </View>
                          </Pressable>
                        ))}
                      </View>
                      <Text style={styles.inputLabel}>نزول العودة</Text>
                      <View style={styles.pointOptionList}>
                        {returnDropChoices.map((point) => (
                          <Pressable
                            key={point.id}
                            style={[styles.pointOptionCard, returnDropoffPointId === point.id && styles.pointOptionCardActive]}
                            onPress={() => setReturnDropoffPointId(point.id)}
                          >
                            <View style={styles.pointOptionOrderWrap}>
                              <Text style={styles.pointOptionOrderText}>{point.stopOrder}</Text>
                            </View>
                            <View style={styles.pointOptionBody}>
                              <Text style={[styles.pointOptionTitle, returnDropoffPointId === point.id && styles.pointOptionTitleActive]}>{point.name}</Text>
                              <Text style={[styles.pointOptionMeta, returnDropoffPointId === point.id && styles.pointOptionMetaActive]}>
                                الوصول المتوقع {formatPointEta(selectedReturnTrip?.startTime, point)}
                              </Text>
                            </View>
                          </Pressable>
                        ))}
                      </View>
                    </>
                  ) : null}
                </View>
              ) : null}

              <Text style={styles.inputLabel}>طريقة الدفع</Text>
              <View style={styles.pillsWrap}>
                {availablePaymentMethods.map((method) => (
                  <Pressable
                    key={method.value}
                    style={[styles.choicePill, paymentMethod === method.value && styles.choicePillActive]}
                    onPress={() => setPaymentMethod(method.value)}
                  >
                    <Text style={[styles.choicePillText, paymentMethod === method.value && styles.choicePillTextActive]}>
                      {paymentMethodDisplayLabel(method.value)}
                    </Text>
                  </Pressable>
                ))}
              </View>

              {repeatedTripBooking ? (
                <View style={styles.pricingPreviewCard}>
                  <View style={styles.pricingPreviewHeader}>
                    <Text style={styles.pricingPreviewTitle}>اختيار مواعيد الرحلة</Text>
                    <Text style={styles.tripSeatsBadge}>{selectedServiceDateKeys.length} محدد</Text>
                  </View>
                  <Text style={styles.pricingPreviewHint}>
                    {selectedDatesLabel || 'اختر مواعيد الرحلة المتكررة التي تريد حجزها.'}
                  </Text>
                  <View style={styles.pillsWrap}>
                    {serviceDateOptions.map((option) => {
                      const selected = selectedServiceDateKeys.includes(option.dateKey);
                      return (
                        <Pressable
                          key={option.dateKey}
                          style={[styles.choicePill, selected && styles.choicePillActive]}
                          onPress={() => toggleServiceDate(option.dateKey)}
                        >
                          <Text style={[styles.choicePillText, selected && styles.choicePillTextActive]}>
                            {new Date(option.startTime).toLocaleDateString('ar-EG', { month: 'short', day: 'numeric' })}
                          </Text>
                        </Pressable>
                      );
                    })}
                  </View>
                  {recommendedTier ? (
                    <View style={styles.tierRecommendationCard}>
                      <Text style={styles.tierRecommendationTitle}>
                        أضف {Math.max(0, Number(recommendedTier.durationDays || 0) - selectedServiceDateKeys.length)} موعد إضافي لفتح باقة {recommendedTier.name}
                      </Text>
                      <Text style={styles.pricingPreviewHint}>
                        المحدد الآن {selectedServiceDateKeys.length} - باقة {recommendedTier.durationDays} يوم - وفر {formatMoney(Math.max(0, Number(recommendedTier.originalPrice || 0) - Number(recommendedTier.packagePrice || 0)))}.
                      </Text>
                      <View style={styles.focusActionRow}>
                        <Pressable style={styles.secondaryActionButton} onPress={() => setSelectedTierId('')}>
                          <Text style={styles.secondaryActionButtonText}>متابعة بدون باقة</Text>
                        </Pressable>
                        <Pressable style={styles.primaryActionButton} onPress={() => applyRecommendedTier(recommendedTier)}>
                          <Text style={styles.primaryActionButtonText}>تطبيق الباقة</Text>
                        </Pressable>
                      </View>
                    </View>
                  ) : null}
                </View>
              ) : null}

              {paymentMethod === 'WALLET' ? (
                <View style={styles.walletProofCard}>
                  <Text style={styles.walletProofTitle}>الدفع من المحفظة</Text>
                  <Text style={styles.walletProofMeta}>
                    الرصيد المتاح: {formatMoney(walletData?.account?.balance ?? walletData?.wallet?.balance ?? 0)}
                  </Text>
                  <Text style={styles.walletProofText}>
                    سيتم خصم قيمة الحجز مباشرة من رصيد محفظتك عند تأكيد الحجز. في حالة الاسترداد المعتمد ستعود القيمة إلى المحفظة تلقائيا.
                  </Text>
                  <Pressable
                    style={styles.secondaryActionButton}
                    onPress={() => {
                      setReservationModalOpen(false);
                      setActiveTab('wallet');
                    }}
                  >
                    <Text style={styles.secondaryActionButtonText}>فتح المحفظة للشحن</Text>
                  </Pressable>
                </View>
              ) : null}

              <Text style={styles.inputLabel}>اختيار المقعد</Text>
              <View style={styles.pillsWrap}>
                {availableSeats.length === 0 ? (
                  <Text style={styles.emptyStateText}>لا توجد مقاعد متاحة لهذه الرحلة.</Text>
                ) : (
                  availableSeats.map((seat) => (
                    <Pressable
                      key={seat}
                      style={[styles.choicePill, selectedSeat === seat && styles.choicePillActive]}
                      onPress={() => setSelectedSeat(seat)}
                    >
                      <Text style={[styles.choicePillText, selectedSeat === seat && styles.choicePillTextActive]}>
                        {seat}
                      </Text>
                    </Pressable>
                  ))
                )}
              </View>

              {availableReservationTiers.length > 0 ? (
                <>
                  <Text style={styles.inputLabel}>Package tier</Text>
                  <View style={styles.pillsWrap}>
                    <Pressable
                      style={[styles.choicePill, !selectedTierId && styles.choicePillActive]}
                      onPress={() => setSelectedTierId('')}
                    >
                      <Text style={[styles.choicePillText, !selectedTierId && styles.choicePillTextActive]}>
                        Standard ride
                      </Text>
                    </Pressable>
                    {availableReservationTiers.slice(0, 6).map((tier) => {
                      const selected = selectedTierId === tier.id;
                      return (
                        <Pressable
                          key={tier.id}
                          style={[styles.choicePill, selected && styles.choicePillActive]}
                          onPress={() => setSelectedTierId(tier.id)}
                        >
                          <Text style={[styles.choicePillText, selected && styles.choicePillTextActive]}>
                            {tier.name} - {formatMoney(tier.packagePrice)}
                          </Text>
                        </Pressable>
                      );
                    })}
                  </View>
                  {selectedTier ? (
                    <View style={styles.pricingPreviewCard}>
                      <Text style={styles.pricingPreviewTitle}>{selectedTier.name}</Text>
                      <Text style={styles.pricingPreviewHint}>
                        باقة {selectedTier.durationDays} يوم. الأيام المستبعدة: {selectedTier.excludedWeekdays.length ? selectedTier.excludedWeekdays.join(', ') : 'لا يوجد'}.
                      </Text>
                      {selectedTier.cancellationPolicy ? (
                        <Text style={styles.pricingPreviewHint}>{selectedTier.cancellationPolicy}</Text>
                      ) : null}
                    </View>
                  ) : null}
                </>
              ) : null}

              <View style={styles.pricingPreviewCard}>
                <View style={styles.pricingPreviewHeader}>
                  <Text style={styles.pricingPreviewTitle}>قسيمة الخصم</Text>
                  {voucherQuote ? <Text style={styles.tripSeatsBadge}>تم التطبيق</Text> : null}
                </View>
                <Text style={styles.pricingPreviewHint}>أدخل كود القسيمة وسيحسب الخادم الخصم والسعر النهائي بأمان قبل الحجز.</Text>
                <View style={styles.voucherInputRow}>
                  <TextInput
                    value={voucherCode}
                    onChangeText={(value) => {
                      setVoucherCode(value.toUpperCase().replace(/\s+/g, ''));
                      setVoucherQuote(null);
                      setVoucherError('');
                    }}
                    autoCapitalize="characters"
                    placeholder="مثال: SOFTCAR20"
                    placeholderTextColor="#7f93ad"
                    style={[styles.searchInput, styles.voucherInput]}
                  />
                  <Pressable
                    style={[styles.secondaryActionButton, voucherLoading && styles.disabledActionButton]}
                    onPress={() => void validateVoucherCode()}
                    disabled={voucherLoading}
                  >
                    <Text style={styles.secondaryActionButtonText}>{voucherLoading ? 'جارٍ الفحص...' : 'تطبيق'}</Text>
                  </Pressable>
                </View>
                {voucherError ? <Text style={styles.pricingPreviewError}>{voucherError}</Text> : null}
                {voucherQuote ? (
                  <View style={styles.pricingPreviewGrid}>
                    <View style={styles.pricingPreviewMetric}>
                      <Text style={styles.pricingPreviewLabel}>القسيمة</Text>
                      <Text style={styles.pricingPreviewValue}>{voucherQuote.voucher.name}</Text>
                    </View>
                    <View style={styles.pricingPreviewMetric}>
                      <Text style={styles.pricingPreviewLabel}>التوفير</Text>
                      <Text style={styles.pricingPreviewValue}>{formatMoney(voucherQuote.discountAmount)}</Text>
                    </View>
                    <View style={styles.pricingPreviewMetric}>
                      <Text style={styles.pricingPreviewLabel}>الإجمالي الجديد</Text>
                      <Text style={styles.pricingPreviewValue}>{formatMoney(voucherQuote.finalPrice)}</Text>
                    </View>
                  </View>
                ) : null}
              </View>

              <View style={styles.pricingPreviewCard}>
                <View style={styles.pricingPreviewHeader}>
                  <Text style={styles.pricingPreviewTitle}>سعر المسار قبل الحجز</Text>
                  {pricingLoading ? <ActivityIndicator size="small" color="#FCA5A5" /> : null}
                </View>
                {pricingError ? (
                  <Text style={styles.pricingPreviewError}>{pricingError}</Text>
                ) : pricingPreview ? (
                  <View style={styles.pricingPreviewGrid}>
                    <View style={styles.pricingPreviewMetric}>
                      <Text style={styles.pricingPreviewLabel}>السعر النهائي</Text>
                      <Text style={styles.pricingPreviewValue}>{formatMoney(pricingPreview.finalPrice)}</Text>
                      <Text style={styles.pricingPreviewHint}>يشمل ضريبة 14%: {formatMoney(pricingPreview.taxAmount || 0)}</Text>
                    </View>
                    <View style={styles.pricingPreviewMetric}>
                      <Text style={styles.pricingPreviewLabel}>مدة المسار</Text>
                      <Text style={styles.pricingPreviewValue}>{pricingPreview.durationMin} دقيقة</Text>
                    </View>
                    <View style={styles.pricingPreviewMetric}>
                      <Text style={styles.pricingPreviewLabel}>موعد الصعود</Text>
                      <Text style={styles.pricingPreviewValue}>{formatDate(pricingPreview.boardingTime || null)}</Text>
                    </View>
                    <View style={styles.pricingPreviewMetric}>
                      <Text style={styles.pricingPreviewLabel}>موعد الوصول</Text>
                      <Text style={styles.pricingPreviewValue}>{formatDate(pricingPreview.arrivalTime || null)}</Text>
                    </View>
                  </View>
                ) : (
                  <Text style={styles.pricingPreviewHint}>اختر نقطة الصعود والنزول حتى يظهر السعر الدقيق لهذا المسار.</Text>
                )}
              </View>

              <View style={styles.confirmationCard}>
                <Text style={styles.confirmationTitle}>تأكيد التفاصيل</Text>
                <Text style={styles.confirmationText}>
                  الصعود: {orderedPoints.find((point) => point.id === pickupPointId)?.name || '-'}
                </Text>
                <Text style={styles.confirmationText}>
                  النزول: {orderedPoints.find((point) => point.id === dropoffPointId)?.name || '-'}
                </Text>
                {reserveRoundTrip ? (
                  <>
                    <Text style={styles.confirmationText}>
                      صعود العودة: {orderedReturnPoints.find((point) => point.id === returnPickupPointId)?.name || '-'}
                    </Text>
                    <Text style={styles.confirmationText}>
                      نزول العودة: {orderedReturnPoints.find((point) => point.id === returnDropoffPointId)?.name || '-'}
                    </Text>
                  </>
                ) : null}
                <Text style={styles.confirmationText}>المقعد: {selectedSeat || '-'}</Text>
                <Text style={styles.confirmationText}>الدفع: {formatPaymentMethodLabel(paymentMethod)}</Text>
                <Text style={styles.confirmationText}>السعر قبل التأكيد: {previewedPriceLabel}</Text>
              </View>

              <Pressable
                style={[styles.reserveButton, (loading || pricingLoading || Boolean(pricingError)) && styles.disabledActionButton]}
                onPress={handleReserve}
                disabled={loading || pricingLoading || Boolean(pricingError)}
              >
                <Text style={styles.reserveButtonText}>{loading ? 'جارٍ تنفيذ الحجز...' : reserveRoundTrip ? 'تأكيد حجز الذهاب والعودة' : 'تأكيد الحجز'}</Text>
              </Pressable>
            </ScrollView>
          </Animated.View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

type PassengerAppBoundaryState = {
  error: Error | null;
  resetKey: number;
};

class PassengerAppBoundary extends React.Component<Record<string, never>, PassengerAppBoundaryState> {
  state: PassengerAppBoundaryState = {
    error: null,
    resetKey: 0,
  };

  static getDerivedStateFromError(error: Error): PassengerAppBoundaryState {
    return { error, resetKey: 0 };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('[passenger-app] render failure', error, info.componentStack);
  }

  private restart = () => {
    this.setState((current) => ({
      error: null,
      resetKey: current.resetKey + 1,
    }));
  };

  private resetSession = async () => {
    await clearStoredToken().catch(() => undefined);
    this.restart();
  };

  render() {
    if (!this.state.error) {
      return <PassengerApp key={this.state.resetKey} />;
    }

    return (
      <SafeAreaView style={styles.crashScreen}>
        <StatusBar style="light" />
        <View style={styles.crashCard}>
          <Text style={styles.crashBadge}>SOFT CAR</Text>
          <Text style={styles.crashTitle}>تعذر فتح الصفحة</Text>
          <Text style={styles.crashMessage}>
            تم إيقاف الجزء المتعثر لحماية التطبيق. أعد المحاولة، وإذا استمرت المشكلة سجّل الدخول من جديد.
          </Text>
          <Pressable style={styles.crashPrimaryButton} onPress={this.restart}>
            <Text style={styles.crashPrimaryButtonText}>إعادة المحاولة</Text>
          </Pressable>
          <Pressable style={styles.crashSecondaryButton} onPress={() => void this.resetSession()}>
            <Text style={styles.crashSecondaryButtonText}>العودة إلى تسجيل الدخول</Text>
          </Pressable>
        </View>
      </SafeAreaView>
    );
  }
}

export default function App() {
  return <PassengerAppBoundary />;
}

const styles = StyleSheet.create({
  voucherBroadcastRoot: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.78)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 18,
  },
  voucherBroadcastCard: {
    width: '100%',
    maxWidth: 420,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#7f1d1d',
    backgroundColor: '#090909',
    overflow: 'hidden',
  },
  voucherBroadcastClose: {
    position: 'absolute',
    zIndex: 4,
    left: 10,
    top: 10,
    width: 40,
    height: 40,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.22)',
    backgroundColor: 'rgba(0,0,0,0.72)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  voucherBroadcastCloseText: { color: '#ffffff', fontSize: 25, lineHeight: 27, fontWeight: '700' },
  voucherBroadcastImage: { width: '100%', height: 180, backgroundColor: '#151515' },
  voucherBroadcastGift: { height: 160, alignItems: 'center', justifyContent: 'center', backgroundColor: '#210606' },
  voucherBroadcastGiftText: { color: '#ef4444', fontSize: 64, fontWeight: '900' },
  voucherBroadcastBody: { padding: 18, gap: 8 },
  voucherBroadcastEyebrow: { color: '#fca5a5', fontSize: 11, fontWeight: '900', textAlign: 'right' },
  voucherBroadcastTitle: { color: '#ffffff', fontSize: 24, fontWeight: '900', textAlign: 'right' },
  voucherBroadcastDescription: { color: '#cbd5e1', fontSize: 12, lineHeight: 20, textAlign: 'right' },
  voucherBroadcastCodeRow: { marginTop: 5, flexDirection: 'row-reverse', alignItems: 'center', justifyContent: 'space-between', borderWidth: 1, borderColor: '#292929', backgroundColor: '#111111', borderRadius: 8, padding: 12 },
  voucherBroadcastMeta: { color: '#8f8f97', fontSize: 10, fontWeight: '800', textAlign: 'right' },
  voucherBroadcastCode: { color: '#fca5a5', fontSize: 18, fontWeight: '900', marginTop: 3 },
  voucherBroadcastSeconds: { color: '#ffffff', fontSize: 17, fontWeight: '900', marginTop: 3, textAlign: 'left' },
  voucherBroadcastAction: { minHeight: 50, borderRadius: 8, backgroundColor: '#dc2626', alignItems: 'center', justifyContent: 'center', marginTop: 5, paddingHorizontal: 12 },
  voucherBroadcastActionText: { color: '#ffffff', fontSize: 14, fontWeight: '900' },
  voucherBroadcastHint: { color: '#6b7280', fontSize: 10, lineHeight: 16, textAlign: 'center' },
  crashScreen: {
    flex: 1,
    backgroundColor: '#050505',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 22,
  },
  crashCard: {
    width: '100%',
    maxWidth: 420,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#3f1717',
    backgroundColor: '#111111',
    padding: 22,
    gap: 14,
  },
  crashBadge: {
    color: '#ef4444',
    fontSize: 13,
    fontWeight: '900',
    textAlign: 'center',
  },
  crashTitle: {
    color: '#ffffff',
    fontSize: 24,
    fontWeight: '900',
    textAlign: 'center',
  },
  crashMessage: {
    color: '#d1d5db',
    fontSize: 14,
    lineHeight: 22,
    textAlign: 'center',
    writingDirection: 'rtl',
  },
  crashPrimaryButton: {
    minHeight: 50,
    borderRadius: 12,
    backgroundColor: '#dc2626',
    alignItems: 'center',
    justifyContent: 'center',
  },
  crashPrimaryButtonText: {
    color: '#ffffff',
    fontSize: 15,
    fontWeight: '900',
  },
  crashSecondaryButton: {
    minHeight: 48,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#4b5563',
    alignItems: 'center',
    justifyContent: 'center',
  },
  crashSecondaryButtonText: {
    color: '#e5e7eb',
    fontSize: 14,
    fontWeight: '800',
  },
  networkNotice: {
    borderWidth: 1,
    borderColor: '#7F1D1D',
    backgroundColor: '#240B0B',
    paddingHorizontal: 14,
    paddingVertical: 11,
    borderRadius: 10,
  },
  networkNoticeText: {
    color: '#FECACA',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
    writingDirection: 'rtl',
  },
  bookingRecoveryCard: {
    borderWidth: 1,
    borderColor: '#166534',
    backgroundColor: '#071A10',
    borderRadius: 10,
    padding: 12,
    flexDirection: 'row-reverse',
    alignItems: 'center',
    gap: 10,
  },
  bookingRecoveryCopy: {
    flex: 1,
    gap: 3,
  },
  bookingRecoveryTitle: {
    color: '#BBF7D0',
    fontSize: 13,
    fontWeight: '900',
    textAlign: 'right',
  },
  bookingRecoveryText: {
    color: '#D1FAE5',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
    writingDirection: 'rtl',
  },
  bookingRecoveryDismiss: {
    minHeight: 38,
    minWidth: 60,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#22C55E',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 10,
  },
  bookingRecoveryDismissText: {
    color: '#DCFCE7',
    fontSize: 12,
    fontWeight: '900',
  },
  refundStatusCard: {
    borderWidth: 1,
    borderColor: '#7F1D1D',
    backgroundColor: '#1D0B0B',
    borderRadius: 10,
    padding: 12,
    gap: 4,
    marginTop: 10,
  },
  refundStatusTitle: {
    color: '#FECACA',
    fontSize: 13,
    fontWeight: '800',
    textAlign: 'right',
  },
  refundStatusText: {
    color: '#CBD5E1',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'right',
  },
  refundRequestButton: {
    minHeight: 42,
    borderRadius: 9,
    borderWidth: 1,
    borderColor: '#D32F2F',
    backgroundColor: '#240B0B',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 14,
    marginTop: 10,
  },
  refundRequestButtonText: {
    color: '#FECACA',
    fontSize: 12,
    fontWeight: '800',
  },
  reviewActionButton: {
    minHeight: 36,
    borderRadius: 9,
    borderWidth: 1,
    borderColor: '#F59E0B',
    backgroundColor: '#211704',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 11,
    paddingVertical: 7,
  },
  reviewActionButtonText: {
    color: '#FDE68A',
    fontSize: 11,
    fontWeight: '900',
  },
  reviewStarsRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 8,
  },
  reviewStarButton: {
    width: 48,
    height: 48,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: '#111111',
    alignItems: 'center',
    justifyContent: 'center',
  },
  reviewStarButtonActive: {
    borderColor: '#F59E0B',
    backgroundColor: '#F59E0B',
  },
  reviewStarText: {
    color: '#CBD5E1',
    fontSize: 17,
    fontWeight: '900',
  },
  reviewStarTextActive: {
    color: '#0A0A0A',
  },
  refundModalRoot: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 18,
  },
  refundModalBackdrop: {
    position: 'absolute',
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.78)',
  },
  refundModalCard: {
    width: '100%',
    maxWidth: 520,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#3B1B1B',
    backgroundColor: '#0A0A0A',
    padding: 16,
    gap: 12,
  },
  refundModalTitle: {
    color: '#F8FAFC',
    fontSize: 22,
    fontWeight: '900',
    textAlign: 'right',
  },
  refundModalText: {
    color: '#94A3B8',
    fontSize: 13,
    lineHeight: 20,
    textAlign: 'right',
  },
  refundReasonInput: {
    minHeight: 120,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    color: '#F8FAFC',
    padding: 12,
    textAlign: 'right',
    writingDirection: 'rtl',
  },
  refundModalActions: {
    flexDirection: 'row',
    gap: 10,
  },
  booting: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#040914',
    gap: 10,
  },
  bootingText: {
    color: '#cbd5e1',
    fontSize: 14,
  },
  loginContainer: {
    flex: 1,
    backgroundColor: '#040914',
    padding: 16,
    justifyContent: 'center',
  },
  loginHero: {
    marginBottom: 18,
    gap: 6,
  },
  loginEyebrow: {
    color: '#FCA5A5',
    fontWeight: '700',
    fontSize: 11,
    letterSpacing: 1.8,
  },
  loginTitle: {
    color: '#f8fafc',
    fontSize: 33,
    fontWeight: '800',
  },
  loginSubtitle: {
    color: '#94a3b8',
    fontSize: 14,
    lineHeight: 20,
  },
  loginFeatureRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 8,
  },
  loginFeaturePill: {
    minHeight: 36,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#1d4f63',
    backgroundColor: '#050505',
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loginFeaturePillText: {
    color: '#d5fbff',
    fontSize: 12,
    fontWeight: '700',
  },
  loginCard: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#1f2e46',
    backgroundColor: '#0A0A0A',
    padding: 14,
    gap: 10,
  },
  authModeSwitch: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 4,
  },
  authModeButton: {
    flex: 1,
    minHeight: 40,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#0e1a31',
    alignItems: 'center',
    justifyContent: 'center',
  },
  authModeButtonActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#D32F2F',
  },
  authModeButtonText: {
    color: '#cbd5e1',
    fontWeight: '700',
    fontSize: 12,
  },
  authModeButtonTextActive: {
    color: '#ecfeff',
  },
  loginInput: {
    minHeight: 48,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#0e1a31',
    paddingHorizontal: 12,
    color: '#f8fafc',
    textAlign: 'right',
    writingDirection: 'rtl',
  },
  passwordInputWrap: {
    position: 'relative',
    justifyContent: 'center',
  },
  passwordTextInput: {
    paddingLeft: 86,
  },
  passwordToggle: {
    position: 'absolute',
    left: 8,
    top: 6,
    bottom: 6,
    minWidth: 66,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(211, 47, 47, 0.36)',
    backgroundColor: 'rgba(211, 47, 47, 0.16)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  passwordToggleText: {
    color: '#ffffff',
    fontSize: 12,
    fontWeight: '900',
  },
  loginButton: {
    minHeight: 48,
    borderRadius: 12,
    backgroundColor: '#D32F2F',
    alignItems: 'center',
    justifyContent: 'center',
  },
  loginButtonDisabled: {
    opacity: 0.55,
  },
  loginButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '800',
  },
  otpHeader: {
    alignItems: 'center',
    gap: 8,
    paddingVertical: 6,
  },
  otpIconCircle: {
    width: 76,
    height: 76,
    borderRadius: 38,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(211, 47, 47, 0.45)',
    backgroundColor: 'rgba(211, 47, 47, 0.14)',
  },
  otpIconText: {
    color: '#ffffff',
    fontSize: 24,
    fontWeight: '900',
    letterSpacing: 3,
  },
  otpTitle: {
    color: '#ffffff',
    fontSize: 24,
    fontWeight: '900',
    textAlign: 'center',
  },
  otpSubtitle: {
    color: '#cbd5e1',
    fontSize: 13,
    lineHeight: 21,
    textAlign: 'center',
  },
  otpInput: {
    minHeight: 62,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#D32F2F',
    backgroundColor: '#181818',
    color: '#ffffff',
    fontSize: 28,
    fontWeight: '900',
    letterSpacing: 12,
    textAlign: 'center',
    writingDirection: 'ltr',
  },
  otpHint: {
    color: '#94a3b8',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'center',
  },
  otpStatusBox: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#334155',
    backgroundColor: '#111827',
    padding: 12,
  },
  otpStatusBoxSuccess: {
    borderColor: '#16a34a',
    backgroundColor: 'rgba(22, 163, 74, 0.12)',
  },
  otpStatusBoxError: {
    borderColor: '#ef4444',
    backgroundColor: 'rgba(239, 68, 68, 0.12)',
  },
  otpStatusText: {
    color: '#dbeafe',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'center',
  },
  otpStatusTextSuccess: {
    color: '#bbf7d0',
  },
  otpStatusTextError: {
    color: '#fecaca',
  },
  otpTimerCard: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#262626',
    backgroundColor: '#111111',
    padding: 12,
    gap: 10,
  },
  otpTimerHeader: {
    flexDirection: 'row-reverse',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 10,
  },
  otpTimerLabel: {
    color: '#cbd5e1',
    fontSize: 12,
    fontWeight: '700',
  },
  otpTimerValue: {
    color: '#ffffff',
    fontSize: 12,
    fontWeight: '900',
  },
  otpTimerTrack: {
    height: 7,
    borderRadius: 999,
    overflow: 'hidden',
    backgroundColor: '#262626',
  },
  otpTimerFill: {
    height: '100%',
    borderRadius: 999,
    backgroundColor: '#D32F2F',
  },
  otpSecondaryButton: {
    minHeight: 46,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#181818',
    alignItems: 'center',
    justifyContent: 'center',
  },
  otpSecondaryButtonDisabled: {
    opacity: 0.5,
  },
  otpSecondaryButtonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '800',
  },
  otpEditButton: {
    minHeight: 42,
    alignItems: 'center',
    justifyContent: 'center',
  },
  otpEditButtonText: {
    color: '#94a3b8',
    fontSize: 13,
    fontWeight: '800',
  },
  policyCheckRow: {
    minHeight: 54,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#0e1a31',
    padding: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  policyCheckRowActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#0b2f34',
  },
  policyCheckBox: {
    width: 24,
    height: 24,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#64748b',
    alignItems: 'center',
    justifyContent: 'center',
  },
  policyCheckBoxActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#D32F2F',
  },
  policyCheckMark: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '900',
  },
  policyCheckText: {
    flex: 1,
    color: '#cbd5e1',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'right',
  },
  container: {
    flex: 1,
    backgroundColor: '#030813',
  },
  scrollContent: {
    padding: 14,
    paddingBottom: 36,
    gap: 12,
  },
  heroCard: {
    borderRadius: 20,
    borderWidth: 1,
    borderColor: '#164e63',
    backgroundColor: '#0b1328',
    padding: 14,
    gap: 4,
  },
  heroTopRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 12,
  },
  heroTopCopy: {
    flex: 1,
    gap: 4,
  },
  heroActionColumn: {
    gap: 10,
    alignItems: 'center',
  },
  heroEyebrow: {
    color: '#FCA5A5',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1.8,
  },
  heroTitle: {
    color: '#f8fafc',
    fontSize: 25,
    fontWeight: '800',
  },
  heroMeta: {
    color: '#94a3b8',
    fontSize: 12,
    marginTop: 2,
  },
  notificationBellButton: {
    width: 86,
    minHeight: 86,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#1f7a8c',
    backgroundColor: '#091a2e',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 8,
    paddingVertical: 10,
    gap: 4,
  },
  notificationBellIcon: {
    color: '#d5fbff',
    fontSize: 12,
    fontWeight: '800',
  },
  notificationBellLabel: {
    color: '#e2e8f0',
    fontSize: 12,
    fontWeight: '700',
  },
  notificationBellBadge: {
    minWidth: 24,
    height: 24,
    borderRadius: 999,
    backgroundColor: '#D32F2F',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 6,
  },
  notificationBellBadgeText: {
    color: '#ffffff',
    fontSize: 12,
    fontWeight: '800',
  },
  menuButton: {
    width: 64,
    minHeight: 64,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#1f7a8c',
    backgroundColor: '#091a2e',
    alignItems: 'center',
    justifyContent: 'center',
  },
  menuButtonIcon: {
    color: '#f8fafc',
    fontSize: 24,
    fontWeight: '800',
  },
  currentTripCard: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#1b6a7a',
    backgroundColor: '#0a1f2c',
    paddingHorizontal: 12,
    paddingVertical: 10,
    gap: 4,
  },
  currentTripHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 8,
  },
  currentTripTitle: {
    color: '#e2e8f0',
    fontSize: 16,
    fontWeight: '800',
  },
  currentTripStatus: {
    color: '#99f6e4',
    fontSize: 11,
    fontWeight: '800',
  },
  currentTripRoute: {
    color: '#f8fafc',
    fontSize: 18,
    fontWeight: '800',
  },
  currentTripMeta: {
    color: '#cbd5e1',
    fontSize: 13,
    textAlign: 'right',
  },
  currentTripTicketRow: {
    marginTop: 4,
    paddingTop: 8,
    borderTopWidth: 1,
    borderTopColor: '#164e63',
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  currentTripTicketLabel: {
    color: '#94a3b8',
    fontSize: 12,
  },
  currentTripTicketCode: {
    color: '#f8fafc',
    fontWeight: '800',
    fontSize: 13,
  },
  currentTripActionRow: {
    marginTop: 6,
    flexDirection: 'row',
    gap: 10,
  },
  currentTripActionButton: {
    flex: 1,
    minHeight: 46,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#1f7a8c',
    backgroundColor: '#0d2531',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
  },
  currentTripActionButtonText: {
    color: '#ccfbf1',
    fontSize: 13,
    fontWeight: '800',
  },
  searchCard: {
    borderRadius: 22,
    borderWidth: 1,
    borderColor: '#2A0F12',
    backgroundColor: '#0A0A0A',
    padding: 14,
    gap: 12,
  },
  routeSearchTitle: {
    color: '#ffffff',
    fontSize: 18,
    fontWeight: '900',
    textAlign: 'right',
  },
  routeSearchHint: {
    color: '#cbd5e1',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  routeSearchGrid: {
    gap: 10,
  },
  routeField: {
    gap: 7,
  },
  routeFieldLabel: {
    color: '#fecaca',
    fontSize: 12,
    fontWeight: '900',
    textAlign: 'right',
  },
  searchInput: {
    minHeight: 48,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    paddingHorizontal: 12,
    color: '#f8fafc',
    textAlign: 'right',
    writingDirection: 'rtl',
  },
  stopSuggestionRow: {
    gap: 8,
    paddingVertical: 2,
  },
  stopSuggestionChip: {
    minHeight: 34,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#7f1d1d',
    backgroundColor: '#1A0B0B',
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stopSuggestionText: {
    color: '#fecaca',
    fontSize: 12,
    fontWeight: '800',
  },
  routeActionRow: {
    flexDirection: 'row',
    gap: 10,
  },
  routeActionButton: {
    flex: 1,
  },
  locationSearchButton: {
    minHeight: 48,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#3f3f46',
    backgroundColor: '#ffffff',
    alignItems: 'center',
    justifyContent: 'center',
  },
  locationSearchButtonText: {
    color: '#0A0A0A',
    fontWeight: '900',
    fontSize: 15,
  },
  locationSearchNote: {
    color: '#fca5a5',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'right',
  },
  walletProofCard: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#7f1d1d',
    backgroundColor: '#140808',
    padding: 14,
    gap: 8,
  },
  walletProofTitle: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '900',
    textAlign: 'right',
  },
  walletProofMeta: {
    color: '#fecaca',
    fontSize: 13,
    fontWeight: '900',
    textAlign: 'right',
  },
  walletProofText: {
    color: '#cbd5e1',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'right',
  },
  walletSenderInput: {
    borderColor: '#D32F2F',
    backgroundColor: '#1A1A1A',
  },
  searchButton: {
    minHeight: 48,
    borderRadius: 12,
    backgroundColor: '#D32F2F',
    alignItems: 'center',
    justifyContent: 'center',
  },
  searchButtonText: {
    color: '#ffffff',
    fontWeight: '900',
    fontSize: 16,
  },
  sectionCard: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#1f2e46',
    backgroundColor: '#0A0A0A',
    padding: 12,
    gap: 10,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  sectionHeaderActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  sectionTitle: {
    color: '#f8fafc',
    fontSize: 22,
    fontWeight: '800',
    textAlign: 'right',
  },
  sectionBadge: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#1b6a7a',
    paddingHorizontal: 10,
    paddingVertical: 4,
    color: '#FCA5A5',
    fontSize: 11,
    fontWeight: '700',
  },
  emptyStateText: {
    color: '#94a3b8',
    fontSize: 13,
    lineHeight: 19,
  },
  tripList: {
    gap: 10,
  },
  tripCard: {
    borderRadius: 15,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    padding: 11,
    gap: 6,
  },
  tripCardSelected: {
    borderColor: '#D32F2F',
    backgroundColor: '#0c2234',
  },
  tripCardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  },
  tripCardTitle: {
    color: '#f8fafc',
    fontWeight: '800',
    fontSize: 17,
    flex: 1,
    textAlign: 'right',
  },
  tripSeatsBadge: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#1f7a8c',
    color: '#99f6e4',
    fontSize: 11,
    fontWeight: '700',
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  tripCardRoute: {
    color: '#cbd5e1',
    fontSize: 13,
    textAlign: 'right',
  },
  tripServiceClass: {
    alignSelf: 'flex-end',
    color: '#fecaca',
    backgroundColor: '#2a0b0b',
    borderWidth: 1,
    borderColor: '#7f1d1d',
    borderRadius: 7,
    paddingHorizontal: 8,
    paddingVertical: 5,
    fontSize: 10,
    fontWeight: '800',
    textAlign: 'right',
  },
  tripCardBottom: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 10,
  },
  tripCardMeta: {
    color: '#94a3b8',
    fontSize: 12,
    textAlign: 'right',
  },
  tripCardPrice: {
    color: '#FCA5A5',
    fontSize: 12,
    fontWeight: '800',
  },
  tripDateChipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  tripDateChip: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#1f7a8c',
    backgroundColor: '#0A0A0A',
    color: '#99f6e4',
    fontSize: 11,
    fontWeight: '800',
    paddingHorizontal: 9,
    paddingVertical: 4,
  },
  tripDateChipActive: {
    borderColor: '#16a34a',
    backgroundColor: '#052e16',
    color: '#bbf7d0',
  },
  tripCardActionRow: {
    marginTop: 6,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  tripCardActionHint: {
    flex: 1,
  },
  tripCardActionHintText: {
    color: '#8ba6c7',
    fontSize: 11,
    lineHeight: 16,
  },
  tripCardActionWrap: {
    minHeight: 44,
    borderRadius: 11,
    borderWidth: 1,
    borderColor: '#1f7a8c',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#0A0A0A',
    paddingHorizontal: 16,
  },
  tripCardAction: {
    color: '#ccfbf1',
    fontWeight: '700',
    fontSize: 13,
  },
  tripFavoriteButton: {
    minHeight: 44,
    borderRadius: 11,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: '#111111',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 13,
  },
  tripFavoriteButtonActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#3b0b0b',
  },
  tripFavoriteButtonText: {
    color: '#cbd5e1',
    fontSize: 12,
    fontWeight: '800',
  },
  tripFavoriteButtonTextActive: {
    color: '#fecaca',
  },
  focusMapCard: {
    overflow: 'hidden',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#23344f',
    backgroundColor: '#050505',
  },
  focusDetailsCard: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    padding: 12,
    gap: 10,
  },
  recurringSummaryCard: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#1f7a8c',
    backgroundColor: '#0A0A0A',
    padding: 11,
    gap: 8,
  },
  recurringSummaryHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 8,
  },
  recurringSummaryTitle: {
    color: '#ccfbf1',
    fontSize: 14,
    fontWeight: '900',
  },
  recurringSummaryHint: {
    color: '#8ba6c7',
    fontSize: 12,
    lineHeight: 17,
  },
  focusTripTitle: {
    color: '#f8fafc',
    fontSize: 18,
    fontWeight: '800',
    textAlign: 'right',
  },
  focusTripRoute: {
    color: '#9fb5cc',
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'right',
  },
  focusStatsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  focusStatCard: {
    width: '47%',
    minHeight: 74,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#0A0A0A',
    padding: 10,
    gap: 6,
  },
  focusStatLabel: {
    color: '#7f93ad',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
    textAlign: 'right',
  },
  focusStatValue: {
    color: '#eff6ff',
    fontSize: 13,
    fontWeight: '700',
    lineHeight: 18,
    textAlign: 'right',
  },
  driverAssistMeta: {
    color: '#9fb5cc',
    fontSize: 12,
    textAlign: 'right',
  },
  focusActionRow: {
    flexDirection: 'row',
    gap: 10,
  },
  secondaryActionButton: {
    flex: 1,
    minHeight: 48,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: '#0A0A0A',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 10,
  },
  secondaryActionButtonText: {
    color: '#e2e8f0',
    fontSize: 14,
    fontWeight: '700',
  },
  primaryActionButton: {
    flex: 1,
    minHeight: 48,
    borderRadius: 14,
    backgroundColor: '#e2e8f0',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 10,
  },
  primaryActionButtonText: {
    color: '#0A0A0A',
    fontSize: 14,
    fontWeight: '800',
  },
  loyaltyHeroCard: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#7F1D1D',
    backgroundColor: '#111111',
    padding: 14,
    gap: 10,
  },
  loyaltyEyebrow: {
    color: '#FCA5A5',
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 1.4,
    textAlign: 'right',
    textTransform: 'uppercase',
  },
  loyaltyPoints: {
    color: '#f8fafc',
    fontSize: 34,
    fontWeight: '900',
    textAlign: 'right',
  },
  loyaltyHint: {
    color: '#b6c8dc',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  loyaltyProgressTrack: {
    height: 10,
    borderRadius: 999,
    overflow: 'hidden',
    backgroundColor: '#0A0A0A',
    borderWidth: 1,
    borderColor: '#404040',
  },
  loyaltyProgressFill: {
    height: '100%',
    borderRadius: 999,
    backgroundColor: '#D32F2F',
  },
  benefitList: {
    gap: 10,
  },
  benefitCard: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#0A0A0A',
    padding: 12,
    gap: 6,
  },
  loyaltyRewardEligible: {
    borderColor: '#16A34A',
    backgroundColor: '#071A0D',
  },
  loyaltyActivityRow: {
    minHeight: 78,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#0A0A0A',
    padding: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  loyaltyActivityPoints: {
    color: '#4ADE80',
    fontSize: 18,
    fontWeight: '900',
  },
  benefitTitle: {
    color: '#f8fafc',
    fontSize: 15,
    fontWeight: '900',
    textAlign: 'right',
  },
  benefitText: {
    color: '#a9bad1',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  complianceGrid: {
    gap: 10,
  },
  complianceCard: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#0A0A0A',
    padding: 12,
    gap: 6,
  },
  complianceTitle: {
    color: '#f8fafc',
    fontSize: 15,
    fontWeight: '900',
    textAlign: 'right',
  },
  complianceText: {
    color: '#a9bad1',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  supportHero: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#7F1D1D',
    backgroundColor: '#111111',
    padding: 14,
    gap: 8,
  },
  supportTitle: {
    color: '#f8fafc',
    fontSize: 20,
    fontWeight: '900',
    lineHeight: 27,
    textAlign: 'right',
  },
  supportText: {
    color: '#b6c8dc',
    fontSize: 13,
    lineHeight: 21,
    textAlign: 'right',
  },
  supportPanel: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#0A0A0A',
    padding: 12,
    gap: 10,
  },
  supportPanelTitle: {
    color: '#f8fafc',
    fontSize: 16,
    fontWeight: '900',
    textAlign: 'right',
  },
  supportPanelText: {
    color: '#a9bad1',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  supportPillRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  supportPill: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: '#050505',
    paddingHorizontal: 10,
    paddingVertical: 7,
  },
  supportPillActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#D32F2F',
  },
  supportPillText: {
    color: '#cbd5e1',
    fontSize: 11,
    fontWeight: '800',
  },
  supportPillTextActive: {
    color: '#ffffff',
  },
  supportInput: {
    minHeight: 46,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: '#050505',
    color: '#f8fafc',
    paddingHorizontal: 12,
    paddingVertical: 10,
    textAlign: 'right',
  },
  supportTextArea: {
    minHeight: 92,
    textAlignVertical: 'top',
  },
  supportTicketCard: {
    borderRadius: 15,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#050505',
    padding: 11,
    gap: 8,
  },
  supportTicketHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 10,
  },
  flexOne: {
    flex: 1,
  },
  supportTicketTitle: {
    color: '#f8fafc',
    fontSize: 14,
    fontWeight: '900',
    textAlign: 'right',
  },
  supportTicketMeta: {
    color: '#94a3b8',
    fontSize: 11,
    lineHeight: 17,
    textAlign: 'right',
  },
  supportTicketStatus: {
    borderRadius: 999,
    overflow: 'hidden',
    backgroundColor: '#D32F2F',
    color: '#ffffff',
    fontSize: 10,
    fontWeight: '900',
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  supportTicketDetails: {
    borderTopWidth: 1,
    borderTopColor: '#2A2A2A',
    paddingTop: 8,
    gap: 6,
  },
  supportTicketBody: {
    color: '#dbeafe',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  supportTicketResolution: {
    color: '#fecaca',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  disabledActionButton: {
    opacity: 0.5,
  },
  confirmationOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.78)',
    justifyContent: 'center',
    padding: 18,
  },
  confirmationPanel: {
    borderRadius: 28,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.12)',
    backgroundColor: '#0B0B0D',
    padding: 18,
    gap: 14,
    shadowColor: '#D32F2F',
    shadowOpacity: 0.35,
    shadowRadius: 28,
    elevation: 12,
  },
  confirmationPanelHeader: {
    flexDirection: 'row-reverse',
    alignItems: 'center',
    gap: 14,
  },
  confirmationPulse: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: '#D32F2F',
    borderWidth: 8,
    borderColor: 'rgba(211, 47, 47, 0.24)',
  },
  confirmationPanelCopy: {
    flex: 1,
    gap: 4,
  },
  confirmationEyebrow: {
    color: '#FCA5A5',
    fontSize: 11,
    fontWeight: '900',
    textAlign: 'right',
  },
  passengerConfirmationTitle: {
    color: '#ffffff',
    fontSize: 22,
    fontWeight: '900',
    textAlign: 'right',
  },
  confirmationSubtitle: {
    color: '#cbd5e1',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  confirmationTripCard: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    padding: 12,
    gap: 5,
  },
  confirmationTripName: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '900',
    textAlign: 'right',
  },
  confirmationTripMeta: {
    color: '#cbd5e1',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  confirmationDetailsGrid: {
    flexDirection: 'row-reverse',
    gap: 10,
  },
  confirmationDetailBox: {
    flex: 1,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#050505',
    padding: 11,
    gap: 4,
  },
  confirmationDetailLabel: {
    color: '#94a3b8',
    fontSize: 10,
    fontWeight: '800',
    textAlign: 'right',
  },
  confirmationDetailValue: {
    color: '#ffffff',
    fontSize: 15,
    fontWeight: '900',
    textAlign: 'right',
  },
  confirmationDetailHint: {
    color: '#9ca3af',
    fontSize: 11,
    textAlign: 'right',
  },
  confirmationWarningBox: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: 'rgba(251, 191, 36, 0.42)',
    backgroundColor: 'rgba(251, 191, 36, 0.12)',
    padding: 11,
  },
  confirmationWarningText: {
    color: '#fde68a',
    fontSize: 12,
    lineHeight: 19,
    textAlign: 'right',
  },
  confirmationActionRow: {
    flexDirection: 'row',
    gap: 10,
  },
  confirmationRejectButton: {
    flex: 1,
    minHeight: 50,
    borderRadius: 15,
    borderWidth: 1,
    borderColor: '#3f3f46',
    backgroundColor: '#18181b',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 10,
  },
  confirmationRejectText: {
    color: '#f8fafc',
    fontSize: 13,
    fontWeight: '900',
  },
  confirmationConfirmButton: {
    flex: 1.3,
    minHeight: 50,
    borderRadius: 15,
    backgroundColor: '#D32F2F',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 10,
  },
  confirmationConfirmText: {
    color: '#ffffff',
    fontSize: 13,
    fontWeight: '900',
  },
  confirmationLaterButton: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 7,
  },
  confirmationLaterText: {
    color: '#9ca3af',
    fontSize: 12,
    fontWeight: '800',
  },
  reservationCard: {
    borderRadius: 15,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    padding: 11,
    gap: 4,
  },
  reservationHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 8,
  },
  reservationTripTitle: {
    color: '#f8fafc',
    fontWeight: '800',
    fontSize: 15,
    flex: 1,
  },
  reservationStatus: {
    color: '#FCA5A5',
    fontSize: 11,
    fontWeight: '700',
  },
  reservationMeta: {
    color: '#cbd5e1',
    fontSize: 12,
    textAlign: 'right',
  },
  reservationFooter: {
    marginTop: 4,
    paddingTop: 7,
    borderTopWidth: 1,
    borderTopColor: '#2A2A2A',
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: 8,
  },
  reservationGroupDetails: {
    marginTop: 8,
    gap: 6,
  },
  reservationQuickActions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  reservationMiniRow: {
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#050505',
    paddingHorizontal: 10,
    paddingVertical: 8,
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 8,
  },
  signOutButton: {
    minHeight: 48,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: '#111111',
    alignItems: 'center',
    justifyContent: 'center',
  },
  signOutButtonText: {
    color: '#f8fafc',
    fontSize: 16,
    fontWeight: '700',
  },
  drawerRoot: {
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'flex-end',
    backgroundColor: 'rgba(2, 6, 23, 0.6)',
  },
  drawerBackdrop: {
    position: 'absolute',
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
  },
  drawerPanel: {
    width: '82%',
    maxWidth: 340,
    height: '100%',
    backgroundColor: '#050505',
    borderLeftWidth: 1,
    borderLeftColor: '#1f2e46',
    paddingHorizontal: 16,
    paddingTop: 24,
    paddingBottom: 18,
    gap: 16,
  },
  drawerHeader: {
    flexDirection: 'row-reverse',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 10,
  },
  drawerEyebrow: {
    color: '#FCA5A5',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1.6,
    textAlign: 'right',
  },
  drawerTitle: {
    color: '#f8fafc',
    fontSize: 26,
    fontWeight: '800',
    textAlign: 'right',
    marginTop: 4,
  },
  drawerSubtitle: {
    color: '#94a3b8',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'right',
    marginTop: 4,
  },
  drawerCloseButton: {
    minHeight: 42,
    minWidth: 74,
    paddingHorizontal: 14,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    alignItems: 'center',
    justifyContent: 'center',
  },
  drawerCloseButtonText: {
    color: '#f8fafc',
    fontSize: 13,
    fontWeight: '700',
  },
  drawerMenuScroll: {
    flex: 1,
  },
  drawerMenuList: {
    gap: 10,
    paddingBottom: 28,
  },
  drawerMenuButton: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    paddingHorizontal: 14,
    paddingVertical: 14,
    gap: 4,
  },
  drawerMenuButtonActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#D32F2F',
  },
  drawerMenuButtonText: {
    color: '#f8fafc',
    fontSize: 15,
    fontWeight: '800',
    textAlign: 'right',
  },
  drawerMenuButtonTextActive: {
    color: '#ecfeff',
  },
  drawerMenuHint: {
    color: '#94a3b8',
    fontSize: 12,
    lineHeight: 17,
    textAlign: 'right',
  },
  drawerMenuHintActive: {
    color: '#d1fae5',
  },
  drawerDangerButton: {
    borderColor: '#7f1d1d',
    backgroundColor: '#22090d',
  },
  drawerDangerButtonText: {
    color: '#fecaca',
  },
  drawerDangerHint: {
    color: '#fca5a5',
  },
  bottomTabs: {
    position: 'absolute',
    left: 12,
    right: 12,
    bottom: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#1f2e46',
    backgroundColor: 'rgba(10, 19, 38, 0.98)',
    padding: 8,
  },
  bottomTabButton: {
    flex: 1,
    minHeight: 44,
    borderRadius: 11,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    alignItems: 'center',
    justifyContent: 'center',
  },
  bottomTabButtonActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#D32F2F',
  },
  bottomTabText: {
    color: '#cbd5e1',
    fontSize: 12,
    fontWeight: '700',
  },
  bottomTabTextActive: {
    color: '#ecfeff',
  },
  mapWrap: {
    width: '100%',
    overflow: 'hidden',
    backgroundColor: '#050505',
    borderRadius: 24,
    position: 'relative',
  },
  mapWebview: {
    flex: 1,
    backgroundColor: '#050505',
  },
  mapExpandButton: {
    position: 'absolute',
    top: 12,
    right: 12,
    width: 42,
    height: 42,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    backgroundColor: 'rgba(2,6,23,0.82)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  mapExpandButtonText: {
    color: '#f8fafc',
    fontSize: 18,
    fontWeight: '800',
    lineHeight: 20,
  },
  mapFallback: {
    width: '100%',
    backgroundColor: '#050505',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 18,
    borderRadius: 24,
  },
  mapFallbackText: {
    color: '#94a3b8',
    textAlign: 'center',
    fontSize: 12,
    lineHeight: 18,
  },
  fullscreenMapRoot: {
    flex: 1,
    backgroundColor: 'rgba(2,6,23,0.96)',
    padding: 14,
    justifyContent: 'center',
  },
  fullscreenMapSurface: {
    flex: 1,
    borderRadius: 28,
    overflow: 'hidden',
  },
  modalRoot: {
    flex: 1,
    backgroundColor: '#030813',
  },
  notificationModalRoot: {
    flex: 1,
    justifyContent: 'flex-end',
    backgroundColor: 'rgba(2, 6, 23, 0.72)',
    padding: 12,
  },
  notificationPanel: {
    maxHeight: '86%',
    borderRadius: 22,
    borderWidth: 1,
    borderColor: '#1f2e46',
    backgroundColor: '#050505',
    padding: 14,
    gap: 12,
  },
  notificationPanelHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 12,
  },
  notificationHeaderActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  notificationRefreshButton: {
    minHeight: 40,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#7f1d1d',
    backgroundColor: '#22090d',
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  notificationRefreshButtonText: {
    color: '#fecaca',
    fontSize: 12,
    fontWeight: '800',
  },
  notificationPanelTitle: {
    color: '#f8fafc',
    fontSize: 20,
    fontWeight: '800',
    textAlign: 'right',
  },
  notificationPanelMeta: {
    color: '#8ba6c7',
    fontSize: 12,
    lineHeight: 18,
    marginTop: 4,
  },
  notificationFilterRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
    gap: 8,
  },
  notificationFilterChip: {
    minHeight: 38,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  notificationFilterChipActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#D32F2F',
  },
  notificationFilterText: {
    color: '#cbd5e1',
    fontSize: 12,
    fontWeight: '800',
  },
  notificationFilterTextActive: {
    color: '#ecfeff',
  },
  notificationSearchInput: {
    minHeight: 46,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    color: '#f8fafc',
    paddingHorizontal: 14,
    textAlign: 'right',
    fontSize: 13,
  },
  notificationFocusCard: {
    borderRadius: 18,
    borderWidth: 1,
    borderColor: '#D32F2F',
    backgroundColor: '#061e2a',
    padding: 14,
    gap: 8,
  },
  notificationFocusEyebrow: {
    color: '#5eead4',
    fontSize: 11,
    fontWeight: '900',
    letterSpacing: 1.2,
    textAlign: 'right',
  },
  notificationFocusTitle: {
    color: '#f8fafc',
    fontSize: 18,
    fontWeight: '900',
    textAlign: 'right',
  },
  notificationFocusBody: {
    color: '#dbe7f5',
    fontSize: 14,
    lineHeight: 22,
    textAlign: 'right',
  },
  notificationFocusTime: {
    color: '#8ba6c7',
    fontSize: 12,
    textAlign: 'right',
  },
  notificationFocusActions: {
    flexDirection: 'row',
    gap: 10,
    marginTop: 6,
  },
  notificationUtilityButton: {
    flex: 1,
    minHeight: 42,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: '#111111',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 10,
  },
  notificationUtilityButtonText: {
    color: '#e2e8f0',
    fontSize: 12,
    fontWeight: '800',
  },
  notificationDeleteButton: {
    borderColor: '#7f1d1d',
    backgroundColor: '#22090d',
  },
  notificationDeleteButtonText: {
    color: '#fecaca',
  },
  notificationBulkRow: {
    minHeight: 40,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  notificationBulkMeta: {
    flex: 1,
    color: '#8ba6c7',
    fontSize: 12,
    textAlign: 'right',
  },
  notificationMarkAllButton: {
    minHeight: 38,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  notificationMarkAllText: {
    color: '#f8fafc',
    fontSize: 12,
    fontWeight: '800',
  },
  notificationList: {
    gap: 10,
    paddingBottom: 16,
  },
  notificationCard: {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    padding: 12,
    gap: 8,
  },
  notificationCardUnread: {
    borderColor: '#D32F2F',
    backgroundColor: '#0A0A0A',
  },
  notificationCardFocused: {
    borderColor: '#5eead4',
    backgroundColor: '#111111',
  },
  notificationCardHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 8,
  },
  notificationCardTitle: {
    flex: 1,
    color: '#f8fafc',
    fontSize: 14,
    fontWeight: '800',
    textAlign: 'right',
  },
  notificationCardTime: {
    color: '#8ba6c7',
    fontSize: 11,
    textAlign: 'right',
  },
  notificationCardBody: {
    color: '#dbe7f5',
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'right',
  },
  notificationCardType: {
    color: '#99f6e4',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
  },
  notificationCardFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  notificationCardAction: {
    color: '#e2e8f0',
    fontSize: 12,
    fontWeight: '800',
  },
  notificationLoadMoreButton: {
    minHeight: 46,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#7f1d1d',
    backgroundColor: '#22090d',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  notificationLoadMoreText: {
    color: '#fecaca',
    fontSize: 13,
    fontWeight: '800',
  },
  notificationEndText: {
    color: '#64748b',
    fontSize: 12,
    textAlign: 'center',
    paddingVertical: 8,
  },
  modalTopBar: {
    position: 'absolute',
    top: 52,
    left: 12,
    right: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  modalTopActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  modalTopTitle: {
    flex: 1,
    color: '#f8fafc',
    fontSize: 14,
    fontWeight: '700',
    backgroundColor: 'rgba(2, 6, 23, 0.72)',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#404040',
    paddingHorizontal: 10,
    paddingVertical: 9,
    textAlign: 'right',
  },
  modalGhostButton: {
    minHeight: 40,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#164e63',
    backgroundColor: 'rgba(8, 26, 39, 0.86)',
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  modalGhostButtonText: {
    color: '#d5fbff',
    fontWeight: '700',
    fontSize: 12,
  },
  modalCloseButton: {
    minHeight: 40,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: 'rgba(2, 6, 23, 0.85)',
    paddingHorizontal: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  modalCloseButtonText: {
    color: '#e2e8f0',
    fontWeight: '700',
    fontSize: 12,
  },
  bottomSheet: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    height: sheetHeight,
    backgroundColor: '#0A0A0A',
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    borderWidth: 1,
    borderColor: '#1f2e46',
  },
  sheetHandleZone: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingTop: 10,
    paddingBottom: 8,
    borderBottomWidth: 1,
    borderBottomColor: '#1f2e46',
  },
  sheetHandlePressable: {
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 2,
  },
  sheetHandle: {
    width: 56,
    height: 6,
    borderRadius: 999,
    backgroundColor: '#404040',
    marginBottom: 8,
  },
  sheetTitle: {
    color: '#e2e8f0',
    fontSize: 13,
    fontWeight: '700',
  },
  sheetHint: {
    color: '#FCA5A5',
    fontSize: 11,
    fontWeight: '700',
    marginTop: 3,
  },
  sheetScroll: {
    flex: 1,
  },
  sheetContent: {
    paddingHorizontal: 12,
    paddingTop: 10,
    paddingBottom: 24,
    gap: 8,
  },
  tripSummaryCard: {
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#2A2A2A',
    backgroundColor: '#111111',
    padding: 10,
    gap: 3,
  },
  tripSummaryCardFocused: {
    borderColor: '#D32F2F',
    backgroundColor: '#0d2336',
  },
  tripSummaryTitle: {
    color: '#f8fafc',
    fontSize: 16,
    fontWeight: '800',
    textAlign: 'right',
  },
  tripSummaryMeta: {
    color: '#cbd5e1',
    fontSize: 12,
    textAlign: 'right',
  },
  tripSummaryActionRow: {
    marginTop: 6,
    paddingTop: 8,
    borderTopWidth: 1,
    borderTopColor: '#2A2A2A',
  },
  tripSummaryActionText: {
    color: '#99f6e4',
    fontSize: 11,
    lineHeight: 16,
  },
  inputLabel: {
    marginTop: 8,
    color: '#e2e8f0',
    fontSize: 14,
    fontWeight: '800',
    textAlign: 'right',
  },
  pointOptionList: {
    gap: 8,
  },
  pointOptionCard: {
    minHeight: 56,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: '#111111',
    paddingHorizontal: 10,
    paddingVertical: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  pointOptionCardActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#0f2f2f',
  },
  pointOptionOrderWrap: {
    width: 28,
    height: 28,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#475569',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#0b1222',
  },
  pointOptionOrderText: {
    color: '#cbd5e1',
    fontSize: 12,
    fontWeight: '700',
  },
  pointOptionBody: {
    flex: 1,
    gap: 2,
  },
  pointOptionTitle: {
    color: '#e2e8f0',
    fontSize: 13,
    fontWeight: '700',
    textAlign: 'right',
  },
  pointOptionTitleActive: {
    color: '#ecfeff',
  },
  pointOptionMeta: {
    color: '#94a3b8',
    fontSize: 11,
    textAlign: 'right',
  },
  pointOptionMetaActive: {
    color: '#99f6e4',
  },
  pillsWrap: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  choicePill: {
    minHeight: 40,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#404040',
    backgroundColor: '#111111',
    paddingHorizontal: 12,
    justifyContent: 'center',
  },
  choicePillActive: {
    borderColor: '#D32F2F',
    backgroundColor: '#D32F2F',
  },
  choicePillText: {
    color: '#e2e8f0',
    fontSize: 12,
    fontWeight: '600',
  },
  choicePillTextActive: {
    color: '#ecfeff',
    fontWeight: '700',
  },
  confirmationCard: {
    marginTop: 8,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#1f7a8c',
    backgroundColor: '#0A0A0A',
    padding: 10,
    gap: 4,
  },
  confirmationTitle: {
    color: '#e0f2fe',
    fontSize: 14,
    fontWeight: '800',
  },
  confirmationText: {
    color: '#cfe8ff',
    fontSize: 12,
  },
  pricingPreviewCard: {
    marginTop: 8,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#24445a',
    backgroundColor: '#050505',
    padding: 12,
    gap: 10,
  },
  tierRecommendationCard: {
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#D32F2F',
    backgroundColor: 'rgba(211, 47, 47, 0.12)',
    padding: 10,
    gap: 8,
  },
  tierRecommendationTitle: {
    color: '#bbf7d0',
    fontSize: 13,
    fontWeight: '900',
    textAlign: 'right',
  },
  voucherInputRow: {
    marginTop: 12,
    flexDirection: 'row-reverse',
    alignItems: 'center',
    gap: 10,
  },
  voucherInput: {
    flex: 1,
    marginTop: 0,
  },
  pricingPreviewHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  pricingPreviewTitle: {
    color: '#f8fafc',
    fontSize: 14,
    fontWeight: '800',
    textAlign: 'right',
    flex: 1,
  },
  pricingPreviewGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  pricingPreviewMetric: {
    width: '47%',
    minHeight: 74,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#1f394d',
    backgroundColor: '#0A0A0A',
    padding: 10,
    gap: 6,
  },
  pricingPreviewLabel: {
    color: '#8ba6c7',
    fontSize: 11,
    fontWeight: '700',
    textAlign: 'right',
  },
  pricingPreviewValue: {
    color: '#ecfeff',
    fontSize: 13,
    fontWeight: '800',
    lineHeight: 18,
    textAlign: 'right',
  },
  pricingPreviewHint: {
    color: '#9fb5cc',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'right',
  },
  pricingPreviewError: {
    color: '#fda4af',
    fontSize: 12,
    lineHeight: 18,
    textAlign: 'right',
  },
  reserveButton: {
    marginTop: 8,
    minHeight: 48,
    borderRadius: 12,
    backgroundColor: '#D32F2F',
    alignItems: 'center',
    justifyContent: 'center',
  },
  reserveButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '800',
  },
});
