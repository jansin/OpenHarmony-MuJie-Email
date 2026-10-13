import { LogUtil } from './LogUtil';

const logger = new LogUtil('ErrorHandler');

export enum ErrorCode {
  UNKNOWN = 'E0000',
  NETWORK_ERROR = 'E0001',
  AUTHENTICATION_FAILED = 'E0002',
  INVALID_PARAMS = 'E0003',
  STORAGE_ERROR = 'E0004',
  SERVICE_UNAVAILABLE = 'E0005',
  TIMEOUT = 'E0006',
  NOT_FOUND = 'E0007',
  CONFLICT = 'E0008',
  RATE_LIMITED = 'E0009'
}

export interface ErrorContext {
  [key: string]: string | number | boolean | null;
}

export interface AppError {
  code: ErrorCode;
  message: string;
  originalError?: Error;
  context?: ErrorContext;
}

export function createError(code: ErrorCode, message: string, originalError?: Error, context?: ErrorContext): AppError {
  return { code, message, originalError, context };
}

export function wrapError(error: Error | string | object, defaultCode: ErrorCode = ErrorCode.UNKNOWN): AppError {
  if (error instanceof Error) {
    const code = inferErrorCode(error);
    return {
      code,
      message: error.message,
      originalError: error
    };
  }
  if (typeof error === 'string') {
    return {
      code: defaultCode,
      message: error
    };
  }
  return {
    code: defaultCode,
    message: JSON.stringify(error)
  };
}

function inferErrorCode(error: Error): ErrorCode {
  const message = error.message.toLowerCase();
  if (message.includes('network') || message.includes('connection') || message.includes('timeout')) {
    return ErrorCode.NETWORK_ERROR;
  }
  if (message.includes('auth') || message.includes('login') || message.includes('password')) {
    return ErrorCode.AUTHENTICATION_FAILED;
  }
  if (message.includes('storage') || message.includes('database') || message.includes('rdb')) {
    return ErrorCode.STORAGE_ERROR;
  }
  if (message.includes('timeout')) {
    return ErrorCode.TIMEOUT;
  }
  if (message.includes('not found') || message.includes('404')) {
    return ErrorCode.NOT_FOUND;
  }
  if (message.includes('conflict') || message.includes('409')) {
    return ErrorCode.CONFLICT;
  }
  return ErrorCode.UNKNOWN;
}

export function handleError(error: Error | string | object, context?: string): void {
  const appError = wrapError(error);
  logger.e(`[${appError.code}] ${appError.message}`, context ? `Context: ${context}` : undefined);
  if (appError.originalError) {
    logger.e(`Original error stack: ${appError.originalError.stack}`);
  }
}

export function handleErrorWithCallback(
  error: Error | string | object,
  callback: (appError: AppError) => void,
  context?: string
): void {
  const appError = wrapError(error);
  handleError(error, context);
  callback(appError);
}

export function safeExecute<T>(
  fn: () => T | Promise<T>,
  defaultValue: T,
  context?: string
): T {
  try {
    const result = fn();
    if (result instanceof Promise) {
      result.catch((e) => handleError(e, context));
    }
    return result as T;
  } catch (e) {
    handleError(e as Error, context);
    return defaultValue;
  }
}

export async function safeExecuteAsync<T>(
  fn: () => Promise<T>,
  defaultValue: T,
  context?: string
): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    handleError(e as Error, context);
    return defaultValue;
  }
}

export function getErrorMessage(error: Error | string | object): string {
  if (error instanceof Error) {
    return error.message;
  }
  if (typeof error === 'string') {
    return error;
  }
  return 'Unknown error';
}

export function getErrorCode(error: Error | string | object): ErrorCode {
  if (error instanceof Error) {
    return inferErrorCode(error);
  }
  return ErrorCode.UNKNOWN;
}