import { router } from 'expo-router';
import { useState } from 'react';

import { AuthScreen } from '@/components/AuthScreen';
import { Button, Field, Notice } from '@/components/ui';
import { forgotPassword } from '@/lib/api';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';

export default function ForgotPasswordScreen() {
  const { t } = useI18n();
  const [email, setEmail] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const [loading, setLoading] = useState(false);

  const submit = async () => {
    if (!email.trim()) {
      setError(t.required);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      await forgotPassword(email.trim());
      setSent(true);
    } catch (e) {
      setError(errorMessage(e, t));
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthScreen title={t.forgotPassword}>
      {sent && <Notice tone="info">{t.resetSent}</Notice>}
      {error && <Notice tone="error">{error}</Notice>}
      {!sent && (
        <>
          <Field
            label={t.email}
            value={email}
            onChangeText={setEmail}
            autoCapitalize="none"
            autoComplete="email"
            keyboardType="email-address"
            onSubmitEditing={submit}
          />
          <Button title={t.sendResetLink} onPress={submit} loading={loading} />
        </>
      )}
      <Button title={t.backToSignIn} variant="secondary" onPress={() => router.replace('/')} />
    </AuthScreen>
  );
}
