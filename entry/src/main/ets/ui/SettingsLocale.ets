import { i18n } from '@kit.LocalizationKit'
import { settingsText, settingsFormat } from './SettingsLocaleData'
export function settingsLanguage(language: string): string { return language === 'system' ? i18n.System.getSystemLanguage() : language }
export function localizedSettingsText(value: string, language: string): string { return settingsText(value, settingsLanguage(language)) }
export function localizedSettingsFormat(value: string, args: (string | number | boolean | null | undefined)[], language: string): string {
  return settingsFormat(value, args, settingsLanguage(language))
}
