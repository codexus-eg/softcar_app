export type TripPoint = {
  id: string;
  name: string;
  stopOrder: number;
  pointType?: 'PICKUP' | 'DROPOFF';
  arrivalOffsetMin?: number | null;
  latitude?: number | string | null;
  longitude?: number | string | null;
};

export type TripReservation = {
  seatNumbers: string | null;
  status?: string | null;
};

export type DriverContact = {
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

export type Trip = {
  id: string;
  title: string;
  mainDestination: string;
  endDestination: string;
  startTime: string;
  estimatedEndTime?: string | null;
  seatsRemaining: number;
  totalSeats: number;
  basePrice?: number | string | null;
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

export type Reservation = {
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
  refunds?: Array<{
    id: string;
    refundCode: string;
    amount: number | string;
    status: string;
    reason: string;
    createdAt: string;
    updatedAt: string;
  }>;
};

export type MobileMePayload = {
  user: {
    id: string;
    name: string;
    email?: string | null;
    phone?: string | null;
    image?: string | null;
    preferredLanguage?: string | null;
    preferredTheme?: string | null;
  };
};

export type TripChatParticipant = {
  id: string;
  name: string;
  image?: string | null;
  role?: string | null;
};

export type TripChatMessage = {
  id: string;
  tripId: string;
  senderId: string;
  recipientUserId?: string | null;
  message: string;
  createdAt: string;
  sender?: TripChatParticipant | null;
  recipient?: TripChatParticipant | null;
};

export type TripChatPayload = {
  messages: TripChatMessage[];
  participants: {
    driver: TripChatParticipant | null;
    passengers: TripChatParticipant[];
  };
};

export type NotificationItem = {
  id: string;
  title: string;
  message: string;
  type: string;
  actionUrl?: string | null;
  readAt?: string | null;
  sentAt: string;
};

export type NotificationFeedPayload = {
  notifications: NotificationItem[];
  unreadCount: number;
};

export type SupportTicket = {
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

export type WalletSettingsPayload = {
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
    status: string;
    createdAt: string;
  }>;
  transactions?: Array<{
    id: string;
    amount: number;
    method: string;
    status: string;
    provider: string;
    createdAt: string;
  }>;
};

export type PricingPreview = {
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

export type ReservationTier = {
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

export type PassengerLoyaltyPayload = {
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

export type PaymentMethod = 'CASH' | 'CARD' | 'WALLET' | 'CASHLESS_CORPORATE';
export type PassengerTab = 'reserve' | 'history' | 'loyalty' | 'compliance' | 'support' | 'settings' | 'profile';
export type NotificationFilter = 'all' | 'unread' | 'trip' | 'support' | 'system';

export type DriverMarkerInput = {
  lat: number;
  lng: number;
  heading?: number | null;
  seats?: number | null;
  label?: string | null;
};

export type OfflineQueueItem = {
  id: string;
  action: string;
  payload: Record<string, any>;
  timestamp: number;
  retries: number;
};
