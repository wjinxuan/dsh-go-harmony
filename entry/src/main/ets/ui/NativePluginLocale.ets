import { i18n } from '@kit.LocalizationKit'
export function nativePluginLocale(language: string): string {
  return language === 'system' ? i18n.System.getSystemLanguage() : language === 'en' ? 'en' : 'zh-CN'
}
