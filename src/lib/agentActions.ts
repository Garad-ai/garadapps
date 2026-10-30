import { Linking, Platform } from 'react-native';

/**
 * Phone actions requested by Garad Voice (see GARAD_APP_TOOLS in
 * Garad_ai/frontend/src/core/appShell.ts). Each action only opens something on the
 * phone; calls and messages open ready for the user to press call or send.
 * Messages go back to the model, which tells the user in their language.
 */
export type ActionResult = { ok: boolean; message: string };

const encode = encodeURIComponent;

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/** Keeps digits and a leading +. */
function phoneNumber(value: unknown): string {
  const raw = text(value);
  const digits = raw.replace(/\D/g, '');
  return raw.startsWith('+') && digits ? `+${digits}` : digits;
}

/** Opens the first link the phone can handle: the app first, then its website. */
async function openFirst(urls: string[]): Promise<boolean> {
  for (const url of urls) {
    try {
      await Linking.openURL(url);
      return true;
    } catch {
      // Not installed or not supported: try the next link.
    }
  }
  return false;
}

const APP_LINKS: Record<string, (search: string) => string[]> = {
  whatsapp: () => ['whatsapp://send', 'https://wa.me/'],
  facebook: () => ['fb://feed', 'https://www.facebook.com'],
  messenger: () => ['fb-messenger://', 'https://www.messenger.com'],
  instagram: () => ['instagram://app', 'https://www.instagram.com'],
  tiktok: (search) =>
    search ? [`https://www.tiktok.com/search?q=${encode(search)}`] : ['snssdk1233://', 'https://www.tiktok.com'],
  youtube: (search) =>
    search
      ? [`https://www.youtube.com/results?search_query=${encode(search)}`]
      : ['vnd.youtube://', 'https://www.youtube.com'],
  telegram: () => ['tg://', 'https://t.me'],
  x: () => ['twitter://timeline', 'https://x.com'],
  snapchat: () => ['snapchat://', 'https://www.snapchat.com'],
  gmail: () => ['googlegmail://', 'https://mail.google.com'],
  maps: (search) => [
    Platform.OS === 'ios' ? `maps://?q=${encode(search)}` : `geo:0,0?q=${encode(search)}`,
    `https://www.google.com/maps/search/?api=1&query=${encode(search)}`,
  ],
  phone: () => ['tel:'],
  messages: () => ['sms:'],
  play_store: (search) => [
    `market://search?q=${encode(search)}&c=apps`,
    `https://play.google.com/store/search?q=${encode(search)}&c=apps`,
  ],
};

export async function runAgentAction(name: string, args: Record<string, unknown>): Promise<ActionResult> {
  switch (name) {
    case 'open_app': {
      const app = text(args.app).toLowerCase();
      if (app === 'settings') {
        await Linking.openSettings();
        return { ok: true, message: 'Opened the phone settings for Garad AI.' };
      }
      const links = APP_LINKS[app];
      if (!links) return { ok: false, message: `Opening "${app}" is not supported yet.` };
      return (await openFirst(links(text(args.search))))
        ? { ok: true, message: `Opened ${app}.` }
        : { ok: false, message: `Could not open ${app} on this phone.` };
    }

    case 'open_website': {
      let url = text(args.url);
      if (url && !/^https?:\/\//i.test(url)) url = `https://${url}`;
      if (!/^https?:\/\/[^\s]+\.[^\s]+/i.test(url)) return { ok: false, message: 'That website address is not valid.' };
      return (await openFirst([url]))
        ? { ok: true, message: `Opened ${url}.` }
        : { ok: false, message: 'Could not open the website.' };
    }

    case 'call_phone': {
      const number = phoneNumber(args.phone_number);
      if (number.replace('+', '').length < 3) return { ok: false, message: 'The phone number is missing or too short.' };
      return (await openFirst([`tel:${number}`]))
        ? { ok: true, message: `The dialer is open with ${number}; the user presses call.` }
        : { ok: false, message: 'This phone cannot make calls.' };
    }

    case 'send_whatsapp_message': {
      const number = phoneNumber(args.phone_number).replace('+', '');
      const message = encode(text(args.message));
      const opened = await openFirst(
        number
          ? [`whatsapp://send?phone=${number}&text=${message}`, `https://wa.me/${number}?text=${message}`]
          : [`whatsapp://send?text=${message}`, `https://wa.me/?text=${message}`]
      );
      return opened
        ? {
            ok: true,
            message: number
              ? 'WhatsApp is open with the message ready; the user presses send.'
              : 'WhatsApp is open with the message ready; the user picks the chat and presses send.',
          }
        : { ok: false, message: 'WhatsApp could not be opened on this phone.' };
    }

    case 'send_sms': {
      const number = phoneNumber(args.phone_number);
      const body = encode(text(args.message));
      const separator = Platform.OS === 'ios' ? '&' : '?';
      return (await openFirst([`sms:${number}${separator}body=${body}`]))
        ? { ok: true, message: 'The messages app is open with the SMS ready; the user presses send.' }
        : { ok: false, message: 'The messages app could not be opened.' };
    }

    case 'navigate_to': {
      const destination = text(args.destination);
      if (!destination) return { ok: false, message: 'The destination is missing.' };
      const opened = await openFirst([
        Platform.OS === 'ios' ? `maps://?daddr=${encode(destination)}` : `google.navigation:q=${encode(destination)}`,
        `https://www.google.com/maps/dir/?api=1&destination=${encode(destination)}`,
      ]);
      return opened
        ? { ok: true, message: `Directions to ${destination} are open.` }
        : { ok: false, message: 'The maps app could not be opened.' };
    }

    default:
      return { ok: false, message: `The action "${name}" is not supported.` };
  }
}
