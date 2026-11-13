import { UIContext } from '@kit.ArkUI'

// DSH Go v1.0.15 accent.dart, palette.dart and semantic_colors.dart.
// The six neutral ramps use the upstream OKLCH hue/chroma transform.
export interface ThemeColors {
  background: string;
  backgroundTop: string;
  backgroundBottom: string;
  surface: string;
  surfaceAlt: string;
  text: string;
  muted: string;
  hint: string;
  border: string;
  codeSurface: string;
  codeHeader: string;
  codeBorder: string;
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onPrimaryContainer: string;
  bubble: string;
  success: string;
  warning: string;
  danger: string;
}

export interface DshAccent {
  id: string;
  name: string;
  nameEn: string;
  light: string;
  dark: string;
}

interface ThemePreset {
  accent: DshAccent;
  light: ThemeColors;
  dark: ThemeColors;
}

const PRESETS: ThemePreset[] = [
  {
    accent: { id: 'mist', name: '雾蓝', nameEn: 'Mist', light: '#4B67B4', dark: '#97B1F0' },
    light: {
      background: '#F0F4FD', backgroundTop: '#EBF1FE', backgroundBottom: '#F6F7FC',
      surface: '#FBFCFF', surfaceAlt: '#EEF1F9', text: '#1E232E',
      muted: '#4F5562', hint: '#646974', border: '#DCE0E8',
      codeSurface: '#EDF0F6', codeHeader: '#E7EBF3', codeBorder: '#DBDEE5',
      primary: '#4B67B4', onPrimary: '#FFFFFF', primaryContainer: '#DEE8FF',
      onPrimaryContainer: '#213262', bubble: '#D9E4FD', success: '#337250',
      warning: '#936123', danger: '#A54743'
    },
    dark: {
      background: '#1C1F28', backgroundTop: '#1D222C', backgroundBottom: '#1B1C23',
      surface: '#232730', surfaceAlt: '#272C36', text: '#E6E9F0',
      muted: '#B6BBC5', hint: '#9A9EA9', border: '#343841',
      codeSurface: '#14171E', codeHeader: '#1A1E26', codeBorder: '#2F333A',
      primary: '#97B1F0', onPrimary: '#121C34', primaryContainer: '#2E3C5F',
      onPrimaryContainer: '#D8E1F6', bubble: '#293144', success: '#8BCCA6',
      warning: '#E6BD7C', danger: '#E69089'
    }
  },
  {
    accent: { id: 'daiqing', name: '黛青', nameEn: 'Teal', light: '#236185', dark: '#8CB9D7' },
    light: {
      background: '#EDF5FB', backgroundTop: '#E7F3FB', backgroundBottom: '#F4F8FB',
      surface: '#FAFCFE', surfaceAlt: '#ECF2F7', text: '#1A252C',
      muted: '#4B575F', hint: '#616B72', border: '#DAE1E6',
      codeSurface: '#EBF1F5', codeHeader: '#E5ECF1', codeBorder: '#D9DFE4',
      primary: '#236185', onPrimary: '#FFFFFF', primaryContainer: '#DBEAF5',
      onPrimaryContainer: '#123950', bubble: '#D6E7F3', success: '#337250',
      warning: '#936123', danger: '#A54743'
    },
    dark: {
      background: '#192026', backgroundTop: '#1A232A', backgroundBottom: '#181D22',
      surface: '#20282E', surfaceAlt: '#242D34', text: '#E4EAEF',
      muted: '#B3BCC3', hint: '#96A0A7', border: '#31393F',
      codeSurface: '#12181D', codeHeader: '#171F24', codeBorder: '#2D3438',
      primary: '#8CB9D7', onPrimary: '#0D1F2B', primaryContainer: '#274152',
      onPrimaryContainer: '#D5E3ED', bubble: '#26333C', success: '#8BCCA6',
      warning: '#E6BD7C', danger: '#E69089'
    }
  },
  {
    accent: { id: 'dusk', name: '暮紫', nameEn: 'Dusk', light: '#726291', dark: '#B8ABD2' },
    light: {
      background: '#F4F3FB', backgroundTop: '#F1EFFB', backgroundBottom: '#F8F6FA',
      surface: '#FCFCFE', surfaceAlt: '#F2F0F7', text: '#24212B',
      muted: '#55535F', hint: '#696771', border: '#E0DFE6',
      codeSurface: '#F0EFF5', codeHeader: '#EBEAF1', codeBorder: '#DEDDE3',
      primary: '#726291', onPrimary: '#FFFFFF', primaryContainer: '#EAE5F4',
      onPrimaryContainer: '#392F4C', bubble: '#E6E1F1', success: '#337250',
      warning: '#936123', danger: '#A54743'
    },
    dark: {
      background: '#201E26', backgroundTop: '#22212A', backgroundBottom: '#1E1B21',
      surface: '#27262E', surfaceAlt: '#2C2B34', text: '#E9E8EE',
      muted: '#BBB9C3', hint: '#9F9CA6', border: '#38373F',
      codeSurface: '#17161C', codeHeader: '#1E1D24', codeBorder: '#333238',
      primary: '#B8ABD2', onPrimary: '#1F1A29', primaryContainer: '#40394F',
      onPrimaryContainer: '#E2DEEC', bubble: '#332F3B', success: '#8BCCA6',
      warning: '#E6BD7C', danger: '#E69089'
    }
  },
  {
    accent: { id: 'turquoise', name: '松石', nameEn: 'Aqua', light: '#34766F', dark: '#8DBEB7' },
    light: {
      background: '#EEF6F5', backgroundTop: '#E8F4F3', backgroundBottom: '#F4F8F9',
      surface: '#FAFDFD', surfaceAlt: '#ECF3F3', text: '#1B2625',
      muted: '#4B5857', hint: '#616B6B', border: '#DAE2E1',
      codeSurface: '#ECF1F1', codeHeader: '#E5EDEC', codeBorder: '#D9E0DF',
      primary: '#34766F', onPrimary: '#FFFFFF', primaryContainer: '#DBECE9',
      onPrimaryContainer: '#123D39', bubble: '#D6E8E6', success: '#337250',
      warning: '#936123', danger: '#A54743'
    },
    dark: {
      background: '#192121', backgroundTop: '#1A2423', backgroundBottom: '#181E1E',
      surface: '#202928', surfaceAlt: '#242E2D', text: '#E4EBEA',
      muted: '#B4BDBC', hint: '#96A1A0', border: '#313A39',
      codeSurface: '#121918', codeHeader: '#18201F', codeBorder: '#2E3433',
      primary: '#8DBEB7', onPrimary: '#0D211F', primaryContainer: '#274340',
      onPrimaryContainer: '#D6E5E2', bubble: '#263533', success: '#8BCCA6',
      warning: '#E6BD7C', danger: '#E69089'
    }
  },
  {
    accent: { id: 'amber', name: '琥珀', nameEn: 'Amber', light: '#8D6636', dark: '#CCAC87' },
    light: {
      background: '#F8F3ED', backgroundTop: '#F7F0E7', backgroundBottom: '#F9F7F4',
      surface: '#FDFCFA', surfaceAlt: '#F4F1EB', text: '#28221A',
      muted: '#5B544B', hint: '#6E6860', border: '#E4DFDA',
      codeSurface: '#F3EFEB', codeHeader: '#EFEAE5', codeBorder: '#E1DDD9',
      primary: '#8D6636', onPrimary: '#FFFFFF', primaryContainer: '#F2E6D9',
      onPrimaryContainer: '#483011', bubble: '#EEE2D3', success: '#337250',
      warning: '#936123', danger: '#A54743'
    },
    dark: {
      background: '#231F18', backgroundTop: '#27211A', backgroundBottom: '#1F1C17',
      surface: '#2B2620', surfaceAlt: '#312B24', text: '#ECE8E4',
      muted: '#BFBAB3', hint: '#A29D96', border: '#3C3731',
      codeSurface: '#1A1612', codeHeader: '#221D18', codeBorder: '#36322D',
      primary: '#CCAC87', onPrimary: '#271A0C', primaryContainer: '#4C3A25',
      onPrimaryContainer: '#EADFD3', bubble: '#392F24', success: '#8BCCA6',
      warning: '#E6BD7C', danger: '#E69089'
    }
  },
  {
    accent: { id: 'graphite', name: '石墨', nameEn: 'Slate', light: '#2C2E32', dark: '#E5E8ED' },
    light: {
      background: '#F3F4F6', backgroundTop: '#EFF1F4', backgroundBottom: '#F7F7F8',
      surface: '#FCFCFD', surfaceAlt: '#F0F1F3', text: '#222326',
      muted: '#535558', hint: '#67696C', border: '#DFE0E2',
      codeSurface: '#EFF0F1', codeHeader: '#EAEBED', codeBorder: '#DDDEE0',
      primary: '#2C2E32', onPrimary: '#FFFFFF', primaryContainer: '#E3E6EC',
      onPrimaryContainer: '#2C2E32', bubble: '#E0E3E8', success: '#337250',
      warning: '#936123', danger: '#A54743'
    },
    dark: {
      background: '#1E1F21', backgroundTop: '#212224', backgroundBottom: '#1C1C1E',
      surface: '#262729', surfaceAlt: '#2A2C2E', text: '#E8E9EB',
      muted: '#B9BBBD', hint: '#9D9EA1', border: '#37383A',
      codeSurface: '#161719', codeHeader: '#1D1E20', codeBorder: '#323335',
      primary: '#E5E8ED', onPrimary: '#191B1E', primaryContainer: '#3B3D41',
      onPrimaryContainer: '#DEE1E7', bubble: '#2E3034', success: '#8BCCA6',
      warning: '#E6BD7C', danger: '#E69089'
    }
  },
]

export const ACCENTS: DshAccent[] = PRESETS.map((preset: ThemePreset) => preset.accent)

export function themeColors(accentId: string = 'mist', dark: boolean = false): ThemeColors {
  const preset = PRESETS.find((item: ThemePreset) => item.accent.id === accentId) ?? PRESETS[0]
  return dark ? preset.dark : preset.light
}

export class DshType {
  static readonly display: number = 28
  static readonly heading: number = 22
  static readonly title: number = 18
  static readonly body: number = 16
  static readonly compact: number = 14
  static readonly label: number = 12
  static readonly mono: number = 13
  static readonly monoFamily: string = 'JetBrainsMono'
  static readonly bodyHeight: number = 1.65
  static readonly monoHeight: number = 1.55
}

export class DshSpace {
  static readonly xs: number = 4
  static readonly sm: number = 8
  static readonly md: number = 12
  static readonly lg: number = 16
  static readonly xl: number = 20
  static readonly xxl: number = 24
  static readonly gutter: number = 16
  static readonly readingWidth: number = 720
  static readonly cardRadius: number = 14
  static readonly bubbleRadius: number = 20
  static readonly sheetRadius: number = 28
}

// DSH Go app_icons.dart roles mapped to its bundled Phosphor font subset.
export class DshGlyphs {
  static readonly family: string = 'DshIcons'
  static readonly back: string = '\uE000'
  static readonly close: string = '\uE002'
  static readonly menu: string = '\uE003'
  static readonly more: string = '\uE004'
  static readonly disclosure: string = '\uE006'
  static readonly expand: string = '\uE007'
  static readonly openExternal: string = '\uE00A'
  static readonly allFeatures: string = '\uE00C'
  static readonly features: string = '\uE00C'
  static readonly web: string = '\uE00D'
  static readonly latest: string = '\uE00E'
  static readonly switchHost: string = '\uE011'
  static readonly send: string = '\uE014'
  static readonly stop: string = '\uE015'
  static readonly voice: string = '\uE016'
  static readonly folder: string = '\uE089'
  static readonly folderOpen: string = '\uE01C'
  static readonly copy: string = '\uE01E'
  static readonly refresh: string = '\uE024'
  static readonly check: string = '\uE02F'
  static readonly add: string = '\uE030'
  static readonly search: string = '\uE03A'
  static readonly settings: string = '\uE03C'
  static readonly newChat: string = '\uE03F'
  static readonly archive: string = '\uE043'
  static readonly pin: string = '\uE045'
  static readonly pinActive: string = '\uE046'
  static readonly terminal: string = '\uE04D'
  static readonly model: string = '\uE077'
  static readonly host: string = '\uE079'
  static readonly file: string = '\uE08F'
  static readonly plugin: string = '\uE0A0'
  static readonly chat: string = '\uE0CA'
}

export function registerDshFonts(context: UIContext): void {
  const font = context.getFont()
  font.registerFont({ familyName: DshGlyphs.family, familySrc: $rawfile('fonts/DshIcons.ttf') })
  font.registerFont({ familyName: DshType.monoFamily, familySrc: $rawfile('fonts/JetBrainsMono-Regular.ttf') })
}
