import { promptAction } from '@kit.ArkUI';

export class ToastUtil {
  static show(msg: string, duration: number = 2000): void {
    try {
      promptAction.showToast({ message: msg, duration: duration });
    } catch (e) {}
  }

  static showError(msg: string): void {
    ToastUtil.show(msg, 3000);
  }

  static showSuccess(msg: string): void {
    ToastUtil.show(msg, 2000);
  }
}
