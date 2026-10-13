export class EmailTheme {
  background: string = '#F5F5F5';
  surface: string = '#FFFFFF';
  primary: string = '#007AFF';
  primaryVariant: string = '#0056CC';
  secondary: string = '#5856D6';
  error: string = '#FF3B30';
  onPrimary: string = '#FFFFFF';
  onSurface: string = '#1C1C1E';
  onBackground: string = '#1C1C1E';
  textPrimary: string = '#1C1C1E';
  textSecondary: string = '#6C6C70';
  textHint: string = '#AEAEB2';
  divider: string = '#D1D1D6';
  cardBackground: string = '#FFFFFF';
  selectedItem: string = '#E5F0FF';
  unreadBackground: string = '#F0F7FF';
  avatarColors: string[] = [];
  success: string = '#34C759';
  warning: string = '#FF9500';
  link: string = '#007AFF';
  warningBackground: string = '#FFF8E1';
  infoBackground: string = '#E5F0FF';
}

export const LIGHT_THEME: EmailTheme = {
  background: '#F5F5F5',
  surface: '#FFFFFF',
  primary: '#007AFF',
  primaryVariant: '#0056CC',
  secondary: '#5856D6',
  error: '#FF3B30',
  onPrimary: '#FFFFFF',
  onSurface: '#1C1C1E',
  onBackground: '#1C1C1E',
  textPrimary: '#1C1C1E',
  textSecondary: '#6C6C70',
  textHint: '#AEAEB2',
  divider: '#D1D1D6',
  cardBackground: '#FFFFFF',
  selectedItem: '#E5F0FF',
  unreadBackground: '#F0F7FF',
  avatarColors: ['#007AFF', '#FF3B30', '#34C759', '#FF9500', '#AF52DE', '#5AC8FA', '#FF6482', '#32D74B',
    '#64D2FF', '#A2845E', '#FF9F0A', '#BF5AF2', '#0A84FF', '#30D158', '#FFD60A', '#7C7C82'],
  success: '#34C759',
  warning: '#FF9500',
  link: '#007AFF',
  warningBackground: '#FFF8E1',
  infoBackground: '#E5F0FF'
};

export const DARK_THEME: EmailTheme = {
  background: '#000000',
  surface: '#1C1C1E',
  primary: '#0A84FF',
  primaryVariant: '#0056CC',
  secondary: '#5E5CE6',
  error: '#FF453A',
  onPrimary: '#FFFFFF',
  onSurface: '#F5F5F5',
  onBackground: '#F5F5F5',
  textPrimary: '#F5F5F5',
  textSecondary: '#AEAEB2',
  textHint: '#636366',
  divider: '#38383A',
  cardBackground: '#1C1C1E',
  selectedItem: '#1A2A44',
  unreadBackground: '#1A1A24',
  avatarColors: ['#0A84FF', '#FF453A', '#30D158', '#FF9F0A', '#BF5AF2', '#64D2FF', '#FF6482', '#32D74B',
    '#5AC8FA', '#A2845E', '#FF9F0A', '#BF5AF2', '#0A84FF', '#30D158', '#FFD60A', '#7C7C82'],
  success: '#30D158',
  warning: '#FF9F0A',
  link: '#0A84FF',
  warningBackground: '#2A1F00',
  infoBackground: '#001A33'
};

const THEME_DARK_STORAGE_KEY: string = 'isDarkMode';

export function initializeEmailTheme(): void {
  const storedDark = AppStorage.Get<boolean>(THEME_DARK_STORAGE_KEY);
  AppStorage.SetOrCreate<boolean>(THEME_DARK_STORAGE_KEY, storedDark ?? false);
}

export function setEmailDarkMode(isDark: boolean): void {
  AppStorage.SetOrCreate<boolean>(THEME_DARK_STORAGE_KEY, isDark);
}
