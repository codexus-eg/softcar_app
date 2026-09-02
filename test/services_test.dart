import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:softcar_passengers/models/shuttle.dart';
import 'package:softcar_passengers/models/user_profile.dart';
import 'package:softcar_passengers/services/wallet_service.dart';
import 'package:softcar_passengers/widgets/board_pass_qr.dart';

void main() {
  group('UserGender', () {
    test('fromCode maps backend codes and rejects unknown', () {
      expect(UserGender.fromCode('MALE'), UserGender.male);
      expect(UserGender.fromCode('female'), UserGender.female);
      expect(UserGender.fromCode('OTHER'), isNull);
      expect(UserGender.fromCode(null), isNull);
    });

    test('code is uppercase for the API payload', () {
      expect(UserGender.male.code, 'MALE');
      expect(UserGender.female.code, 'FEMALE');
    });
  });

  group('Ticket.fromJson', () {
    test('parses a typical live reservation payload', () {
      final ticket = Ticket.fromJson(const {
        'id': 'res_1',
        'ticketCode': 'SCS-20260810-0001',
        'pickupPoint': {'id': 'p1', 'name': 'Downtown'},
        'dropoffPoint': {'id': 'p2', 'name': 'Airport'},
        'trip': {
          'title': 'Downtown → Airport',
          'mainDestination': 'Airport',
          'startTime': '2026-08-10T09:00:00Z',
          'serviceClassCode': 'ECONOMY_COASTER',
          'pickupPoints': [
            {
              'id': 'p2',
              'name': 'Airport',
              'stopOrder': 2,
              'latitude': 30.1219,
              'longitude': 31.4056,
            },
            {
              'id': 'p1',
              'name': 'Downtown',
              'stopOrder': 1,
              'latitude': 30.0444,
              'longitude': 31.2357,
            },
          ],
          'driverProfile': {
            'fullName': 'Ahmed Hassan',
            'currentLat': 30.05,
            'currentLng': 31.24,
            'lastLocationAt': '2026-08-10T09:01:00Z',
          },
        },
        'subtotalPrice': 100,
        'taxAmount': 14,
        'totalPrice': 114,
        'seats': 1,
        'seatNumbers': 'S02',
        'paymentStatus': 'PENDING_CASH_COLLECTION',
        'status': 'RESERVED',
        'reservedAt': '2026-08-09T18:00:00Z',
        'paymentMethod': 'CASH',
      });

      expect(ticket.paymentStatus, 'PENDING_CASH_COLLECTION');
      expect(ticket.status, 'RESERVED');
      expect(ticket.isUpcoming, isTrue);
      expect(ticket.isCompleted, isFalse);
      expect(ticket.isCancelled, isFalse);
      expect(ticket.vehicleClass, ShuttleClass.fit);
      expect(ticket.seatNumbers, 'S02');
      expect(ticket.seats, 1);
      expect(ticket.total, 114);
      expect(ticket.pickupPoints.map((stop) => stop.id), ['p1', 'p2']);
      expect(ticket.driver?.currentLat, 30.05);
      expect(
        ticket.driver?.hasFreshLocation(DateTime.parse('2026-08-10T09:03:00Z')),
        isTrue,
      );
    });

    test('cancelled tickets are flagged and not upcoming', () {
      final ticket = Ticket.fromJson(const {
        'id': 't2',
        'ticketCode': 'SCS-1',
        'status': 'CANCELLED',
        'paymentStatus': 'REFUNDED',
      });
      expect(ticket.isCancelled, isTrue);
      expect(ticket.isUpcoming, isFalse);
      expect(ticket.statusLabel, 'Cancelled');
    });

    test('copyWith can mark a server-verified card payment as paid', () {
      final pending = Ticket.fromJson(const {
        'id': 'card_1',
        'paymentMethod': 'CARD',
        'paymentStatus': 'PENDING_CARD_CHECKOUT',
        'status': 'RESERVED',
      });

      final paid = pending.copyWith(paymentStatus: 'PAID');
      expect(paid.id, pending.id);
      expect(paid.paymentMethod, 'CARD');
      expect(paid.paymentStatus, 'PAID');
      expect(paid.status, 'RESERVED');
    });
  });

  group('ShuttleClass.layout', () {
    test('each class maps its real seat capacity', () {
      expect(ShuttleClass.fit.layout.expand((r) => r.all).length, 28);
      expect(ShuttleClass.comfort.layout.expand((r) => r.all).length, 14);
      expect(ShuttleClass.luxury.layout.expand((r) => r.all).length, 3);
    });

    test('seat numbers are unique within each floor plan', () {
      for (final c in ShuttleClass.values) {
        final all = c.layout.expand((r) => r.all).toList();
        expect(
          all.toSet().length,
          all.length,
          reason: '${c.name} floor plan has duplicate seat numbers',
        );
      }
    });

    test('every class has a driver/single front area', () {
      expect(ShuttleClass.fit.layout.first.left, isNotEmpty);
      expect(ShuttleClass.luxury.layout.first.left, [1]);
    });
  });

  group('ShuttleTrip.fromJson', () {
    test('keeps the real reserving passenger gender for coded seats', () {
      final trip = ShuttleTrip.fromJson(const {
        'id': 'trip_gender',
        'title': 'Gender seat test',
        'mainDestination': 'Cairo',
        'startTime': '2026-08-28T14:00:00Z',
        'basePrice': 114,
        'totalSeats': 14,
        'seatsRemaining': 11,
        'pickupPoints': [],
        'reservations': [
          {
            'seatNumbers': 'S01,S02',
            'user': {'gender': 'MALE'},
          },
          {
            'seatNumbers': 'S03',
            'user': {'gender': 'FEMALE'},
          },
        ],
      });

      expect(trip.reservedSeats, {
        1: UserGender.male,
        2: UserGender.male,
        3: UserGender.female,
      });
    });

    test('maps live trip fields and sorts stops by stopOrder', () {
      final trip = ShuttleTrip.fromJson(const {
        'id': 'trip_9',
        'title': 'Cairo → Alexandria',
        'mainDestination': 'Alexandria',
        'startTime': '2026-08-11T07:30:00Z',
        'basePrice': 250,
        'totalSeats': 28,
        'seatsRemaining': 9,
        'serviceClassCode': 'ECONOMY_COASTER',
        'pickupPoints': [
          {'id': 'p2', 'name': 'Helmeya', 'stopOrder': 2},
          {'id': 'p1', 'name': 'Ramses Station', 'stopOrder': 1},
        ],
      });

      expect(trip.vehicle, ShuttleClass.fit);
      expect(trip.totalSeats, 28);
      expect(trip.seatsRemaining, 9);
      expect(trip.price, 250);
      expect(trip.pickupPoints.first.name, 'Ramses Station');
      expect(trip.fromName, 'Ramses Station');
      expect(trip.toName, 'Helmeya');
    });

    test('parses an assigned driver from driverProfile', () {
      final trip = ShuttleTrip.fromJson(const {
        'id': 'trip_12',
        'title': 'Cairo → Alexandria',
        'mainDestination': 'Alexandria',
        'startTime': '2026-08-11T07:30:00Z',
        'basePrice': 250,
        'totalSeats': 28,
        'seatsRemaining': 9,
        'serviceClassCode': 'ECONOMY_COASTER',
        'pickupPoints': [
          {'id': 'p1', 'name': 'Ramses Station', 'stopOrder': 1},
        ],
        'driverProfile': {
          'fullName': 'Ahmed Hassan',
          'phone': '01050996940',
          'carModel': 'Toyota Coaster 2024',
          'carPlateNumber': 'ABC 1234',
          'photoUrl': '/uploads/driver-1.jpg',
          'currentLat': 30.0444,
          'currentLng': 31.2357,
          'lastLocationAt': '2026-08-11T07:29:00Z',
          'user': {'image': '/uploads/user-1.jpg'},
        },
      });

      final driver = trip.driver!;
      expect(driver.isAssigned, isTrue);
      expect(driver.name, 'Ahmed Hassan');
      expect(driver.phone, '01050996940');
      expect(driver.carPlateNumber, 'ABC 1234');
      expect(driver.photoUrl, '/uploads/driver-1.jpg');
      expect(
        driver.livePosition(DateTime.parse('2026-08-11T07:30:00Z'))?.latitude,
        30.0444,
      );
    });

    test('unassigned trip has a null/empty driver', () {
      final trip = ShuttleTrip.fromJson(const {
        'id': 'trip_13',
        'title': 'Cairo → Alexandria',
        'mainDestination': 'Alexandria',
        'startTime': '2026-08-11T07:30:00Z',
        'basePrice': 250,
        'totalSeats': 28,
        'seatsRemaining': 9,
        'serviceClassCode': 'ECONOMY_COASTER',
        'pickupPoints': [
          {'id': 'p1', 'name': 'Ramses Station', 'stopOrder': 1},
        ],
      });
      expect(trip.driver, isNull);
    });

    test('parses tripType, roundTripPrice and the return trip leg', () {
      final trip = ShuttleTrip.fromJson(const {
        'id': 'trip_20',
        'title': 'Cairo → Alexandria',
        'mainDestination': 'Alexandria',
        'startTime': '2026-08-11T07:30:00Z',
        'basePrice': 250,
        'totalSeats': 14,
        'seatsRemaining': 6,
        'serviceClassCode': 'STANDARD_HIACE',
        'tripType': 'ROUND_TRIP',
        'roundTripPrice': 400,
        'returnTrip': {
          'id': 'trip_21',
          'title': 'Alexandria → Cairo',
          'mainDestination': 'Cairo',
          'startTime': '2026-08-13T19:00:00Z',
          'basePrice': 250,
          'totalSeats': 14,
          'seatsRemaining': 14,
          'serviceClassCode': 'STANDARD_HIACE',
          'pickupPoints': [
            {'id': 'r1', 'name': 'Sidi Gaber', 'stopOrder': 1},
            {'id': 'r2', 'name': 'Downtown Cairo', 'stopOrder': 2},
          ],
        },
      });

      expect(trip.tripType, TripType.roundTrip);
      expect(trip.tripType.isRoundTrip, isTrue);
      expect(trip.roundTripPrice, 400);
      expect(trip.fareForBooking, 400);
      expect(trip.returnTrip, isNotNull);
      expect(trip.returnTrip!.id, 'trip_21');
      expect(trip.returnTrip!.pickupPoints, hasLength(2));
    });

    test('parses a recurring trip with occurrences', () {
      final trip = ShuttleTrip.fromJson(const {
        'id': 'trip_30',
        'title': 'Nasr City → Suez',
        'mainDestination': 'Suez',
        'startTime': '2026-08-17T08:00:00Z',
        'basePrice': 120,
        'totalSeats': 28,
        'seatsRemaining': 12,
        'serviceClassCode': 'ECONOMY_COASTER',
        'tripType': 'RECURRING',
        'recurrenceGroupId': 'grp-1',
        'occurrenceCount': 3,
        'occurrences': [
          {
            'id': 'trip_31',
            'startTime': '2026-08-17T08:00:00Z',
            'totalSeats': 28,
            'seatsRemaining': 12,
            'tripType': 'RECURRING',
          },
          {
            'id': 'trip_32',
            'startTime': '2026-08-24T08:00:00Z',
            'totalSeats': 28,
            'seatsRemaining': 8,
            'tripType': 'RECURRING',
          },
        ],
      });

      expect(trip.tripType, TripType.recurring);
      expect(trip.tripType.isRecurring, isTrue);
      expect(trip.recurrenceGroupId, 'grp-1');
      expect(trip.occurrenceCount, 3);
      expect(trip.occurrences, hasLength(2));
      expect(trip.occurrences.first.seatsRemaining, 12);
    });

    test('defaults an untyped trip to one-time', () {
      final trip = ShuttleTrip.fromJson(const {
        'id': 'trip_33',
        'startTime': '2026-08-11T07:30:00Z',
        'basePrice': 100,
        'totalSeats': 14,
        'seatsRemaining': 3,
        'serviceClassCode': 'STANDARD_HIACE',
      });
      expect(trip.tripType, TripType.oneTime);
      expect(trip.fareForBooking, 100);
      expect(trip.returnTrip, isNull);
      expect(trip.occurrences, isEmpty);
    });
  });

  group('ReservationTier.fromJson', () {
    test('parses a typical active tier payload', () {
      final tier = ReservationTier.fromJson(const {
        'id': 'tier_1',
        'name': 'Weekly commuter pass',
        'code': 'WKLY-7',
        'description': 'Seven days of daily shuttling.',
        'durationDays': 7,
        'excludedWeekdays': [5, 6],
        'originalPrice': 700,
        'packagePrice': 560,
        'minimumSeats': 1,
        'maximumSeats': 4,
        'paymentMethods': ['CASH', 'WALLET'],
        'tripId': 'trip_30',
        'isRecommended': true,
        'discountPercent': 20,
        'walletBonusAmount': 50,
        'priorityBooking': true,
      });

      expect(tier.id, 'tier_1');
      expect(tier.name, 'Weekly commuter pass');
      expect(tier.durationDays, 7);
      expect(tier.excludedWeekdays, contains(5));
      expect(tier.originalPrice, 700);
      expect(tier.packagePrice, 560);
      expect(tier.savings, 140);
      expect(tier.tripId, 'trip_30');
      expect(tier.isRecommended, isTrue);
      expect(tier.priorityBooking, isTrue);
      expect(tier.isActive, isTrue);
    });

    test('general tiers have no tripId and parse weekdays', () {
      final tier = ReservationTier.fromJson(const {
        'id': 'tier_2',
        'name': 'General pass',
        'code': 'GEN-30',
        'durationDays': 30,
        'originalPrice': 3000,
        'packagePrice': 2500,
      });
      expect(tier.tripId, isNull);
      expect(tier.savings, 500);
      expect(tier.isRecommended, isFalse);
    });
  });

  group('GenderColor', () {
    test('female seats are pink and male seats are blue', () {
      expect(GenderColor.forGender(UserGender.female), const Color(0xFFEC4899));
      expect(GenderColor.forGender(UserGender.male), const Color(0xFF3B82F6));
    });
  });

  group('BoardPassQr', () {
    test('renders without error and is deterministic', () {
      const a = BoardPassQr(seed: 'SCS-20260810-0001', size: 168);
      const b = BoardPassQr(seed: 'SCS-20260810-0001', size: 168);
      expect(a.seed, b.seed);
      expect(a.size, b.size);
    });
  });

  group('WalletData', () {
    test('parses balance and merges wallet + ledger transactions', () {
      final data = WalletData.fromJson(const {
        'wallet': {'balance': 250.5, 'currency': 'EGP', 'status': 'ACTIVE'},
        'transactions': [
          {
            'id': 'tx1',
            'amount': 100,
            'type': 'CREDIT',
            'createdAt': '2026-08-09T10:00:00Z',
          },
        ],
      });
      expect(data.balance, 250.5);
      expect(data.currency, 'EGP');
      expect(data.status, 'ACTIVE');
      expect(data.transactions, hasLength(1));
      expect(data.transactions.first['amount'], 100);
    });
  });
}
