import { Link, router } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, Text } from 'react-native';

import { AuthScreen } from '@/components/AuthScreen';
import { Button, Field, Notice } from '@/components/ui';
import { register } from '@/lib/api';
import { errorMessage } from '@/lib/errors';
import { useI18n } from '@/lib/i18n';
import { usePalette } from '@/lib/theme';

export default function RegisterScreen() {
  const c = usePalette();
  const { t } = useI18n();

  const [name, setName] = useState('');
  const [surname, setSurname] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const [loading, setLoading] = useState(false);

  const submit = async () => {
    if (!name.trim() || !surname.trim() || !email.trim() || !password) {
      setError(t.required);
      return;
    }
    setLoading(true);
    setError(null);
    try {
      await register({ name: name.trim(), surname: surname.trim(), email: email.trim(), password });
      setDone(true);
    } catch (e) {
      setError(errorMessage(e, t));
    } finally {
      setLoading(false);
    }
  };

  if (done) {
    return (
      <AuthScreen title={t.signUp}>
        <Notice tone="info">{t.registered}</Notice>
        <Button title={t.backToSignIn} onPress={() => router.replace('/')} />
      </AuthScreen>
    );
  }

  return (
    <AuthScreen title={t.signUp}>
      {error && <Notice tone="error">{error}</Notice>}
      <Field label={t.firstName} value={name} onChangeText={setName} autoComplete="given-name" />
      <Field
        label={t.lastName}
        value={surname}
        onChangeText={setSurname}
        autoComplete="family-name"
      />
      <Field
        label={t.email}
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        autoComplete="email"
        keyboardType="email-address"
      />
      <Field
        label={t.password}
        value={password}
        onChangeText={setPassword}
        secureTextEntry
        autoComplete="new-password"
        textContentType="newPassword"
      />
      <Button title={t.signUp} onPress={submit} loading={loading} />
      <Text style={[styles.footer, { color: c.muted }]}>
        {t.haveAccount}{' '}
        <Link href="/" style={{ color: c.brand, fontWeight: '600' }}>
          {t.signIn}
        </Link>
      </Text>
    </AuthScreen>
  );
}

const styles = StyleSheet.create({
  footer: { textAlign: 'center', fontSize: 15 },
});
