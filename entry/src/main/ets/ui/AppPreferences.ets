import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ACCENTS } from './DshTheme';

export interface AppPreferenceValues {
  accentId: string;
  themeMode: string;
  fontSize: number;
}

const FILE_NAME: string = 'dsh-appearance';
const VALUE_KEY: string = 'appearance';
const ONBOARDING_COMPLETE: string = 'onboarding-complete-v1';

export async function loadAppPreferences(context: common.Context): Promise<AppPreferenceValues> {
  const store = await preferences.getPreferences(context, FILE_NAME);
  const encoded = store.getSync(VALUE_KEY, '{}') as string;
  let value: AppPreferenceValues;
  try {
    value = JSON.parse(encoded) as AppPreferenceValues;
  } catch {
    return { accentId: 'mist', themeMode: 'system', fontSize: 16 };
  }
  return {
    accentId: ACCENTS.some((accent) => accent.id === value?.accentId) ? value.accentId : 'mist',
    themeMode: ['light', 'dark', 'system'].includes(value?.themeMode) ? value.themeMode : 'system',
    fontSize: [14, 16, 18, 20].includes(value?.fontSize) ? value.fontSize : 16
  };
}

export async function saveAppPreferences(context: common.Context, value: AppPreferenceValues): Promise<void> {
  const store = await preferences.getPreferences(context, FILE_NAME);
  store.putSync(VALUE_KEY, JSON.stringify(value));
  await store.flush();
}

export async function loadOnboardingComplete(context: common.Context): Promise<boolean> {
  const store = await preferences.getPreferences(context, FILE_NAME);
  return store.getSync(ONBOARDING_COMPLETE, false) === true;
}

export async function saveOnboardingComplete(context: common.Context): Promise<void> {
  const store = await preferences.getPreferences(context, FILE_NAME);
  store.putSync(ONBOARDING_COMPLETE, true);
  await store.flush();
}
