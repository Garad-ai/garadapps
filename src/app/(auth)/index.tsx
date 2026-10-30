import { Link } from 'expo-router';
import { useState } from 'react';
import { Platform, StyleSheet, Text } from 'react-native';

import { AuthScreen } from '@/components/AuthScreen';
import { Button, Field, Notice } from '@/components/ui';
import { ApiError, login } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

type Step = 'credentials' | 'otp' | 'two_factor';

export default function SignInScreen() {
  const c = usePalette();
  const { t } = useI18n();
  const { signIn } = useAuth();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [step, setStep] = useState<Step>('credentials');
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const submit = async () => {
    if (!email.trim() || !password) {
      setError(t.required);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const result = await login({
        email: email.trim(),
        password,
        otp: step === 'otp' ? code.trim() : undefined,
        oneTimePassword: step === 'two_factor' ? code.trim() : undefined,
        deviceName: `Garad AI ${Platform.OS}`,
      });
      if (result.status === 'ok') {
        await signIn(result.token);
        return;
      }
      setStep('otp');
      setCode('');
      setInfo(t.otpSent);
    } catch (e) {
      if (e instanceof ApiError && e.type === 'two_factor' && step !== 'two_factor') {
        setStep('two_factor');
        setCode('');
        setInfo(null);
      } else {
        setError(errorMessage(e, t));
      }
    } finally {
      setLoading(false);
    }
  };

  const needsCode = step !== 'credentials';

  return (
    <AuthScreen title={t.signIn}>
      {info && <Notice tone="info">{info}</Notice>}
      {error && <Notice tone="error">{error}</Notice>}
      <Field
        label={t.email}
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        autoComplete="email"
        keyboardType="email-address"
        textContentType="emailAddress"
        editable={!needsCode}
      />
      <Field
        label={t.password}
        value={password}
        onChangeText={setPassword}
        secureTextEntry
        autoComplete="current-password"
        textContentType="password"
        editable={!needsCode}
        onSubmitEditing={needsCode ? undefined : submit}
      />
      {needsCode && (
        <Field
          label={step === 'otp' ? t.otpCode : t.twoFactorCode}
          value={code}
          onChangeText={setCode}
          keyboardType="number-pad"
          autoComplete="one-time-code"
          textContentType="oneTimeCode"
          autoFocus
          onSubmitEditing={submit}
        />
      )}
      <Button title={needsCode ? t.verify : t.signIn} onPress={submit} loading={loading} />
      <Link href="/forgot-password" style={[styles.link, { color: c.brand }]}>
        {t.forgotPassword}
      </Link>
      <Text style={[styles.footer, { color: c.muted }]}>
        {t.noAccount}{' '}
        <Link href="/register" style={{ color: c.brand, fontWeight: '600' }}>
          {t.signUp}
        </Link>
      </Text>
    </AuthScreen>
  );
}

const styles = StyleSheet.create({
  link: { textAlign: 'center', fontWeight: '600', paddingVertical: 6 },
  footer: { textAlign: 'center', fontSize: 15 },
});
