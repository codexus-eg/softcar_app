# SoftCar Passenger

Production Flutter passenger app for the SoftCar Shuttle platform.

## Production connection

- API base: `https://softcarshuttle.com/api/mobile`
- Authentication, routes, reservations, wallet, notifications, reviews, support, and account data come from the VPS PostgreSQL-backed web service.
- Live tracking polls the reservation API and uses fresh driver GPS coordinates. It shows a timetable estimate only when GPS is unavailable or older than three minutes.
- The app contains no demo login, seeded trips, generated wallet balances, or offline reservation fallback.

## Verify

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The Android package id is `com.softcar.passengersss`. Store publishing requires a private release keystore configured by the application owner; local release builds currently use the debug key for direct device testing.
