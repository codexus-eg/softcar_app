import * as Calendar from 'expo-calendar';

type CalendarReservation = {
  ticketCode: string | null;
  pickupPoint: { name: string };
  dropoffPoint: { name: string };
  trip: { title: string; startTime: string; estimatedEndTime?: string | null };
};

export async function addReservationToDeviceCalendar(reservation: CalendarReservation) {
  const startDate = new Date(reservation.trip.startTime);
  if (!Number.isFinite(startDate.getTime())) throw new Error('موعد الرحلة غير صالح للإضافة إلى التقويم.');
  const permission = await Calendar.requestCalendarPermissionsAsync();
  if (permission.status !== 'granted') throw new Error('فعّل إذن التقويم من إعدادات الهاتف لإضافة الرحلة.');
  const calendars = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
  const writable = calendars.find((entry) => entry.allowsModifications) || calendars[0];
  if (!writable) throw new Error('لم يتم العثور على تقويم متاح على هذا الجهاز.');
  const estimated = reservation.trip.estimatedEndTime ? new Date(reservation.trip.estimatedEndTime) : null;
  const endDate = estimated && Number.isFinite(estimated.getTime()) && estimated > startDate
    ? estimated
    : new Date(startDate.getTime() + 90 * 60 * 1000);
  const eventId = await Calendar.createEventAsync(writable.id, {
    title: `رحلة SOFT CAR - ${reservation.trip.title}`,
    startDate,
    endDate,
    location: `${reservation.pickupPoint.name} ← ${reservation.dropoffPoint.name}`,
    notes: [`نقطة الصعود: ${reservation.pickupPoint.name}`, `نقطة النزول: ${reservation.dropoffPoint.name}`, reservation.ticketCode ? `رقم التذكرة: ${reservation.ticketCode}` : ''].filter(Boolean).join('\n'),
    alarms: [{ relativeOffset: -30 }, { relativeOffset: -10 }],
    timeZone: 'Africa/Cairo',
  });
  return { eventId, calendarTitle: writable.title };
}
