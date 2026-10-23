import type { CapacitorConfig } from '@capacitor/cli';

// 앱이 www/index.html(복사본)을 내장하지 않고 실제 라이브 사이트를 그대로 띄워요.
// 그래서 웹사이트 코드를 고칠 때마다 앱도 자동으로 최신 내용으로 보여요 (앱스토어 재심사 불필요).
// 단, 인터넷 연결이 꼭 필요해요. www/index.html은 cap sync가 요구하는 로컬 폴백용으로만 둠.
const config: CapacitorConfig = {
  appId: 'com.maytoon.app',
  appName: '메이툰',
  webDir: 'www',
  server: {
    url: 'https://maytoon07.github.io/maytoon/',
    cleartext: false
  },
  android: {
    backgroundColor: '#FBF8FA'
  },
  ios: {
    backgroundColor: '#FBF8FA'
  }
};

export default config;
