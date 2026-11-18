export const localizedSettingsText = value => value;
export const localizedSettingsFormat = (value, args) => value.replace(/\{(\d+)\}/g, (_match, index) => String(args[Number(index)] ?? ''));

export const settingsLanguage = value => value === 'system' || !value ? 'zh' : value;
