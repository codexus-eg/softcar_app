import React from 'react';
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';

export type PassengerDriverAssistContact = {
  fullName?: string | null;
  phone?: string | null;
  carModel?: string | null;
  carPlateNumber?: string | null;
  photoUrl?: string | null;
  carPhotoUrl?: string | null;
  image?: string | null;
};

type PassengerDriverAssistCardProps = {
  driver: PassengerDriverAssistContact | null | undefined;
  emptyLabel?: string;
  onCallDriver: (phone: string | null | undefined) => void;
};

export function PassengerDriverAssistCard({
  driver,
  emptyLabel = 'سيتم تعيين السائق قريبًا',
  onCallDriver,
}: PassengerDriverAssistCardProps) {
  if (!driver) return null;

  const avatarSource = driver.photoUrl || driver.image || null;
  const vehiclePhoto = driver.carPhotoUrl || null;
  const driverInitial = (driver.fullName || 'D').trim().charAt(0).toUpperCase();
  const callLabel = driver.phone ? 'اتصال بالسائق' : 'رقم السائق غير متاح بعد';

  return (
    <View style={styles.card}>
      <View style={styles.headerRow}>
        <View style={styles.avatarShell}>
          {avatarSource ? (
            <Image source={{ uri: avatarSource }} style={styles.avatarImage} />
          ) : (
            <View style={styles.avatarFallback}>
              <Text style={styles.avatarFallbackText}>{driverInitial}</Text>
            </View>
          )}
        </View>
        <View style={styles.copy}>
          <Text style={styles.title}>السائق: {driver.fullName || emptyLabel}</Text>
          <Text style={styles.meta}>
            {driver.carModel || 'مركبة الرحلة'}
            {driver.carPlateNumber ? ` • ${driver.carPlateNumber}` : ''}
          </Text>
        </View>
      </View>
      {vehiclePhoto ? <Image source={{ uri: vehiclePhoto }} style={styles.vehicleImage} /> : null}
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={callLabel}
        style={[styles.button, !driver.phone && styles.disabledButton]}
        onPress={() => {
          onCallDriver(driver.phone);
        }}
        disabled={!driver.phone}
      >
        <Text style={styles.buttonText}>{callLabel}</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#24445a',
    backgroundColor: '#0A0A0A',
    padding: 12,
    gap: 10,
  },
  headerRow: {
    flexDirection: 'row-reverse',
    alignItems: 'center',
    gap: 12,
  },
  avatarShell: {
    width: 52,
    height: 52,
    borderRadius: 18,
    overflow: 'hidden',
    backgroundColor: '#102235',
  },
  avatarImage: {
    width: '100%',
    height: '100%',
  },
  avatarFallback: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#D32F2F',
  },
  avatarFallbackText: {
    color: '#f8fafc',
    fontSize: 18,
    fontWeight: '900',
  },
  copy: {
    flex: 1,
    gap: 4,
  },
  title: {
    color: '#f8fafc',
    fontSize: 15,
    fontWeight: '800',
    textAlign: 'right',
  },
  meta: {
    color: '#9fb5cc',
    fontSize: 12,
    textAlign: 'right',
  },
  vehicleImage: {
    width: '100%',
    height: 126,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#1f3652',
    backgroundColor: '#081120',
  },
  button: {
    minHeight: 46,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#1f7a8c',
    backgroundColor: '#0A0A0A',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
  },
  disabledButton: {
    opacity: 0.5,
  },
  buttonText: {
    color: '#ccfbf1',
    fontSize: 13,
    fontWeight: '800',
  },
});
