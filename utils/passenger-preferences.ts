import AsyncStorage from '@react-native-async-storage/async-storage';
import { LOCAL_PREFERENCES_KEY } from './constants';

export type PassengerLocalPreferences = {
  favoriteTripIds: string[];
  emergencyContactPhone: string;
  reduceMotion: boolean;
  tripRemindersEnabled: boolean;
  reminderLeadMinutes: number;
};

const DEFAULT_PREFERENCES: PassengerLocalPreferences = {
  favoriteTripIds: [],
  emergencyContactPhone: '',
  reduceMotion: false,
  tripRemindersEnabled: true,
  reminderLeadMinutes: 30,
};

export async function loadPassengerPreferences(): Promise<PassengerLocalPreferences> {
  try {
    const raw = await AsyncStorage.getItem(LOCAL_PREFERENCES_KEY);
    if (!raw) return DEFAULT_PREFERENCES;
    const parsed = JSON.parse(raw) as Partial<PassengerLocalPreferences>;
    return {
      favoriteTripIds: Array.isArray(parsed.favoriteTripIds)
        ? parsed.favoriteTripIds.filter((value): value is string => typeof value === 'string')
        : [],
      emergencyContactPhone:
        typeof parsed.emergencyContactPhone === 'string' ? parsed.emergencyContactPhone : '',
      reduceMotion: parsed.reduceMotion === true,
      tripRemindersEnabled: parsed.tripRemindersEnabled !== false,
      reminderLeadMinutes: [15, 30, 60].includes(Number(parsed.reminderLeadMinutes))
        ? Number(parsed.reminderLeadMinutes)
        : 30,
    };
  } catch {
    return DEFAULT_PREFERENCES;
  }
}

export async function savePassengerPreferences(
  preferences: PassengerLocalPreferences
): Promise<void> {
  await AsyncStorage.setItem(LOCAL_PREFERENCES_KEY, JSON.stringify(preferences));
}
