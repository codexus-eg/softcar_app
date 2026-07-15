import AsyncStorage from '@react-native-async-storage/async-storage';
import * as LocalAuthentication from 'expo-local-authentication';

const BIOMETRIC_KEY = 'softcar.passenger.biometric_enabled';

export async function canUseBiometrics() {
  const [hardware, enrolled] = await Promise.all([
    LocalAuthentication.hasHardwareAsync(),
    LocalAuthentication.isEnrolledAsync(),
  ]);
  return hardware && enrolled;
}

export async function authenticateDevice() {
  const result = await LocalAuthentication.authenticateAsync({
    promptMessage: 'فتح تطبيق سوفت كار',
    cancelLabel: 'إلغاء',
    fallbackLabel: 'استخدام رمز الجهاز',
    disableDeviceFallback: false,
  });
  return result.success;
}

export async function getBiometricEnabled() {
  return (await AsyncStorage.getItem(BIOMETRIC_KEY)) === 'true';
}

export async function setBiometricEnabled(enabled: boolean) {
  await AsyncStorage.setItem(BIOMETRIC_KEY, String(enabled));
}
