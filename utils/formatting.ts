import type { NotificationItem, NotificationFilter, TripPoint, Trip } from './types';

export function formatDate(value: string | null | undefined) {
  if (!value) return '-';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '-' : parsed.toLocaleString('ar-EG');
}

export function formatShortTime(value: string | null | undefined) {
  if (!value) return '-';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '-' : parsed.toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' });
}

export function formatMoney(value: number | string | null | undefined) {
  const parsed = Number(value || 0);
  return Number.isFinite(parsed) ? `${parsed.toFixed(2)} ج.م` : '0.00 ج.م';
}

export function formatPaymentMethodLabel(method: string | null | undefined) {
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

export function formatReservationStatusLabel(status: string | null | undefined) {
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

export function formatTripStatusLabel(status: string | null | undefined) {
  switch (String(status || '').toUpperCase()) {
    case 'SCHEDULED':
      return 'Scheduled';
    case 'IN_PROGRESS':
      return 'In progress';
    case 'COMPLETED':
      return 'Completed';
    case 'CANCELLED':
      return 'Cancelled';
    case 'DELAYED':
      return 'Delayed';
    default:
      return status || '-';
  }
}

export function formatNotificationTypeLabel(type: string | null | undefined) {
  switch (String(type || '').toLowerCase()) {
    case 'trip_delay':
      return 'تأخير رحلة';
    case 'trip_update':
      return 'تحديث رحلة';
    case 'driver_update':
      return 'تحديث السائق';
    case 'booking':
      return 'حجز';
    case 'system':
      return 'النظام';
    default:
      return type || '-';
  }
}

export function formatThemeLabel(theme: string | null | undefined) {
  switch (String(theme || '').toLowerCase()) {
    case 'dark':
      return 'داكن';
    case 'light':
      return 'فاتح';
    case 'system':
      return 'تلقائي';
    default:
      return theme || 'تلقائي';
  }
}

export function formatLanguageLabel(language: string | null | undefined) {
  switch (String(language || '').toLowerCase()) {
    case 'ar':
    case 'ar-eg':
      return 'العربية';
    case 'en':
      return 'الإنجليزية';
    default:
      return language || 'العربية';
  }
}

export function formatSupportCategoryLabel(category: string) {
  const map: Record<string, string> = {
    GENERAL: 'عام',
    BOOKING: 'الحجز',
    TRIP: 'الرحلة',
    PAYMENT: 'الدفع',
    TECHNICAL: 'تقني',
    ACCOUNT: 'الحساب',
  };
  return map[category] || category;
}

export function formatSupportPriorityLabel(priority: string) {
  const map: Record<string, string> = {
    LOW: 'منخفض',
    NORMAL: 'عادي',
    HIGH: 'مهم',
    URGENT: 'عاجل',
  };
  return map[priority] || priority;
}

export function formatSupportStatusLabel(status: string) {
  const map: Record<string, string> = {
    OPEN: 'مفتوح',
    IN_PROGRESS: 'قيد المتابعة',
    RESOLVED: 'تم الحل',
    CLOSED: 'مغلق',
  };
  return map[status] || status;
}

export function formatPointEta(startTime: string | null | undefined, point: TripPoint) {
  const parsedOffset = Number(point.arrivalOffsetMin ?? 0);
  const offset = Number.isFinite(parsedOffset) ? Math.max(0, parsedOffset) : 0;
  if (!startTime) return `${offset} دقيقة`;
  const startDate = new Date(startTime);
  if (Number.isNaN(startDate.getTime())) return `${offset} دقيقة`;
  const eta = new Date(startDate.getTime() + offset * 60_000);
  return formatShortTime(eta.toISOString());
}

export function toNumber(value: number | string | null | undefined) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function normalizeRouteText(value?: string | null) {
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

export function pointRouteText(point?: TripPoint | null) {
  return normalizeRouteText(`${point?.name || ''}`);
}

export function mobileDateKey(value?: string | null) {
  if (!value) return '';
  return new Date(value).toISOString().slice(0, 10);
}

export function pointMatchesRoute(point: TripPoint, query: string) {
  const normalizedQuery = normalizeRouteText(query);
  if (!normalizedQuery) return true;
  const text = pointRouteText(point);
  return text.includes(normalizedQuery) || normalizedQuery.includes(text);
}

export function matchesNotificationFilter(item: NotificationItem, filter: NotificationFilter) {
  const type = String(item.type || '').toLowerCase();
  if (filter === 'all') return true;
  if (filter === 'unread') return !item.readAt;
  if (filter === 'trip') return type.includes('trip') || type.includes('reservation') || type.includes('booking') || type.includes('driver');
  if (filter === 'support') return type.includes('support') || type.includes('ticket') || type.includes('chat');
  return type.includes('system') || type.includes('rule') || type.includes('security');
}

export function getNotificationActionLabel(item: NotificationItem | null) {
  const type = String(item?.type || '').toLowerCase();
  if (!item?.actionUrl) return 'لا يوجد إجراء مطلوب';
  if (type.includes('trip') || type.includes('reservation') || type.includes('booking') || type.includes('driver')) {
    return 'فتح الرحلة المرتبطة';
  }
  if (type.includes('support') || type.includes('chat') || type.includes('ticket')) {
    return 'فتح الدعم';
  }
  return 'فتح الإجراء';
}

export function parseSeatCode(raw: string) {
  const upper = String(raw || '').trim().toUpperCase();
  if (!upper) return '';
  if (upper.startsWith('S')) return upper;
  const match = upper.match(/\d+/);
  if (!match) return '';
  return `S${match[0].padStart(2, '0')}`;
}

export function parseReservedSeats(trip: Trip) {
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

export function createSeatMap(totalSeats: number) {
  const safeSeatCount = Math.max(1, Math.min(Number(totalSeats || 1), 60));
  return Array.from({ length: safeSeatCount }, (_, index) => `S${String(index + 1).padStart(2, '0')}`);
}

export function distanceKm(aLat: number, aLng: number, bLat: number, bLng: number) {
  const lat1 = aLat * Math.PI / 180;
  const lat2 = bLat * Math.PI / 180;
  const dLat = lat2 - lat1;
  const dLng = (bLng - aLng) * Math.PI / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 6371 * (2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h)));
}

export function nearestMobilePickupDistance(trip: Trip, coords?: { lat: number; lng: number } | null) {
  if (!coords) return Number.POSITIVE_INFINITY;
  return (trip.pickupPoints || []).reduce((nearest, point) => {
    const lat = toNumber(point.latitude);
    const lng = toNumber(point.longitude);
    if (lat == null || lng == null) return nearest;
    return Math.min(nearest, distanceKm(coords.lat, coords.lng, lat, lng));
  }, Number.POSITIVE_INFINITY);
}

export function uniqueStopOptions(trips: Trip[], type: 'pickup' | 'dropoff', query: string) {
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

export function findMobileRoutePair(trip: Trip, from: string, to: string) {
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

export function mobileTripOccurrences(trip: Trip) {
  return (trip.occurrences?.length
    ? trip.occurrences
    : [{ id: trip.id, startTime: trip.startTime, seatsRemaining: trip.seatsRemaining, status: 'SCHEDULED' }]
  )
    .filter((occurrence) => String(occurrence.status || 'SCHEDULED').toUpperCase() === 'SCHEDULED')
    .sort((left, right) => new Date(left.startTime).getTime() - new Date(right.startTime).getTime());
}

export function tripMatchesMobileRoute(trip: Trip, from: string, to: string, date: string, query: string) {
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

export function reservationDisplayGroupKey(reservation: { id: string; trip: { title: string }; pickupPoint: { name: string }; dropoffPoint: { name: string }; status: string; paymentMethod: string; recurringReservationId?: string | null }) {
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

export function groupReservationsForDisplay(reservations: Array<{ id: string; trip: { title: string; startTime: string }; pickupPoint: { name: string }; dropoffPoint: { name: string }; status: string; paymentMethod: string; recurringReservationId?: string | null }>) {
  const groups = new Map<string, typeof reservations>();
  for (const reservation of reservations) {
    const key = reservationDisplayGroupKey(reservation);
    groups.set(key, [...(groups.get(key) || []), reservation]);
  }
  return Array.from(groups.values()).map((group) =>
    [...group].sort((left, right) => new Date(left.trip.startTime).getTime() - new Date(right.trip.startTime).getTime())
  );
}

export function isReservationPaidPackage(reservations: Array<{ paymentMethod: string; paymentStatus?: string | null }>) {
  return reservations.some((reservation) => {
    const method = String(reservation.paymentMethod || '').toUpperCase();
    const status = String(reservation.paymentStatus || '').toUpperCase();
    return method === 'CASH' && (status.includes('COLLECTED') || status.includes('PAID'));
  });
}
