<?php

namespace App\Services\Mail;

use App\Jobs\SendTemplatedEmail;
use App\Models\Complaint;
use App\Models\EmailLog;
use App\Models\EmailTemplate;
use App\Models\NewsletterSubscriber;
use App\Models\Order;
use App\Models\User;
use App\Services\Settings;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\URL;
use Throwable;

class TemplateMailer
{
    public function __construct(
        private readonly TemplateRenderer $renderer,
        private readonly MailDriverManager $drivers,
        private readonly Settings $settings,
    ) {}

    /** Queue a templated e-mail (processed by the queue worker / cron). */
    public function send(string $templateKey, string $to, array $vars = [], ?Model $related = null): void
    {
        $log = EmailLog::create([
            'to' => $to,
            'template_key' => $templateKey,
            'status' => 'queued',
            'related_type' => $related?->getMorphClass(),
            'related_id' => $related?->getKey(),
        ]);

        SendTemplatedEmail::dispatch($log->id, $templateKey, $to, $vars);
    }

    /** Render + deliver immediately. Returns the log entry. */
    public function deliver(string $templateKey, string $to, array $vars = [], ?EmailLog $log = null): EmailLog
    {
        $log ??= EmailLog::create(['to' => $to, 'template_key' => $templateKey, 'status' => 'queued']);

        try {
            $template = EmailTemplate::where('key', $templateKey)->where('is_active', true)->first();
            if (! $template) {
                $log->update(['status' => 'skipped', 'error' => 'Sablon nem létezik vagy inaktív.']);

                return $log;
            }

            $vars = $this->baseVars() + $vars;
            $subject = $this->renderer->render($template->subject, $vars);
            $html = view('emails.layout', [
                'subject' => $subject,
                'body' => $this->renderer->render($template->body, $vars),
                'vars' => $vars,
            ])->render();

            $this->drivers->send($to, $subject, $html);
            $log->update(['subject' => $subject, 'driver' => $this->drivers->driver(), 'status' => 'sent', 'sent_at' => now(), 'error' => null]);
        } catch (Throwable $e) {
            $log->update(['driver' => $this->drivers->driver(), 'status' => 'failed', 'error' => mb_substr($e->getMessage(), 0, 2000)]);
            throw $e;
        }

        return $log;
    }

    public function baseVars(): array
    {
        return [
            'site_name' => $this->settings->get('site.name'),
            'site_url' => url('/'),
            'support_email' => $this->settings->get('site.email'),
            'year' => date('Y'),
        ];
    }

    public function orderVars(Order $order): array
    {
        $order->loadMissing('items');
        $rows = $order->items->map(fn ($i) => sprintf(
            '<tr><td style="padding:6px 0">%s%s × %d</td><td style="padding:6px 0;text-align:right">%s</td></tr>',
            e($i->name), $i->variant_name ? ' <small>('.e($i->variant_name).')</small>' : '', $i->quantity, huf($i->line_gross)
        ))->implode('');

        return [
            'customer_name' => $order->customer_name,
            'order_number' => $order->number,
            'order_total' => huf($order->total_gross),
            'order_status' => $order->status->label(),
            'payment_method' => __('payment.'.$order->payment_method),
            'tracking_url' => $order->trackingUrl(),
            'invoice_url' => $order->invoiceUrl() ?? '',
            'tracking_button' => $this->renderer->button($order->trackingUrl(), 'Rendelésem követése'),
            'invoice_button' => $order->invoiceUrl() ? $this->renderer->button($order->invoiceUrl(), 'Számla megtekintése') : '',
            'items_table' => '<table width="100%" style="border-collapse:collapse">'.$rows
                .'<tr><td style="border-top:1px solid #eee;padding:8px 0"><strong>Végösszeg</strong></td><td style="border-top:1px solid #eee;text-align:right"><strong>'.huf($order->total_gross).'</strong></td></tr></table>',
            'bank_account' => $this->settings->get('company.bank_account'),
            'carrier' => $order->supplierOrders->first()?->carrier ?? '',
            'tracking_number' => $order->supplierOrders->first()?->tracking_number ?? '',
        ];
    }

    public function forOrder(string $templateKey, Order $order, array $extra = []): void
    {
        $this->send($templateKey, $order->email, $extra + $this->orderVars($order), $order);
    }

    public function forComplaint(string $templateKey, Complaint $complaint, array $extra = []): void
    {
        $url = $complaint->user_id
            ? route('account.complaints.show', $complaint)
            : route('orders.track', $complaint->order->tracking_token);

        $this->send($templateKey, $complaint->email, $extra + [
            'complaint_number' => $complaint->number,
            'complaint_status' => Complaint::STATUSES[$complaint->status] ?? $complaint->status,
            'order_number' => $complaint->order->number,
            'complaint_button' => $this->renderer->button($url, 'Reklamáció megtekintése'),
        ], $complaint);
    }

    public function sendVerifyEmail(User $user): void
    {
        $url = URL::temporarySignedRoute('verification.verify', now()->addHours(48), [
            'id' => $user->getKey(), 'hash' => sha1($user->getEmailForVerification()),
        ]);

        $this->send('account_verify', $user->email, [
            'customer_name' => $user->name,
            'verify_button' => $this->renderer->button($url, 'E-mail cím megerősítése'),
            'verify_url' => $url,
        ], $user);
    }

    public function sendPasswordReset(User $user, string $token): void
    {
        $url = route('password.reset', ['token' => $token, 'email' => $user->email]);

        $this->send('password_reset', $user->email, [
            'customer_name' => $user->name,
            'reset_button' => $this->renderer->button($url, 'Új jelszó beállítása'),
            'reset_url' => $url,
        ], $user);
    }

    public function newsletterVars(NewsletterSubscriber $subscriber): array
    {
        return [
            'customer_name' => $subscriber->name ?: 'Kedves Vásárlónk',
            'confirm_button' => $this->renderer->button(route('newsletter.confirm', $subscriber->token), 'Feliratkozás megerősítése'),
            'unsubscribe_url' => route('newsletter.unsubscribe', $subscriber->token),
        ];
    }
}
