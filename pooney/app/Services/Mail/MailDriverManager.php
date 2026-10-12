<?php

namespace App\Services\Mail;

use App\Services\Settings;
use Aws\Ses\SesClient;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Mail;
use PHPMailer\PHPMailer\PHPMailer;
use RuntimeException;

/**
 * Delivers an already rendered HTML e-mail through the driver chosen in
 * Admin → Beállítások → E-mail küldés. Every driver can be tested from the admin.
 */
class MailDriverManager
{
    public function __construct(private readonly Settings $settings) {}

    public function driver(): string
    {
        return (string) $this->settings->get('mail.driver', 'log');
    }

    public function send(string $to, string $subject, string $html, ?string $driver = null): void
    {
        $driver ??= $this->driver();

        match ($driver) {
            'smtp' => $this->viaLaravel('pooney_smtp', $to, $subject, $html),
            'ses' => $this->viaSes($to, $subject, $html),
            'phpmailer' => $this->viaPhpMailer($to, $subject, $html),
            'http_api' => $this->viaHttpApi($to, $subject, $html),
            default => $this->viaLaravel('log', $to, $subject, $html),
        };
    }

    private function from(): array
    {
        return [(string) $this->settings->get('mail.from_address'), (string) $this->settings->get('mail.from_name')];
    }

    private function viaLaravel(string $mailer, string $to, string $subject, string $html): void
    {
        if ($mailer === 'pooney_smtp') {
            config(['mail.mailers.pooney_smtp' => [
                'transport' => 'smtp',
                'host' => $this->settings->get('mail.smtp.host'),
                'port' => (int) $this->settings->get('mail.smtp.port', 587),
                'scheme' => $this->settings->get('mail.smtp.encryption') === 'ssl' ? 'smtps' : 'smtp',
                'username' => $this->settings->get('mail.smtp.username'),
                'password' => $this->settings->get('mail.smtp.password'),
                'timeout' => 20,
            ]]);
            Mail::purge('pooney_smtp');
        }

        [$fromAddress, $fromName] = $this->from();
        $replyTo = (string) $this->settings->get('mail.reply_to');

        Mail::mailer($mailer)->html($html, function ($message) use ($to, $subject, $fromAddress, $fromName, $replyTo) {
            $message->to($to)->subject($subject)->from($fromAddress, $fromName);
            if ($replyTo !== '') {
                $message->replyTo($replyTo);
            }
        });
    }

    private function viaSes(string $to, string $subject, string $html): void
    {
        [$fromAddress, $fromName] = $this->from();

        $client = new SesClient([
            'version' => '2010-12-01',
            'region' => $this->settings->get('mail.ses.region', 'eu-central-1'),
            'credentials' => ['key' => $this->settings->get('mail.ses.key'), 'secret' => $this->settings->get('mail.ses.secret')],
        ]);

        $client->sendEmail([
            'Source' => sprintf('%s <%s>', $fromName, $fromAddress),
            'Destination' => ['ToAddresses' => [$to]],
            'ReplyToAddresses' => array_filter([(string) $this->settings->get('mail.reply_to')]),
            'Message' => [
                'Subject' => ['Data' => $subject, 'Charset' => 'UTF-8'],
                'Body' => [
                    'Html' => ['Data' => $html, 'Charset' => 'UTF-8'],
                    'Text' => ['Data' => $this->plainText($html), 'Charset' => 'UTF-8'],
                ],
            ],
        ]);
    }

    private function viaPhpMailer(string $to, string $subject, string $html): void
    {
        [$fromAddress, $fromName] = $this->from();

        $mail = new PHPMailer(true);
        $mail->isSMTP();
        $mail->CharSet = PHPMailer::CHARSET_UTF8;
        $mail->Host = (string) $this->settings->get('mail.smtp.host');
        $mail->Port = (int) $this->settings->get('mail.smtp.port', 587);
        $mail->SMTPAuth = filled($this->settings->get('mail.smtp.username'));
        $mail->Username = (string) $this->settings->get('mail.smtp.username');
        $mail->Password = (string) $this->settings->get('mail.smtp.password');
        $mail->SMTPSecure = match ($this->settings->get('mail.smtp.encryption')) {
            'ssl' => PHPMailer::ENCRYPTION_SMTPS,
            'tls' => PHPMailer::ENCRYPTION_STARTTLS,
            default => '',
        };
        $mail->Timeout = 20;
        $mail->setFrom($fromAddress, $fromName);
        if ($reply = $this->settings->get('mail.reply_to')) {
            $mail->addReplyTo($reply);
        }
        $mail->addAddress($to);
        $mail->isHTML(true);
        $mail->Subject = $subject;
        $mail->Body = $html;
        $mail->AltBody = $this->plainText($html);
        $mail->send();
    }

    /**
     * Generic JSON HTTP API (Brevo, Mailgun-like, or the service used on demcsak.hu).
     * The payload is built from an admin-editable template, values are JSON-escaped.
     */
    private function viaHttpApi(string $to, string $subject, string $html): void
    {
        $endpoint = (string) $this->settings->get('mail.http_api.endpoint');
        if ($endpoint === '') {
            throw new RuntimeException('HTTP API végpont nincs beállítva.');
        }

        [$fromAddress, $fromName] = $this->from();
        $escape = fn (string $v) => substr(json_encode($v, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), 1, -1);
        $payload = strtr((string) $this->settings->get('mail.http_api.payload_template'), [
            '{{to}}' => $escape($to), '{{subject}}' => $escape($subject), '{{html}}' => $escape($html),
            '{{text}}' => $escape($this->plainText($html)), '{{from}}' => $escape($fromAddress), '{{from_name}}' => $escape($fromName),
        ]);

        if (json_decode($payload) === null) {
            throw new RuntimeException('A HTTP API payload sablon nem érvényes JSON.');
        }

        Http::withToken((string) $this->settings->get('mail.http_api.token'))
            ->withBody($payload, 'application/json')
            ->timeout(20)
            ->post($endpoint)
            ->throw();
    }

    private function plainText(string $html): string
    {
        return trim(html_entity_decode(strip_tags(preg_replace('/<(br|\/p|\/tr|\/h\d)>/i', "\n", $html)), ENT_QUOTES, 'UTF-8'));
    }
}
