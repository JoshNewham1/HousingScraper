import Mailjet from 'node-mailjet';

export interface EmailOptions {
  from: string;
  to: string;
  subject: string;
  html: string;
}

/**
 * Interface for email providers to allow easy swapping in the future.
 */
export interface EmailProvider {
  sendEmail(options: EmailOptions): Promise<void>;
}

/**
 * Mailjet implementation of the EmailProvider interface.
 */
class MailjetProvider implements EmailProvider {
  private mailjet: Mailjet;

  constructor() {
    const publicKey = process.env.MJ_APIKEY_PUBLIC;
    const privateKey = process.env.MJ_APIKEY_PRIVATE;

    if (!publicKey || !privateKey) {
      throw new Error("Mailjet API keys (MJ_APIKEY_PUBLIC, MJ_APIKEY_PRIVATE) are missing.");
    }

    this.mailjet = new Mailjet({
      apiKey: publicKey,
      apiSecret: privateKey
    });
  }

  async sendEmail(options: EmailOptions): Promise<void> {
    await this.mailjet
      .post('send', { version: 'v3.1' })
      .request({
        Messages: [
          {
            From: {
              Email: options.from,
              Name: "Housing Scraper"
            },
            To: [
              {
                Email: options.to
              }
            ],
            Subject: options.subject,
            HTMLPart: options.html
          }
        ]
      });
  }
}

// Current active provider
const provider: EmailProvider = new MailjetProvider();

/**
 * Abstracted function to send email using the configured provider.
 */
export const sendEmail = async (options: EmailOptions): Promise<void> => {
  return provider.sendEmail(options);
};
